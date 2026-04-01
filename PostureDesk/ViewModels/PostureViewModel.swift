import AppKit
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI

/// Central view model that aggregates all services and drives the menu bar UI.
@Observable
final class PostureViewModel {
    private static let driftThresholdDefaultsKey = "driftThreshold"

    // Services
    let sensorClient = DirectSensorClient()
    let postureAnalyzer = PostureAnalyzer()
    let breakTracker = BreakTracker()
    let fatigueMonitor = FatigueMonitor()
    let surfaceClassifier = SurfaceClassifier()

    // UI State
    var iconState: IconState = .away
    var historyRefreshToken = 0
    var isPaused = false
    private var logCounter = 0

    @ObservationIgnored private var processTimer: Timer?
    @ObservationIgnored private var autoResumeWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?

    // Theme: 0 = system, 1 = light, 2 = dark
    var themeMode: Int = UserDefaults.standard.integer(forKey: "themeMode") {
        didSet { UserDefaults.standard.set(themeMode, forKey: "themeMode") }
    }

    // Dynamic Island variant
    var islandVariant: IslandVariant = IslandVariant(rawValue: UserDefaults.standard.integer(forKey: "islandVariant")) ?? .lidAngle {
        didSet { UserDefaults.standard.set(islandVariant.rawValue, forKey: "islandVariant") }
    }

    // Dynamic Island overlay toggle
    var dynamicIslandEnabled: Bool = UserDefaults.standard.bool(forKey: "dynamicIslandEnabled") {
        didSet {
            UserDefaults.standard.set(dynamicIslandEnabled, forKey: "dynamicIslandEnabled")
            if dynamicIslandEnabled {
                islandManager.show(viewModel: self)
            } else {
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
        didSet { NotificationManager.shared.breakEnabled = breakNotificationsEnabled }
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
        }
    }

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
        ) { [weak self] _ in
            self?.appearanceTick += 1
        }
    }

    deinit {
        processTimer?.invalidate()
        autoResumeWorkItem?.cancel()
        sensorClient.disconnect()
        islandManager.hide()
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    /// Start monitoring — connects sensors and begins processing loop.
    func start() {
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
        NotificationManager.shared.requestPermission()
        postureAnalyzer.driftThreshold = driftThreshold
        sensorClient.connect()

        if dynamicIslandEnabled {
            islandManager.show(viewModel: self)
        }

        processTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processLatestSnapshot()
        }
    }

    /// Calibrate posture baseline from current readings.
    @discardableResult
    func calibrate() -> Bool {
        guard let snapshot = sensorClient.latestSnapshot else { return false }

        let now = Date()
        postureAnalyzer.calibrate(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        breakTracker.resetSession(at: now)
        fatigueMonitor.resetSession()
        finalizeCurrentSession(endedAt: now)

        if !isPaused, isUserPresent {
            startNewSession(at: now)
            updateCurrentSession()
        }

        updateIconState()
        return true
    }

    func recordBreak() {
        breakTracker.recordBreak()
        updateCurrentSession()
        updateIconState()
    }

    func pauseMonitoring(for duration: TimeInterval? = nil) {
        guard !isPaused else { return }

        isPaused = true
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
        let now = Date()
        let result = breakTracker.resume(isActive: isUserPresent, at: now)
        handleBreakTrackerUpdate(result, now: now)
        updateIconState()
    }

    /// Accept the auto-detected surface suggestion.
    func acceptSurfaceSuggestion() {
        selectedSurface = surfaceClassifier.suggestedSurface
        surfaceClassifier.acceptSuggestion()
    }

    /// Dismiss the surface suggestion.
    func dismissSurfaceSuggestion() {
        surfaceClassifier.dismissSuggestion()
    }

    // MARK: - System Idle Time

    private var systemIdleSeconds: Double {
        activityEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }

    private var isUserPresent: Bool {
        systemIdleSeconds < 30
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

        // Feed to all analyzers
        postureAnalyzer.update(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        let breakUpdate = breakTracker.update(isActive: present, at: now)
        fatigueMonitor.update(typingRMS: snapshot.typingRMS, isActive: present)
        surfaceClassifier.currentSurface = selectedSurface
        surfaceClassifier.update(
            pitch: snapshot.pitch,
            roll: snapshot.roll,
            vibrationVariance: snapshot.vibrationVariance,
            fftLow: snapshot.fftLowBin,
            fftMid: snapshot.fftMidBin,
            fftHigh: snapshot.fftHighBin
        )

        postureAnalyzer.driftThreshold = driftThreshold

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
        if sensorClient.connectionError != nil {
            iconState = .unavailable
        } else if isPaused {
            iconState = .away
        } else if breakTracker.state != .active {
            iconState = .away
        } else if postureAnalyzer.isDrifting || postureAnalyzer.driftMagnitude > postureAnalyzer.driftThreshold {
            // Respond immediately to current drift, not just sustained drift
            // (notifications still require sustained drift via PostureAnalyzer.isDrifting)
            iconState = .drifting
        } else if breakTracker.isBreakOverdue {
            iconState = .breakNeeded
        } else {
            iconState = .good
        }
    }

    private func scheduleAutoResume(after duration: TimeInterval) {
        autoResumeWorkItem?.cancel()
        autoResumeWorkItem = nil

        guard duration > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.resumeMonitoring()
        }
        autoResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func sendBreakReminder() {
        NotificationManager.shared.send(
            category: NotificationCategory.breakReminder.rawValue,
            title: "PostureDesk",
            body: "You've been active for \(formatDuration(breakTracker.secondsSinceLastBreak)) without a break. Stand up, stretch, look at something far away."
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Session Persistence

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
        session.surface = selectedSurface
        session.typingIntensityAvailable = fatigueMonitor.hasSessionTypingMetrics
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.sessionAverageIntensity) : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.peakIntensityPercent) : 0
        try? modelContext.save()
    }

    private func finalizeCurrentSession(
        endedAt: Date = Date(),
        totalActiveSeconds: Int? = nil,
        breaksTaken: Int? = nil
    ) {
        guard let session = currentSession else { return }
        let finalizedActiveMinutes = (totalActiveSeconds ?? breakTracker.totalActiveSeconds) / 60

        guard finalizedActiveMinutes > 0 else {
            modelContext.delete(session)
            try? modelContext.save()
            currentSession = nil
            #if DEBUG
            print("[Session] Discarded 0m session")
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
        try? modelContext.save()
        historyRefreshToken &+= 1
        currentSession = nil
        #if DEBUG
        print("[Session] Finalized session (\(session.totalActiveMinutes)m, \(session.postureAlertCount) alerts, \(session.breaksTaken) breaks)")
        #endif
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
