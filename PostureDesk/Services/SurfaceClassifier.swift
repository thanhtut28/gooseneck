import Foundation

/// Classifies the surface the MacBook is resting on based on sensor data.
/// Uses pitch angle and vibration variance over a sliding window to produce a stable suggestion.
/// Does not auto-switch — emits a `suggestedSurface` that the UI can present as a prompt.
@Observable
final class SurfaceClassifier {

    /// The surface the classifier thinks the device is on.
    private(set) var suggestedSurface: Surface = .unknown

    /// True when the suggestion differs from the current selection and has been stable.
    private(set) var hasPendingSuggestion: Bool = false

    /// Set by PostureViewModel to track what the user currently has selected.
    var currentSurface: Surface = .desk

    // Sliding window of recent classifications (30 seconds at 1Hz)
    private var recentVotes: [Surface] = []
    private let windowSize = 30

    // Stability: only suggest after consistent classification
    private let stabilityThreshold = 0.7  // 70% agreement in window

    /// Large movement detection (for "did you move?" prompt)
    var didDetectLargeMovement = false
    private var lastPitch: Double?
    private let movementThreshold = 8.0  // degrees of sudden pitch change

    /// Process sensor data (called at 1Hz).
    func update(pitch: Double, roll: Double, vibrationVariance: Double,
                fftLow: Double, fftMid: Double, fftHigh: Double) {

        // Detect sudden large movements (possible surface change)
        if let last = lastPitch, abs(pitch - last) > movementThreshold {
            didDetectLargeMovement = true
            // Clear history on large movement — re-evaluate from scratch
            recentVotes.removeAll()
        }
        lastPitch = pitch

        // Classify this sample
        let vote = classifySample(pitch: pitch, roll: roll,
                                  vibrationVariance: vibrationVariance,
                                  fftLow: fftLow, fftMid: fftMid, fftHigh: fftHigh)

        recentVotes.append(vote)
        if recentVotes.count > windowSize {
            recentVotes.removeFirst()
        }

        // Need enough samples before suggesting
        guard recentVotes.count >= windowSize / 2 else { return }

        // Find the majority vote
        let counts = Dictionary(grouping: recentVotes, by: { $0 })
            .mapValues { $0.count }
        guard let (winner, count) = counts.max(by: { $0.value < $1.value }) else { return }

        let ratio = Double(count) / Double(recentVotes.count)

        if ratio >= stabilityThreshold {
            suggestedSurface = winner
            hasPendingSuggestion = (winner != currentSurface && winner != .unknown)
        }
    }

    /// Accept the suggestion — caller should update selectedSurface.
    func acceptSuggestion() {
        hasPendingSuggestion = false
        didDetectLargeMovement = false
    }

    /// Dismiss the suggestion — ignore until next movement.
    func dismissSuggestion() {
        hasPendingSuggestion = false
        didDetectLargeMovement = false
        recentVotes.removeAll()
    }

    // MARK: - Classification Logic

    /// Classify a single sample based on pitch and vibration.
    ///
    /// Heuristics:
    /// - **Desk**: Low absolute pitch (0-8°), low vibration variance (hard surface)
    /// - **Lap**: Moderate pitch (5-25°), moderate vibration (body micro-movements)
    /// - **Couch**: Higher pitch (15°+), high vibration variance (soft cushion)
    ///
    /// The pitch thresholds overlap intentionally — vibration variance breaks ties.
    private func classifySample(pitch: Double, roll: Double,
                                vibrationVariance: Double,
                                fftLow: Double, fftMid: Double, fftHigh: Double) -> Surface {

        let absPitch = abs(pitch)
        let absRoll = abs(roll)

        // High vibration variance = soft surface
        let isHighVibration = vibrationVariance > 0.01
        let isVeryHighVibration = vibrationVariance > 0.03

        // Score each surface
        var deskScore = 0.0
        var lapScore = 0.0
        var couchScore = 0.0

        // Pitch scoring
        if absPitch < 8 {
            deskScore += 3.0
        } else if absPitch < 15 {
            deskScore += 1.0
            lapScore += 2.0
        } else if absPitch < 25 {
            lapScore += 2.0
            couchScore += 1.0
        } else {
            couchScore += 3.0
        }

        // Roll scoring — desk is usually level, lap/couch can tilt
        if absRoll < 3 {
            deskScore += 1.0
        } else if absRoll < 8 {
            lapScore += 0.5
        } else {
            couchScore += 1.0
        }

        // Vibration scoring
        if isVeryHighVibration {
            couchScore += 2.0
            lapScore += 0.5
        } else if isHighVibration {
            lapScore += 1.5
            couchScore += 0.5
        } else {
            deskScore += 1.5
        }

        // FFT: soft surfaces dampen high frequencies
        if fftHigh > 0 {
            let lowToHighRatio = fftLow / max(fftHigh, 0.001)
            if lowToHighRatio > 5 {
                couchScore += 1.0  // Low frequency dominant = soft surface
            } else if lowToHighRatio < 2 {
                deskScore += 0.5   // Balanced = hard surface
            }
        }

        // Return highest score
        if couchScore > lapScore && couchScore > deskScore { return .couch }
        if lapScore > deskScore { return .lap }
        return .desk
    }
}
