import Foundation

/// Lightweight movement spike detector.
/// Surface selection is manual (via PostureViewModel.selectedSurface).
/// This class only detects large movement events for a future "Did you move?" prompt.
@Observable
final class SurfaceClassifier {

    /// Set to true when a large movement spike is detected. UI can observe and reset.
    var didDetectLargeMovement = false

    func update(vibrationVariance: Double, fftLow: Double, fftMid: Double, fftHigh: Double) {
        if vibrationVariance > 0.05 {
            didDetectLargeMovement = true
        }
    }
}
