import Foundation

/// Handles XPC requests from the PostureDesk app by reading from SensorManager
/// through the SignalProcessor pipeline.
final class XPCServer: NSObject, PostureSensorProtocol {

    private let sensorManager: SensorManager
    private let signalProcessor = SignalProcessor()
    private var latestSnapshot = SensorSnapshot()

    init(sensorManager: SensorManager) {
        self.sensorManager = sensorManager
        super.init()
        startProcessing()
    }

    // MARK: - PostureSensorProtocol

    func getSensorSnapshot(withReply reply: @escaping (SensorSnapshot) -> Void) {
        reply(latestSnapshot)
    }

    func calibrateBaseline(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func getSensorStatus(withReply reply: @escaping (SensorAvailability) -> Void) {
        let availability = SensorAvailability(
            hasAccelerometer: sensorManager.hasAccelerometer,
            hasGyroscope: sensorManager.hasGyroscope,
            hasLidAngle: sensorManager.hasLidAngle
        )
        reply(availability)
    }

    // MARK: - Processing Pipeline

    private func startProcessing() {
        // Feed raw samples into the signal processor
        sensorManager.onAccelSample = { [weak self] sample in
            self?.signalProcessor.processSample(sample)
        }

        // 1Hz snapshot emission
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            signalProcessor.computeSnapshot()

            let snapshot = SensorSnapshot(
                pitch: signalProcessor.pitch,
                roll: signalProcessor.roll,
                lidAngle: sensorManager.currentLidAngle,
                typingRMS: signalProcessor.typingRMS,
                vibrationVariance: signalProcessor.vibrationVariance,
                isActive: signalProcessor.isActive,
                timestamp: Date.timeIntervalSinceReferenceDate,
                fftLowBin: signalProcessor.fftLow,
                fftMidBin: signalProcessor.fftMid,
                fftHighBin: signalProcessor.fftHigh
            )

            self.latestSnapshot = snapshot
        }
    }
}
