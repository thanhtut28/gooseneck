import Foundation
import Observation

/// Reads sensors directly in-process using the shared IOKit sensor pipeline.
@MainActor @Observable
final class DirectSensorClient {

    private(set) var isConnected = false
    private(set) var latestSnapshot: SensorSnapshot?
    private(set) var sensorAvailability: SensorAvailability?
    private(set) var connectionError: String?

    @ObservationIgnored private let runtime = SensorRuntime()
    @ObservationIgnored private var activeRuntimeGeneration = 0

    init() {
        runtime.onAvailabilityResolved = { [weak self] availability, generation in
            Task { @MainActor in
                guard let self, generation == self.activeRuntimeGeneration else { return }
                self.publishSensorAvailability(availability)

                guard !availability.hasAccelerometer else { return }
                self.publishConnectionError(
                    "Accelerometer unavailable. GooseNeck requires an Apple Silicon MacBook.",
                    clearLatestSnapshot: false
                )
            }
        }

        runtime.onSnapshot = { [weak self] snapshot, generation in
            Task { @MainActor in
                guard let self, generation == self.activeRuntimeGeneration else { return }
                self.publishSnapshot(snapshot)
            }
        }

        runtime.onConnectionFailure = { [weak self] message, generation in
            Task { @MainActor in
                guard let self, generation == self.activeRuntimeGeneration else { return }
                self.publishConnectionError(message, clearLatestSnapshot: true)
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            _ = runtime.disconnect()
        }
    }

    func connect(resetPublishedState: Bool = true) {
        activeRuntimeGeneration = runtime.connect()

        if resetPublishedState {
            latestSnapshot = nil
            sensorAvailability = nil
        }

        if connectionError != nil {
            connectionError = nil
        }
        if isConnected {
            isConnected = false
        }
    }

    func suspend() {
        activeRuntimeGeneration = runtime.suspend()
        if isConnected {
            isConnected = false
        }
    }

    func disconnect() {
        activeRuntimeGeneration = runtime.disconnect()
        latestSnapshot = nil
        if isConnected {
            isConnected = false
        }
    }

    func fetchSensorStatus() {
        publishSensorAvailability(runtime.fetchSensorStatus())
    }

    private func publishSensorAvailability(_ availability: SensorAvailability) {
        if sensorAvailability?.matches(availability) == true {
            return
        }
        sensorAvailability = availability
    }

    private func publishSnapshot(_ snapshot: SensorSnapshot) {
        if latestSnapshot?.matchesMeasurementPayload(of: snapshot) != true {
            latestSnapshot = snapshot
        }

        if connectionError != nil {
            connectionError = nil
        }
        if !isConnected {
            isConnected = true
        }
    }

    private func publishConnectionError(_ message: String, clearLatestSnapshot: Bool) {
        if connectionError != message {
            connectionError = message
        }
        if clearLatestSnapshot {
            latestSnapshot = nil
        }
        if isConnected {
            isConnected = false
        }
    }
}

private final class SensorRuntime {
    private let processingQueue = DispatchQueue(label: "com.gooseneck.sensor-processing", qos: .userInitiated)
    private let sensorManager = SensorManager()
    private var signalProcessor = SignalProcessor()
    private var snapshotTimer: DispatchSourceTimer?
    private var availabilityCheckWorkItem: DispatchWorkItem?
    private var snapshotMonitoringStartedAt: TimeInterval?
    private var lastAccelSampleTimestamp: TimeInterval?
    private var generation = 0
    private let sampleFreshnessThreshold: TimeInterval = 3.0

    var onAvailabilityResolved: ((SensorAvailability, Int) -> Void)?
    var onSnapshot: ((SensorSnapshot, Int) -> Void)?
    var onConnectionFailure: ((String, Int) -> Void)?

    deinit {
        _ = disconnect()
    }

    func connect() -> Int {
        processingQueue.sync {
            stopActiveConnection()

            generation += 1
            let currentGeneration = generation
            signalProcessor = SignalProcessor()
            snapshotMonitoringStartedAt = nil
            lastAccelSampleTimestamp = nil

            sensorManager.onAccelSample = { [weak self] sample in
                self?.processingQueue.async { [weak self] in
                    self?.handleAccelerometerSample(sample, generation: currentGeneration)
                }
            }

            sensorManager.start()

            let workItem = DispatchWorkItem { [weak self] in
                self?.resolveSensorAvailability(for: currentGeneration)
            }
            availabilityCheckWorkItem = workItem
            processingQueue.asyncAfter(deadline: .now() + 1.5, execute: workItem)

            return currentGeneration
        }
    }

    func suspend() -> Int {
        processingQueue.sync {
            generation += 1
            stopActiveConnection()
            return generation
        }
    }

    func disconnect() -> Int {
        processingQueue.sync {
            generation += 1
            stopActiveConnection()
            return generation
        }
    }

    func fetchSensorStatus() -> SensorAvailability {
        processingQueue.sync {
            SensorAvailability(
                hasAccelerometer: sensorManager.hasAccelerometer,
                hasGyroscope: sensorManager.hasGyroscope,
                hasLidAngle: sensorManager.hasLidAngle
            )
        }
    }

    private func handleAccelerometerSample(_ sample: AccelSample, generation: Int) {
        guard generation == self.generation else { return }

        lastAccelSampleTimestamp = sample.timestamp
        signalProcessor.processSample(sample)
    }

    private func resolveSensorAvailability(for generation: Int) {
        guard generation == self.generation else { return }

        availabilityCheckWorkItem = nil

        let availability = SensorAvailability(
            hasAccelerometer: sensorManager.hasAccelerometer,
            hasGyroscope: sensorManager.hasGyroscope,
            hasLidAngle: sensorManager.hasLidAngle
        )
        onAvailabilityResolved?(availability, generation)

        guard availability.hasAccelerometer else {
            stopActiveConnection()
            return
        }

        startSnapshotTimer(for: generation)
    }

    private func startSnapshotTimer(for generation: Int) {
        guard snapshotTimer == nil else { return }

        snapshotMonitoringStartedAt = Date.timeIntervalSinceReferenceDate

        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.produceSnapshot(for: generation)
        }
        snapshotTimer = timer
        timer.activate()
    }

    private func produceSnapshot(for generation: Int) {
        guard generation == self.generation else { return }

        let now = Date.timeIntervalSinceReferenceDate

        guard sensorManager.hasAccelerometer else {
            failConnection("Sensor connection was lost.", generation: generation)
            return
        }

        if isSensorStreamStale(at: now) {
            failConnection("Sensor data stream stopped. Retry Sensors to reconnect.", generation: generation)
            return
        }

        signalProcessor.computeSnapshot()

        let snapshot = SensorSnapshot(
            pitch: signalProcessor.pitch,
            roll: signalProcessor.roll,
            lidAngle: sensorManager.currentLidAngle,
            typingRMS: signalProcessor.typingRMS,
            vibrationVariance: signalProcessor.vibrationVariance,
            isActive: signalProcessor.isActive,
            timestamp: now,
            fftLowBin: signalProcessor.fftLow,
            fftMidBin: signalProcessor.fftMid,
            fftHighBin: signalProcessor.fftHigh
        )

        onSnapshot?(snapshot, generation)
    }

    private func failConnection(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        stopActiveConnection()
        onConnectionFailure?(message, generation)
    }

    private func stopActiveConnection() {
        availabilityCheckWorkItem?.cancel()
        availabilityCheckWorkItem = nil

        if let snapshotTimer {
            snapshotTimer.setEventHandler {}
            snapshotTimer.cancel()
            self.snapshotTimer = nil
        }

        snapshotMonitoringStartedAt = nil
        lastAccelSampleTimestamp = nil
        sensorManager.onAccelSample = nil
        sensorManager.stop()
    }

    private func isSensorStreamStale(at now: TimeInterval) -> Bool {
        if let lastAccelSampleTimestamp {
            return now - lastAccelSampleTimestamp > sampleFreshnessThreshold
        }

        guard let snapshotMonitoringStartedAt else { return false }
        return now - snapshotMonitoringStartedAt > sampleFreshnessThreshold
    }
}

private extension SensorSnapshot {
    func matchesMeasurementPayload(of other: SensorSnapshot) -> Bool {
        pitch == other.pitch &&
        roll == other.roll &&
        lidAngle == other.lidAngle &&
        typingRMS == other.typingRMS &&
        vibrationVariance == other.vibrationVariance &&
        isActive == other.isActive &&
        fftLowBin == other.fftLowBin &&
        fftMidBin == other.fftMidBin &&
        fftHighBin == other.fftHighBin
    }
}

private extension SensorAvailability {
    func matches(_ other: SensorAvailability) -> Bool {
        hasAccelerometer == other.hasAccelerometer &&
        hasGyroscope == other.hasGyroscope &&
        hasLidAngle == other.hasLidAngle
    }
}
