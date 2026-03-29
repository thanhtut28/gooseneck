import Foundation

/// Reads sensors directly in-process, bypassing XPC.
/// This is simpler and avoids code-signing issues with XPC mach services.
@Observable
final class DirectSensorClient {

    private(set) var isConnected = false
    private(set) var latestSnapshot: SensorSnapshot?
    private(set) var sensorAvailability: SensorAvailability?

    private let sensorManager = SensorManager()
    private let signalProcessor = SignalProcessor()
    private var snapshotTimer: Timer?

    func connect() {
        sensorManager.start()

        // Feed raw samples directly into the signal processor
        // (IOKit callbacks fire on the main RunLoop, same thread as our timers)
        sensorManager.onAccelSample = { [weak self] sample in
            self?.signalProcessor.processSample(sample)
        }

        // 1Hz snapshot emission
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.signalProcessor.computeSnapshot()

            let snapshot = SensorSnapshot(
                pitch: self.signalProcessor.pitch,
                roll: self.signalProcessor.roll,
                lidAngle: self.sensorManager.currentLidAngle,
                typingRMS: self.signalProcessor.typingRMS,
                vibrationVariance: self.signalProcessor.vibrationVariance,
                isActive: self.signalProcessor.isActive,
                timestamp: Date.timeIntervalSinceReferenceDate,
                fftLowBin: self.signalProcessor.fftLow,
                fftMidBin: self.signalProcessor.fftMid,
                fftHighBin: self.signalProcessor.fftHigh
            )

            self.latestSnapshot = snapshot
            self.isConnected = true
        }

        // Set availability immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.sensorAvailability = SensorAvailability(
                hasAccelerometer: self.sensorManager.hasAccelerometer,
                hasGyroscope: self.sensorManager.hasGyroscope,
                hasLidAngle: self.sensorManager.hasLidAngle
            )
            self.isConnected = true
        }
    }

    func disconnect() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        sensorManager.stop()
        isConnected = false
    }

    func fetchSensorStatus() {
        sensorAvailability = SensorAvailability(
            hasAccelerometer: sensorManager.hasAccelerometer,
            hasGyroscope: sensorManager.hasGyroscope,
            hasLidAngle: sensorManager.hasLidAngle
        )
    }

    func calibrate(completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}
