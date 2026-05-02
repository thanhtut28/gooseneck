import AppKit
import CoreGraphics
import Foundation
import os
import SwiftData
import SwiftUI

private let storageLog = Logger(subsystem: "com.gooseneck.app", category: "storage")

/// Storage health. Flips to `.failing` after repeated save failures so the UI can surface a banner.
enum StorageHealth: Equatable {
    case ok
    case failing(consecutiveCount: Int, lastError: String)
}

/// Central view model that aggregates all services and drives the menu bar UI.
@MainActor @Observable
final class PostureViewModel {
    private static let driftThresholdDefaultsKey = "driftThreshold"

    // Services
    // Shipping runtime path: the app reads sensors directly in-process.
    let sensorClient = DirectSensorClient()
    let postureAnalyzer = PostureAnalyzer()
    let breakTracker = BreakTracker()
    let fatigueMonitor = FatigueMonitor()
    // UI State
    var iconState: IconState = .away
    var historyRefreshToken = 0
    var isPaused = false
    private var logCounter = 0

    private(set) var storageHealth: StorageHealth = .ok
    @ObservationIgnored private var consecutiveStorageFailures = 0
    private let storageFailureThreshold = 3

    @ObservationIgnored private var processTimer: Timer?
    @ObservationIgnored private var autoResumeWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?
    @ObservationIgnored private var didBecomeActiveObserver: NSObjectProtocol?
    @ObservationIgnored private var monitoringLocked = false

    // Theme: 0 = system, 1 = light, 2 = dark
    var themeMode: Int = UserDefaults.standard.integer(forKey: "themeMode") {
        didSet { UserDefaults.standard.set(themeMode, forKey: "themeMode") }
    }

    // Dynamic Island variant
    var islandVariant: IslandVariant = IslandVariant(rawValue: UserDefaults.standard.integer(forKey: "islandVariant")) ?? .sessionTime {
        didSet { UserDefaults.standard.set(islandVariant.rawValue, forKey: "islandVariant") }
    }

    // Dynamic Island overlay toggle
    var dynamicIslandEnabled: Bool = UserDefaults.standard.bool(forKey: "dynamicIslandEnabled") {
        didSet {
            UserDefaults.standard.set(dynamicIslandEnabled, forKey: "dynamicIslandEnabled")
            if dynamicIslandEnabled, isStarted {
                islandManager.show(viewModel: self)
            } else if !dynamicIslandEnabled {
                islandManager.hide()
            }
        }
    }
    let islandManager = PostureIslandManager()

    var notificationsEnabled: Bool = NotificationManager.shared.notificationsEnabled {
        didSet {
            NotificationManager.shared.notificationsEnabled = notificationsEnabled
        }
    }

    var postureNotificationsEnabled: Bool = NotificationManager.shared.postureEnabled {
        didSet { NotificationManager.shared.postureEnabled = postureNotificationsEnabled }
    }

    var breakNotificationsEnabled: Bool = NotificationManager.shared.breakEnabled {
        didSet {
            NotificationManager.shared.breakEnabled = breakNotificationsEnabled
            if breakNotificationsEnabled && breakTracker.isBreakOverdue {
                breakTracker.resetReminderCadence()
            }
        }
    }

    var fatigueNotificationsEnabled: Bool = NotificationManager.shared.fatigueEnabled {
        didSet { NotificationManager.shared.fatigueEnabled = fatigueNotificationsEnabled }
    }

    var driftThreshold: Double = PostureViewModel.loadDriftThreshold() {
        didSet {
            UserDefaults.standard.set(driftThreshold, forKey: Self.driftThresholdDefaultsKey)
            postureAnalyzer.driftThreshold = driftThreshold
        }
    }

    // Bumped when macOS appearance changes, so preferredColorScheme re-evaluates
    private var appearanceTick: Int = 0

    var preferredColorScheme: ColorScheme {
        _ = appearanceTick
        switch themeMode {
        case 1: return .light
        case 2: return .dark
        default:
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .dark : .light
        }
    }

    // Session persistence
    private let modelContext: ModelContext
    private var currentSession: SessionRecord?
    private var postureAlertCount: Int = 0
    private var wasDrifting = false

    // Manual surface selection (persisted)
    var selectedSurface: Surface = Surface(rawValue: UserDefaults.standard.integer(forKey: "selectedSurface")) ?? .desk {
        didSet {
            UserDefaults.standard.set(selectedSurface.rawValue, forKey: "selectedSurface")
            driftThreshold = selectedSurface.driftThreshold
        }
    }

    // Lid-angle nudge state (smart "did you move?" prompt)
    private(set) var showSurfaceNudge: Bool = false
    @ObservationIgnored private var nudgeSustainedSince: Date?
    @ObservationIgnored private var nudgeDismissedAt: Date?
    private let nudgeLidAngleThreshold: Double = 15.0
    private let nudgeSustainDuration: TimeInterval = 30
    private let nudgeCooldownDuration: TimeInterval = 300

    private let activityEventTypes: [CGEventType] = [
        .keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ]

    enum IconState: String {
        case good = "figure.stand"
        case drifting = "figure.stand.line.dotted.figure.stand"
        case breakNeeded = "clock.badge.exclamationmark"
        case unavailable = "exclamationmark.triangle"
        case away = "moon.zzz"
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        postureAnalyzer.driftThreshold = driftThreshold
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.appearanceTick += 1
            }
        }
        // Re-check system notification permission when app becomes active
        // (user may toggle it in System Settings and return to the app).
        // Installed once here — checkSystemAuthorization() is idempotent.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationManager.shared.checkSystemAuthorization()
        }
        cleanUpOrphanedSessions()
    }

    deinit {
        // deinit is nonisolated; @MainActor classes are always deallocated on main thread
        MainActor.assumeIsolated {
            processTimer?.invalidate()
            autoResumeWorkItem?.cancel()
            sensorClient.disconnect()
            islandManager.hide()
            if let appearanceObserver {
                DistributedNotificationCenter.default().removeObserver(appearanceObserver)
            }
            if let didBecomeActiveObserver {
                NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            }
        }
    }

    /// Start monitoring — connects sensors and begins processing loop.
    func start() {
        guard !monitoringLocked else { return }

        if isStarted {
            if !sensorClient.isConnected {
                sensorClient.connect()
            }
            if dynamicIslandEnabled {
                islandManager.show(viewModel: self)
            }
            return
        }
        isStarted = true

        NotificationManager.shared.notificationsEnabled = notificationsEnabled
        NotificationManager.shared.checkSystemAuthorization()
        postureAnalyzer.driftThreshold = driftThreshold
        sensorClient.connect()

        if dynamicIslandEnabled {
            islandManager.show(viewModel: self)
        }

        processTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.processLatestSnapshot()
            }
        }
    }

    func unlockMonitoring() {
        monitoringLocked = false
    }

    func stop(lockMonitoring: Bool = false, finalizeSession: Bool = true) {
        monitoringLocked = lockMonitoring

        autoResumeWorkItem?.cancel()
        autoResumeWorkItem = nil
        processTimer?.invalidate()
        processTimer = nil

        if finalizeSession {
            finalizeCurrentSession()
        } else {
            discardCurrentSession()
        }

        sensorClient.disconnect()
        islandManager.hide()
        // Note: appearanceObserver and didBecomeActiveObserver are installed once
        // in init() and removed only in deinit — they should survive stop/start cycles.
        fatigueMonitor.resetSession()
        breakTracker.stop()
        showSurfaceNudge = false
        nudgeSustainedSince = nil
        nudgeDismissedAt = nil
        postureAlertCount = 0
        wasDrifting = false
        logCounter = 0
        isPaused = false
        isStarted = false
        if iconState != .away {
            iconState = .away
        }
    }

    /// Recalibrate posture baseline from current readings.
    /// Does NOT reset the session — surface changes and recalibrations are mid-session events.
    @discardableResult
    func calibrate() -> Bool {
        guard let snapshot = sensorClient.latestSnapshot else { return false }

        postureAnalyzer.calibrate(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        showSurfaceNudge = false
        nudgeSustainedSince = nil

        updateIconState()
        return true
    }

    /// Switch surface mid-session. Logs the change, updates thresholds, recalibrates baseline.
    func changeSurface(to newSurface: Surface) {
        let previous = selectedSurface
        selectedSurface = newSurface
        if previous != newSurface {
            currentSession?.recordSurfaceChange(to: newSurface)
        }
        calibrate()
    }

    func recordBreak() {
        breakTracker.recordBreak()
        updateCurrentSession()
        updateIconState()
    }

    func pauseMonitoring(for duration: TimeInterval? = nil) {
        guard !isPaused else { return }

        isPaused = true
        sensorClient.suspend()
        breakTracker.pause()
        updateCurrentSession()
        updateIconState()
        autoResumeWorkItem?.cancel()
        autoResumeWorkItem = nil

        if let duration {
            scheduleAutoResume(after: duration)
        }
    }

    func resumeMonitoring() {
        autoResumeWorkItem?.cancel()
        autoResumeWorkItem = nil

        guard isPaused else { return }

        isPaused = false
        sensorClient.connect(resetPublishedState: false)
        let now = Date()
        let result = breakTracker.resume(isActive: isUserPresent, at: now)
        handleBreakTrackerUpdate(result, now: now)
        updateIconState()
    }

    // MARK: - Surface Nudge

    /// User confirmed they moved — switch surface and recalibrate.
    func acceptSurfaceNudge(to surface: Surface) {
        showSurfaceNudge = false
        nudgeSustainedSince = nil
        nudgeDismissedAt = Date()
        changeSurface(to: surface)
    }

    /// User dismissed the nudge.
    func dismissSurfaceNudge() {
        showSurfaceNudge = false
        nudgeSustainedSince = nil
        nudgeDismissedAt = Date()
    }

    private func checkLidAngleNudge(at now: Date) {
        let drift = abs(postureAnalyzer.lidAngleDrift)

        guard !showSurfaceNudge else { return }
        if let dismissedAt = nudgeDismissedAt,
           now.timeIntervalSince(dismissedAt) < nudgeCooldownDuration {
            return
        }

        if drift > nudgeLidAngleThreshold {
            if nudgeSustainedSince == nil {
                nudgeSustainedSince = now
            } else if let since = nudgeSustainedSince,
                      now.timeIntervalSince(since) >= nudgeSustainDuration {
                showSurfaceNudge = true
            }
        } else {
            nudgeSustainedSince = nil
        }
    }

    // MARK: - System Idle Time

    private var systemIdleSeconds: Double {
        let idle = activityEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
        // Clamp: negative values can occur after system clock adjustments
        return max(0, idle)
    }

    private var isUserPresent: Bool {
        systemIdleSeconds < 30
    }

    /// True when the user actually pressed a key recently. Used to gate typing-
    /// intensity measurement so that fan vibration / trackpad clicks / music
    /// coupling through the chassis do not register as "typing" just because
    /// `isUserPresent` is true. 5-second hysteresis covers brief inter-word
    /// pauses without resetting the recent-window average.
    private var isTyping: Bool {
        let secondsSinceKeyDown = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )
        guard secondsSinceKeyDown >= 0 else { return false }
        return secondsSinceKeyDown < 5
    }

    // MARK: - Processing

    private func processLatestSnapshot() {
        guard !isPaused else { return }
        guard let snapshot = sensorClient.latestSnapshot else {
            updateIconState()
            return
        }

        let now = Date()
        let present = isUserPresent

        // Feed to all analyzers. Break tracking treats any input (mouse, trackpad,
        // keys) as presence; fatigue monitoring requires an actual keyDown so
        // chassis vibration during cursor-only activity is not misread as typing.
        postureAnalyzer.update(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        let breakUpdate = breakTracker.update(isActive: present, at: now)
        fatigueMonitor.update(typingRMS: snapshot.typingRMS, isTyping: isTyping)
        checkLidAngleNudge(at: now)

        // Track posture alerts (drift transitions)
        if postureAnalyzer.isDrifting && !wasDrifting {
            postureAlertCount += 1
        }
        wasDrifting = postureAnalyzer.isDrifting

        handleBreakTrackerUpdate(breakUpdate, now: now)

        if breakUpdate.breakReminderDue {
            sendBreakReminder()
        }

        // Update session record every 30s
        logCounter += 1
        if logCounter % 30 == 0 {
            updateCurrentSession()
            #if DEBUG
            print("[Status] state=\(breakTracker.state) idle=\(String(format: "%.0fs", systemIdleSeconds)) session=\(breakTracker.totalActiveSeconds)s drift=\(String(format: "%.1f°", postureAnalyzer.currentDrift)) typingRMS=\(String(format: "%.6f", snapshot.typingRMS))")
            #endif
        }

        updateIconState()
    }

    private func handleBreakTrackerUpdate(_ result: BreakTrackerUpdateResult, now: Date) {
        if result.startedNewSession {
            finalizeCurrentSession(
                endedAt: result.previousSessionEndedAt ?? now,
                totalActiveSeconds: result.completedSessionActiveSeconds,
                breaksTaken: result.completedSessionBreaksTaken
            )
            fatigueMonitor.resetSession()
            startNewSession(at: now)
        } else if currentSession == nil, result.currentState == .active {
            startNewSession(at: now)
        } else if result.previousState == .active, result.currentState == .away {
            updateCurrentSession()
        }

        if result.previousState != result.currentState {
            #if DEBUG
            print("[Presence] \(result.previousState) → \(result.currentState) (idle: \(String(format: "%.0fs", systemIdleSeconds)), session: \(breakTracker.totalActiveSeconds)s)")
            #endif
        }
    }

    private func updateIconState() {
        let nextState: IconState

        if sensorClient.connectionError != nil {
            nextState = .unavailable
        } else if isPaused {
            nextState = .away
        } else if breakTracker.state != .active {
            nextState = .away
        } else if breakTracker.isBreakOverdue {
            nextState = .breakNeeded
        } else if postureAnalyzer.isDrifting || postureAnalyzer.driftMagnitude > postureAnalyzer.driftThreshold {
            nextState = .drifting
        } else {
            nextState = .good
        }

        if iconState != nextState {
            iconState = nextState
        }
    }

    private func scheduleAutoResume(after duration: TimeInterval) {
        autoResumeWorkItem?.cancel()
        autoResumeWorkItem = nil

        guard duration > 0 else { return }

        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated { [weak self] in
                self?.resumeMonitoring()
            }
        }
        autoResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func sendBreakReminder() {
        NotificationManager.shared.send(
            category: NotificationCategory.breakReminder.rawValue,
            title: "GooseNeck",
            body: "You've been active for \(formatDuration(breakTracker.secondsSinceLastBreak)) without a break. Stand up, stretch, look at something far away."
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    // MARK: - Session Persistence

    /// Save the model context. Tracks consecutive failures and surfaces storage health so the UI can react.
    private func trySave(tag: String) {
        do {
            try modelContext.save()
            consecutiveStorageFailures = 0
            if storageHealth != .ok {
                storageHealth = .ok
            }
        } catch {
            consecutiveStorageFailures += 1
            storageLog.error("Save failed [\(tag, privacy: .public)] attempt \(self.consecutiveStorageFailures): \(error.localizedDescription)")
            if consecutiveStorageFailures >= storageFailureThreshold {
                let newHealth: StorageHealth = .failing(
                    consecutiveCount: consecutiveStorageFailures,
                    lastError: error.localizedDescription
                )
                if storageHealth != newHealth {
                    storageHealth = newHealth
                }
            }
        }
    }

    private func startNewSession(at time: Date = Date()) {
        let session = SessionRecord()
        session.startedAt = time
        session.surface = selectedSurface
        modelContext.insert(session)
        currentSession = session
        postureAlertCount = 0
        wasDrifting = postureAnalyzer.isDrifting
        #if DEBUG
        print("[Session] Started new session")
        #endif
    }

    private func updateCurrentSession() {
        guard let session = currentSession else { return }
        session.totalActiveMinutes = breakTracker.totalActiveSeconds / 60
        session.postureAlertCount = postureAlertCount
        session.breaksTaken = breakTracker.breaksTaken
        session.typingIntensityAvailable = fatigueMonitor.hasSessionTypingMetrics
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.sessionAverageIntensity) : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.peakIntensityPercent) : 0
        trySave(tag: "updateCurrentSession")
    }

    private func finalizeCurrentSession(
        endedAt: Date = Date(),
        totalActiveSeconds: Int? = nil,
        breaksTaken: Int? = nil
    ) {
        guard let session = currentSession else { return }
        let finalizedActiveMinutes = (totalActiveSeconds ?? breakTracker.totalActiveSeconds) / 60

        guard finalizedActiveMinutes >= 2 else {
            modelContext.delete(session)
            trySave(tag: "discardShortSession")
            currentSession = nil
            #if DEBUG
            print("[Session] Discarded short session (\(finalizedActiveMinutes)m < 2m minimum)")
            #endif
            return
        }

        session.endedAt = endedAt
        session.totalActiveMinutes = finalizedActiveMinutes
        session.postureAlertCount = postureAlertCount
        session.breaksTaken = breaksTaken ?? breakTracker.breaksTaken
        session.typingIntensityAvailable = fatigueMonitor.hasSessionTypingMetrics
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.sessionAverageIntensity) : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.peakIntensityPercent) : 0
        fatigueMonitor.persistCurrentBaseline()
        trySave(tag: "finalizeSession")
        historyRefreshToken &+= 1
        currentSession = nil
        #if DEBUG
        print("[Session] Finalized session (\(session.totalActiveMinutes)m, \(session.postureAlertCount) alerts, \(session.breaksTaken) breaks)")
        #endif
    }

    private func discardCurrentSession() {
        guard let session = currentSession else { return }
        modelContext.delete(session)
        trySave(tag: "discardCurrentSession")
        currentSession = nil
    }

    private func cleanUpOrphanedSessions() {
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate<SessionRecord> { $0.endedAt == nil }
        )
        let orphans: [SessionRecord]
        do {
            orphans = try modelContext.fetch(descriptor)
        } catch {
            storageLog.error("Orphan fetch failed: \(error.localizedDescription)")
            return
        }
        guard !orphans.isEmpty else { return }

        for session in orphans {
            if session.totalActiveMinutes >= 2 {
                // Use the later of: estimated end from active minutes, or startedAt + 1min.
                // totalActiveMinutes can be stale by up to 30s at crash time.
                let estimatedEnd = session.startedAt.addingTimeInterval(Double(session.totalActiveMinutes + 1) * 60)
                session.endedAt = min(estimatedEnd, Date())
                #if DEBUG
                print("[Session] Recovered orphaned session: \(session.totalActiveMinutes)m from \(session.startedAt)")
                #endif
            } else {
                modelContext.delete(session)
                #if DEBUG
                print("[Session] Deleted empty orphaned session from \(session.startedAt)")
                #endif
            }
        }
        trySave(tag: "cleanUpOrphans")
    }

}

private extension PostureViewModel {
    static func loadDriftThreshold() -> Double {
        if let storedValue = UserDefaults.standard.object(forKey: driftThresholdDefaultsKey) as? Double {
            return storedValue
        }

        let savedSurface = Surface(rawValue: UserDefaults.standard.integer(forKey: "selectedSurface")) ?? .desk
        return savedSurface.driftThreshold
    }
}
