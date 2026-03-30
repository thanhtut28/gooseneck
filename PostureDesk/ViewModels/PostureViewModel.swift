import AppKit
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI

/// Central view model that aggregates all services and drives the menu bar UI.
@Observable
final class PostureViewModel {

    // Services
    let sensorClient = DirectSensorClient()
    let postureAnalyzer = PostureAnalyzer()
    let breakTracker = BreakTracker()
    let fatigueMonitor = FatigueMonitor()
    let surfaceClassifier = SurfaceClassifier()

    // UI State
    var iconState: IconState = .away
    var isPaused = false
    private var logCounter = 0

    // Theme: 0 = system, 1 = light, 2 = dark
    var themeMode: Int = UserDefaults.standard.integer(forKey: "themeMode") {
        didSet { UserDefaults.standard.set(themeMode, forKey: "themeMode") }
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
            return (isDark ?? true) ? .dark : .light
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
            postureAnalyzer.driftThreshold = selectedSurface.driftThreshold
        }
    }

    enum IconState: String {
        case good = "figure.stand"
        case drifting = "figure.stand.line.dotted.figure.stand"
        case breakNeeded = "clock.badge.exclamationmark"
        case away = "moon.zzz"
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.appearanceTick += 1
        }
    }

    /// Start monitoring — connects sensors and begins processing loop.
    func start() {
        NotificationManager.shared.requestPermission()
        postureAnalyzer.driftThreshold = selectedSurface.driftThreshold
        sensorClient.connect()

        // Process snapshots as they arrive
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processLatestSnapshot()
        }
    }

    /// Calibrate posture baseline from current readings.
    func calibrate() {
        guard let snapshot = sensorClient.latestSnapshot else { return }
        postureAnalyzer.calibrate(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        breakTracker.resetSession()
        fatigueMonitor.resetSession()
        finalizeCurrentSession()
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
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    private var isUserPresent: Bool {
        systemIdleSeconds < 30
    }

    // MARK: - Processing

    private func processLatestSnapshot() {
        guard !isPaused, let snapshot = sensorClient.latestSnapshot else { return }

        let present = isUserPresent
        let oldState = breakTracker.state

        // Feed to all analyzers
        postureAnalyzer.update(pitch: snapshot.pitch, lidAngle: snapshot.lidAngle)
        breakTracker.update(isActive: present)
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

        postureAnalyzer.driftThreshold = selectedSurface.driftThreshold

        // Track posture alerts (drift transitions)
        if postureAnalyzer.isDrifting && !wasDrifting {
            postureAlertCount += 1
        }
        wasDrifting = postureAnalyzer.isDrifting

        // Session lifecycle
        if breakTracker.state != oldState {
            if breakTracker.state == .active && oldState == .away {
                startNewSession()
            } else if breakTracker.state == .away && oldState == .active {
                // Will finalize if user stays away for 5+ min (handled by BreakTracker)
                updateCurrentSession()
            }
            #if DEBUG
            print("[Presence] \(oldState) → \(breakTracker.state) (idle: \(String(format: "%.0fs", systemIdleSeconds)), session: \(breakTracker.totalActiveSeconds)s)")
            #endif
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

    private func updateIconState() {
        if breakTracker.state == .away {
            iconState = .away
        } else if postureAnalyzer.isDrifting || postureAnalyzer.driftMagnitude > postureAnalyzer.driftThreshold {
            // Respond immediately to current drift, not just sustained drift
            // (notifications still require sustained drift via PostureAnalyzer.isDrifting)
            iconState = .drifting
        } else if breakTracker.secondsSinceLastBreak > breakTracker.breakIntervalMinutes * 60 {
            iconState = .breakNeeded
        } else {
            iconState = .good
        }
    }

    // MARK: - Session Persistence

    private func startNewSession() {
        // Finalize any stale session
        finalizeCurrentSession()

        let session = SessionRecord()
        session.startedAt = Date()
        session.surface = selectedSurface
        modelContext.insert(session)
        currentSession = session
        postureAlertCount = 0
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
        session.avgTypingIntensity = fatigueMonitor.currentIntensityPercent
        session.peakTypingIntensity = fatigueMonitor.peakIntensityPercent
        try? modelContext.save()
    }

    private func finalizeCurrentSession() {
        guard let session = currentSession else { return }
        session.endedAt = Date()
        session.totalActiveMinutes = breakTracker.totalActiveSeconds / 60
        session.postureAlertCount = postureAlertCount
        session.breaksTaken = breakTracker.breaksTaken
        session.avgTypingIntensity = fatigueMonitor.currentIntensityPercent
        session.peakTypingIntensity = fatigueMonitor.peakIntensityPercent
        try? modelContext.save()
        currentSession = nil
        #if DEBUG
        print("[Session] Finalized session (\(session.totalActiveMinutes)m, \(session.postureAlertCount) alerts, \(session.breaksTaken) breaks)")
        #endif
    }
}
