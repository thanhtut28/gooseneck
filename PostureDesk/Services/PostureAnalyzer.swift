import Foundation

/// Detects sustained posture drift from calibrated baseline.
/// Uses a 90-second sliding window to distinguish gradual slouching from intentional adjustments.
@MainActor @Observable
final class PostureAnalyzer {
    private let notifyDriftEpisode: @MainActor (Double) -> Void

    private(set) var currentDrift: Double = 0       // Signed combined drift
    private(set) var driftMagnitude: Double = 0     // Absolute combined drift for threshold
    private(set) var pitchDrift: Double = 0         // Signed tilt drift (device pitch)
    private(set) var lidAngleDrift: Double = 0      // Signed lid angle drift
    private(set) var isDrifting: Bool = false
    private(set) var baselinePitch: Double = 0
    private(set) var baselineLidAngle: Double = 0

    private var isCalibrated = false
    private var warmupCount = 0
    private let warmupSeconds = 5  // Wait for AHRS to stabilize
    private var driftHistory: [(timestamp: Date, drift: Double)] = []
    private let windowDuration: TimeInterval = 90
    private var hasSentNotificationForCurrentEpisode = false

    /// Current surface-aware drift threshold
    var driftThreshold: Double = 10.0

    init(
        notifyDriftEpisode: @MainActor @escaping (Double) -> Void = { driftMagnitude in
            NotificationManager.shared.send(
                category: NotificationCategory.posture.rawValue,
                title: "GooseNeck",
                body: String(format: "You've shifted %.0f° from your baseline. Time for a quick readjust?", driftMagnitude)
            )
        }
    ) {
        self.notifyDriftEpisode = notifyDriftEpisode
    }

    /// Calibrate baseline with current sensor readings.
    func calibrate(pitch: Double, lidAngle: Double) {
        baselinePitch = pitch
        baselineLidAngle = lidAngle
        isCalibrated = true
        warmupCount = warmupSeconds  // Skip warmup on manual calibrate
        driftHistory.removeAll()
        isDrifting = false
        currentDrift = 0
        pitchDrift = 0
        lidAngleDrift = 0
        driftMagnitude = 0
        hasSentNotificationForCurrentEpisode = false
    }

    /// Process a new sensor snapshot (called at 1Hz).
    func update(pitch: Double, lidAngle: Double) {
        // Wait for AHRS to stabilize before auto-calibrating
        if !isCalibrated {
            warmupCount += 1
            if warmupCount >= warmupSeconds {
                calibrate(pitch: pitch, lidAngle: lidAngle)
            }
            return
        }

        // Separate signed drifts for each axis
        pitchDrift = pitch - baselinePitch
        lidAngleDrift = lidAngle >= 0 ? (lidAngle - baselineLidAngle) : 0.0

        // Combined
        currentDrift = pitchDrift + lidAngleDrift
        driftMagnitude = abs(pitchDrift) + abs(lidAngleDrift)

        let now = Date()
        driftHistory.append((timestamp: now, drift: driftMagnitude))

        // Trim to window
        let cutoff = now.addingTimeInterval(-windowDuration)
        driftHistory.removeAll { $0.timestamp < cutoff }

        // Check for sustained drift with upward trend
        isDrifting = checkSustainedDrift()

        if isDrifting {
            if !hasSentNotificationForCurrentEpisode {
                notifyDriftEpisode(driftMagnitude)
                hasSentNotificationForCurrentEpisode = true
            }
        } else {
            hasSentNotificationForCurrentEpisode = false
        }
    }

    /// Check if drift has been sustained and trending upward over the window.
    private func checkSustainedDrift() -> Bool {
        guard driftHistory.count >= 10 else { return false }

        guard driftMagnitude > driftThreshold else { return false }

        let aboveThresholdCount = driftHistory.filter { $0.drift > driftThreshold * 0.8 }.count
        let ratio = Double(aboveThresholdCount) / Double(driftHistory.count)
        guard ratio > 0.7 else { return false }

        return true
    }
}
