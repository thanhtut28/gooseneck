import Foundation

/// Reads sensors directly in-process using the shared IOKit sensor pipeline.
@Observable
final class DirectSensorClient {

    private(set) var isConnected = false
    private(set) var latestSnapshot: SensorSnapshot?
    private(set) var sensorAvailability: SensorAvailability?
    private(set) var connectionError: String?

    private let sensorManager = SensorManager()
    private let signalProcessor = SignalProcessor()
    private var snapshotTimer: Timer?
    private var availabilityCheckWorkItem: DispatchWorkItem?
    private var snapshotMonitoringStartedAt: TimeInterval?
    private var lastAccelSampleTimestamp: TimeInterval?
    private let sampleFreshnessThreshold: TimeInterval = 3.0

    func connect() {
        guard snapshotTimer == nil, availabilityCheckWorkItem == nil else { return }

        connectionError = nil
        latestSnapshot = nil
        sensorAvailability = nil
        isConnected = false
        snapshotMonitoringStartedAt = nil
        lastAccelSampleTimestamp = nil

        // Feed raw samples directly into the signal processor
        // (IOKit callbacks fire on the main RunLoop, same thread as our timers)
        sensorManager.onAccelSample = { [weak self] sample in
            self?.lastAccelSampleTimestamp = sample.timestamp
            self?.signalProcessor.processSample(sample)
        }

        sensorManager.start()

        let checkWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            let availability = SensorAvailability(
                hasAccelerometer: self.sensorManager.hasAccelerometer,
                hasGyroscope: self.sensorManager.hasGyroscope,
                hasLidAngle: self.sensorManager.hasLidAngle
            )
            self.sensorAvailability = availability
            self.availabilityCheckWorkItem = nil

            guard availability.hasAccelerometer else {
                self.connectionError = "Accelerometer unavailable. PostureDesk requires an Apple Silicon MacBook."
                self.sensorManager.stop()
                return
            }

            self.startSnapshotTimer()
        }
        availabilityCheckWorkItem = checkWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: checkWorkItem)
    }

    private func startSnapshotTimer() {
        guard snapshotTimer == nil else { return }
        snapshotMonitoringStartedAt = Date.timeIntervalSinceReferenceDate

        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate

            guard self.sensorManager.hasAccelerometer else {
                self.connectionError = "Sensor connection was lost."
                self.disconnect()
                return
            }

            if self.isSensorStreamStale(at: now) {
                self.connectionError = "Sensor data stream stopped. Retry Sensors to reconnect."
                self.disconnect()
                return
            }

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
            self.connectionError = nil
            self.isConnected = true
        }
    }

    func disconnect() {
        availabilityCheckWorkItem?.cancel()
        availabilityCheckWorkItem = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        snapshotMonitoringStartedAt = nil
        lastAccelSampleTimestamp = nil
        sensorManager.onAccelSample = nil
        latestSnapshot = nil
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

    private func isSensorStreamStale(at now: TimeInterval) -> Bool {
        if let lastAccelSampleTimestamp {
            return now - lastAccelSampleTimestamp > sampleFreshnessThreshold
        }

        guard let snapshotMonitoringStartedAt else { return false }
        return now - snapshotMonitoringStartedAt > sampleFreshnessThreshold
    }
}
