import Foundation

/// Monitors typing intensity over time and alerts when fatigue indicators appear.
/// Compares rolling 5-minute average against session baseline (first 15 minutes).
@Observable
final class FatigueMonitor {

    private(set) var currentIntensityPercent: Double = 0  // % above baseline
    private(set) var isFatigued: Bool = false
    private(set) var baselineRMS: Double = 0
    private(set) var intensityHistory: [Double] = []     // Last 5 min of intensity %
    private(set) var peakIntensityPercent: Double = 0

    /// Threshold: alert when intensity exceeds baseline by this percentage
    var fatigueThresholdPercent: Double = 30.0

    // Internal state
    private var baselineSamples: [Double] = []
    private var recentSamples: [Double] = []      // Last 5 minutes
    private var isBaselineSet = false
    private var sessionStartTime: Date?
    private let baselineDuration: TimeInterval = 15 * 60
    private let rollingWindowSize = 300                    // 5 minutes at 1Hz
    private var fatigueStartTime: Date?
    private let fatigueSustainedDuration: TimeInterval = 5 * 60  // Must sustain for 5 min

    /// Process typing RMS from sensor snapshot (called at 1Hz).
    /// Only process when user is actively typing.
    func update(typingRMS: Double, isActive: Bool) {
        guard isActive, typingRMS > 0.0001 else { return }

        let now = Date()

        if sessionStartTime == nil {
            sessionStartTime = now
        }

        // Building baseline (first 15 minutes)
        if !isBaselineSet {
            baselineSamples.append(typingRMS)

            if let start = sessionStartTime, now.timeIntervalSince(start) >= baselineDuration {
                // Baseline period complete
                baselineRMS = baselineSamples.reduce(0, +) / Double(baselineSamples.count)
                isBaselineSet = true
            }
            return
        }

        // After baseline is set, track rolling window
        recentSamples.append(typingRMS)
        if recentSamples.count > rollingWindowSize {
            recentSamples.removeFirst(recentSamples.count - rollingWindowSize)
        }

        // Compute current rolling average
        let currentAvg = recentSamples.reduce(0, +) / Double(recentSamples.count)

        // Calculate percentage above baseline
        if baselineRMS > 0 {
            currentIntensityPercent = ((currentAvg - baselineRMS) / baselineRMS) * 100.0
            peakIntensityPercent = max(peakIntensityPercent, currentIntensityPercent)

            // Keep last 5 min of intensity values for sparkline
            intensityHistory.append(max(0, currentIntensityPercent))
            if intensityHistory.count > 300 {
                intensityHistory.removeFirst(intensityHistory.count - 300)
            }
        }

        // Check for sustained fatigue
        if currentIntensityPercent > fatigueThresholdPercent {
            if fatigueStartTime == nil {
                fatigueStartTime = now
            }

            if let start = fatigueStartTime,
               now.timeIntervalSince(start) >= fatigueSustainedDuration {
                isFatigued = true
                NotificationManager.shared.send(
                    category: "fatigue",
                    title: "PostureDesk",
                    body: String(format: "Your typing intensity is up %.0f%% from your session start. Your hands might need a rest.", currentIntensityPercent)
                )
                // Reset to prevent immediate re-trigger
                fatigueStartTime = nil
            }
        } else {
            fatigueStartTime = nil
            isFatigued = false
        }
    }

    /// Reset for a new session.
    func resetSession() {
        baselineSamples.removeAll()
        recentSamples.removeAll()
        intensityHistory.removeAll()
        isBaselineSet = false
        baselineRMS = 0
        currentIntensityPercent = 0
        peakIntensityPercent = 0
        isFatigued = false
        sessionStartTime = nil
        fatigueStartTime = nil
    }
}
