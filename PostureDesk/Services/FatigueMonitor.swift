import Foundation

enum TypingCalibrationState: Equatable {
    case unavailable
    case bootstrapping
    case ready
}

/// Monitors typing intensity over time and alerts when fatigue indicators appear.
/// Uses a persisted rolling baseline so short sessions can start with a warm baseline.
@MainActor @Observable
final class FatigueMonitor {

    private(set) var currentIntensityPercent: Double = 0  // % above baseline
    private(set) var isFatigued: Bool = false
    private(set) var baselineRMS: Double = 0
    private(set) var intensityHistory: [Double] = []     // Last 5 min of intensity %
    private(set) var peakIntensityPercent: Double = 0
    private(set) var calibrationState: TypingCalibrationState = .unavailable
    private(set) var bootstrapProgress: Double = 0       // 0.0–1.0 during bootstrapping
    private(set) var hasSessionTypingMetrics = false
    /// True iff the user is actively typing (last keyDown within the gating
    /// window). Use this in the UI to distinguish "intensity is 0% because the
    /// user is at-baseline while typing" from "intensity is 0% because the
    /// user isn't typing at all". The two reads are semantically very different.
    private(set) var isCurrentlyTyping: Bool = false

    /// True session average intensity (not a point-in-time snapshot).
    var sessionAverageIntensity: Double {
        guard sessionIntensitySampleCount > 0 else { return 0 }
        return sessionIntensitySum / Double(sessionIntensitySampleCount)
    }

    /// Threshold: alert when intensity exceeds baseline by this percentage
    var fatigueThresholdPercent: Double = FatigueMonitor.loadFatigueThresholdPercent() {
        didSet {
            UserDefaults.standard.set(fatigueThresholdPercent, forKey: Self.fatigueThresholdDefaultsKey)
        }
    }

    // Internal state — baseline
    private var sessionSampleCount: Int = 0
    private var sessionBaselineMean: Double = 0
    private var persistedBaseline: Double = 0
    private var persistedBaselineWeight: Double = 0  // after time-decay

    // Internal state — recent window
    private var recentSamples: [Double] = []
    private let recentWindowSize = 120                        // 2 minutes at 1Hz

    // Internal state — fatigue
    private var fatigueStartTime: Date?
    private let fatigueSustainedDuration: TimeInterval = 5 * 60
    private var hasSentNotificationForCurrentEpisode = false

    // Internal state — session average tracking
    private var sessionIntensitySum: Double = 0
    private var sessionIntensitySampleCount: Int = 0

    // Internal state — typing-burst detection
    private var wasTyping = false

    // Constants
    private let minimumTypingRMS = 0.0001
    private let bootstrapMinimumSamples = 60
    private let baselineTransitionSamples: Double = 600      // 10 min to full session weight
    private let minimumPersistedWeight: Double = 0.3

    // UserDefaults keys
    private let baselineRMSDefaultsKey = "typingBaselineRMS"
    private let baselineSampleCountDefaultsKey = "typingBaselineSampleCount"
    private let baselineUpdatedAtDefaultsKey = "typingBaselineUpdatedAt"
    private static let fatigueThresholdDefaultsKey = "fatigueThresholdPercent"

    init() {
        restorePersistedBaseline()
    }

    /// Process typing RMS from sensor snapshot (called at 1Hz).
    ///
    /// `isTyping` must be true only when an actual keyDown event was generated
    /// recently — passing `isUserPresent` (any input) here would conflate
    /// fan / trackpad / environmental vibration with typing intensity.
    func update(typingRMS: Double, isTyping: Bool) {
        // Typing-burst return detection: clear recent window when typing resumes
        // after a pause, so the average reflects current activity not stale data.
        if isTyping && !wasTyping {
            recentSamples.removeAll()
        }
        wasTyping = isTyping
        if isCurrentlyTyping != isTyping {
            isCurrentlyTyping = isTyping
        }

        guard isTyping, typingRMS > minimumTypingRMS else {
            if currentIntensityPercent != 0 {
                currentIntensityPercent = 0
            }
            fatigueStartTime = nil
            if isFatigued {
                isFatigued = false
            }
            hasSentNotificationForCurrentEpisode = false
            return
        }

        // Accumulate into session baseline (incremental mean, never capped)
        sessionSampleCount += 1
        sessionBaselineMean += (typingRMS - sessionBaselineMean) / Double(sessionSampleCount)

        // Bootstrap: need minimum samples before we have a baseline
        if baselineRMS <= 0 {
            if calibrationState != .bootstrapping {
                calibrationState = .bootstrapping
            }
            // Update bootstrap progress before early return
            let progress = min(1.0, Double(sessionSampleCount) / Double(bootstrapMinimumSamples))
            if bootstrapProgress != progress {
                bootstrapProgress = progress
            }
            guard sessionSampleCount >= bootstrapMinimumSamples else { return }
            baselineRMS = sessionBaselineMean
            if calibrationState != .ready {
                calibrationState = .ready
            }
            if bootstrapProgress != 1.0 {
                bootstrapProgress = 1.0
            }
        }

        guard calibrationState == .ready else { return }

        // Compute blended baseline: linear interpolation from startWeight down to 0.3
        // weight = max(0.3, startWeight - (sessionSampleCount / 600) * (startWeight - 0.3))
        let startWeight = persistedBaseline > 0 ? persistedBaselineWeight : 0
        if persistedBaseline > 0 {
            let sessionFraction = min(1.0, Double(sessionSampleCount) / baselineTransitionSamples)
            let weight = max(minimumPersistedWeight,
                             startWeight - sessionFraction * (startWeight - minimumPersistedWeight))
            baselineRMS = persistedBaseline * weight + sessionBaselineMean * (1.0 - weight)
        } else {
            baselineRMS = sessionBaselineMean
        }

        // Recent window for intensity calculation (2 min)
        recentSamples.append(typingRMS)
        if recentSamples.count > recentWindowSize {
            recentSamples.removeFirst(recentSamples.count - recentWindowSize)
        }

        guard !recentSamples.isEmpty else { return }
        let recentAvg = recentSamples.reduce(0, +) / Double(recentSamples.count)
        let intensityPercent = baselineRMS > 0
            ? min(100, ((recentAvg - baselineRMS) / baselineRMS) * 100.0)
            : 0.0
        if currentIntensityPercent != intensityPercent {
            currentIntensityPercent = intensityPercent
        }

        if currentIntensityPercent > peakIntensityPercent {
            peakIntensityPercent = currentIntensityPercent
        }
        if !hasSessionTypingMetrics {
            hasSessionTypingMetrics = true
        }

        // Track session average
        sessionIntensitySum += max(0, currentIntensityPercent)
        sessionIntensitySampleCount += 1

        // Intensity history for sparkline (5 min)
        intensityHistory.append(max(0, currentIntensityPercent))
        if intensityHistory.count > 300 {
            intensityHistory = Array(intensityHistory.suffix(300))
        }

        // Sustained fatigue detection
        checkFatigue()
    }

    /// Reset per-session state without discarding the persisted typing baseline.
    func resetSession() {
        // Persist baseline before clearing
        persistCurrentBaseline()

        sessionSampleCount = 0
        sessionBaselineMean = 0
        recentSamples.removeAll()
        intensityHistory.removeAll()
        if currentIntensityPercent != 0 {
            currentIntensityPercent = 0
        }
        if peakIntensityPercent != 0 {
            peakIntensityPercent = 0
        }
        if isFatigued {
            isFatigued = false
        }
        fatigueStartTime = nil
        hasSentNotificationForCurrentEpisode = false
        if hasSessionTypingMetrics {
            hasSessionTypingMetrics = false
        }
        sessionIntensitySum = 0
        sessionIntensitySampleCount = 0
        wasTyping = false
        if isCurrentlyTyping {
            isCurrentlyTyping = false
        }
        if bootstrapProgress != 0 {
            bootstrapProgress = 0
        }

        restorePersistedBaseline()
    }

    /// Persist current baseline to UserDefaults. Call at session end.
    func persistCurrentBaseline() {
        guard baselineRMS > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(baselineRMS, forKey: baselineRMSDefaultsKey)
        defaults.set(sessionSampleCount, forKey: baselineSampleCountDefaultsKey)
        defaults.set(Date.timeIntervalSinceReferenceDate, forKey: baselineUpdatedAtDefaultsKey)
    }

    private func checkFatigue() {
        let now = Date()
        if currentIntensityPercent > fatigueThresholdPercent {
            if fatigueStartTime == nil {
                fatigueStartTime = now
            }
            if let start = fatigueStartTime,
               now.timeIntervalSince(start) >= fatigueSustainedDuration {
                if !isFatigued {
                    isFatigued = true
                }
                if !hasSentNotificationForCurrentEpisode {
                    NotificationManager.shared.send(
                        category: NotificationCategory.fatigue.rawValue,
                        title: "GooseNeck",
                        body: String(format: "Your typing intensity is up %.0f%% from your session baseline. Your hands might need a rest.", currentIntensityPercent)
                    )
                    hasSentNotificationForCurrentEpisode = true
                }
            }
        } else {
            fatigueStartTime = nil
            if isFatigued {
                isFatigued = false
            }
            hasSentNotificationForCurrentEpisode = false
        }
    }

    private func restorePersistedBaseline() {
        let defaults = UserDefaults.standard
        let storedBaseline = defaults.double(forKey: baselineRMSDefaultsKey)
        let storedSampleCount = defaults.integer(forKey: baselineSampleCountDefaultsKey)
        let storedUpdatedAt = defaults.double(forKey: baselineUpdatedAtDefaultsKey)

        guard storedBaseline.isFinite, storedBaseline > 0, storedSampleCount > 0 else {
            baselineRMS = 0
            persistedBaseline = 0
            persistedBaselineWeight = 0
            calibrationState = .unavailable
            return
        }

        // Apply time-decay using calendar days so DST / clock adjustments don't inflate the baseline.
        let stored = Date(timeIntervalSinceReferenceDate: storedUpdatedAt)
        let rawDays = Calendar.current.dateComponents([.day], from: stored, to: Date()).day ?? 0
        let daysSince = max(0, Double(rawDays))
        let decayedWeight = max(0.3, 0.8 - 0.1 * daysSince)

        persistedBaseline = storedBaseline
        persistedBaselineWeight = decayedWeight
        baselineRMS = storedBaseline
        calibrationState = .ready
    }

    private static func loadFatigueThresholdPercent() -> Double {
        let storedValue = UserDefaults.standard.object(forKey: fatigueThresholdDefaultsKey) as? Double
        return storedValue ?? 30.0
    }
}
