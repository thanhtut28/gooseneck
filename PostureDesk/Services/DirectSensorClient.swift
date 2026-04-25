import AppKit
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
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var wasConnectedBeforeSleep = false

    // S4 — Bounded retry on sleep/wake reconnect.
    // Backoff schedule: 0.5s, 1s, 2s, 4s. After exhaustion, fall back to 30s polling
    // until the sensor reappears.
    @ObservationIgnored private var wakeRetryAttempt = 0
    @ObservationIgnored private var wakeRetryWorkItem: DispatchWorkItem?
    @ObservationIgnored private let wakeRetryDelays: [TimeInterval] = [0.5, 1.0, 2.0, 4.0]
    @ObservationIgnored private let wakeFallbackPollInterval: TimeInterval = 30.0

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

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillSleep() }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDidWake() }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let sleepObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            }
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
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
        cancelWakeRetry()
        activeRuntimeGeneration = runtime.suspend()
        if isConnected {
            isConnected = false
        }
    }

    func disconnect() {
        cancelWakeRetry()
        activeRuntimeGeneration = runtime.disconnect()
        latestSnapshot = nil
        if isConnected {
            isConnected = false
        }
    }

    func fetchSensorStatus() {
        publishSensorAvailability(runtime.fetchSensorStatus())
    }

    // MARK: - Sleep/Wake

    private func handleWillSleep() {
        cancelWakeRetry()
        wasConnectedBeforeSleep = isConnected ||
            (connectionError == nil && sensorAvailability?.hasAccelerometer == true)

        if wasConnectedBeforeSleep {
            activeRuntimeGeneration = runtime.suspend()
        }
    }

    private func handleDidWake() {
        guard wasConnectedBeforeSleep else { return }
        wasConnectedBeforeSleep = false

        // S4 — Bounded retry with backoff. IOKit can take variable time to
        // re-enumerate HID devices after wake; a single retry at 1s frequently fails.
        cancelWakeRetry()
        wakeRetryAttempt = 0
        scheduleWakeRetry()
    }

    private func scheduleWakeRetry() {
        let delay: TimeInterval
        if wakeRetryAttempt < wakeRetryDelays.count {
            delay = wakeRetryDelays[wakeRetryAttempt]
        } else {
            // Bounded retries exhausted — fall back to slow polling so we still
            // recover if IOKit re-enumeration takes much longer than expected.
            delay = wakeFallbackPollInterval
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.attemptWakeReconnect() }
        }
        wakeRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func attemptWakeReconnect() {
        wakeRetryWorkItem = nil
        wakeRetryAttempt += 1

        // Initiate connection — runtime serializes wakeSPUDrivers + enumeration on
        // its worker queue, so we are not racing.
        connect(resetPublishedState: false)

        // Defer the availability check past the runtime's internal 1.5s
        // availability resolution window.
        let checkDelay: TimeInterval = 2.0
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.evaluateWakeReconnect() }
        }
        wakeRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + checkDelay, execute: work)
    }

    private func evaluateWakeReconnect() {
        wakeRetryWorkItem = nil

        // If we received a snapshot or accelerometer is reported available, success.
        let availability = runtime.fetchSensorStatus()
        if availability.hasAccelerometer && (isConnected || sensorAvailability?.hasAccelerometer == true) {
            wakeRetryAttempt = 0
            return
        }

        // Still not back. If we've used the bounded retries, surface a user-visible
        // reason and continue polling at the slow cadence.
        if wakeRetryAttempt >= wakeRetryDelays.count {
            publishConnectionError(
                "Sensor unavailable after wake. Retrying every \(Int(wakeFallbackPollInterval))s.",
                clearLatestSnapshot: true
            )
        }

        scheduleWakeRetry()
    }

    private func cancelWakeRetry() {
        wakeRetryWorkItem?.cancel()
        wakeRetryWorkItem = nil
        wakeRetryAttempt = 0
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
    private let initialFreshnessThreshold: TimeInterval = 5.0
    private var retryCount = 0
    private var retryWorkItem: DispatchWorkItem?
    private var hasEverReceivedSample = false
    private let maxInitialRetries = 3
    private let retryBaseDelay: TimeInterval = 2.0
    private let retryMaxDelay: TimeInterval = 8.0

    var onAvailabilityResolved: ((SensorAvailability, Int) -> Void)?
    var onSnapshot: ((SensorSnapshot, Int) -> Void)?
    var onConnectionFailure: ((String, Int) -> Void)?

    deinit {
        _ = disconnect()
    }

    func connect() -> Int {
        processingQueue.sync {
            stopActiveConnection()

            retryCount = 0
            hasEverReceivedSample = false
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

        if !hasEverReceivedSample {
            hasEverReceivedSample = true
        }
        if retryCount > 0 {
            print("[SensorRuntime] Sensor stream recovered after \(retryCount) retry(s)")
            retryCount = 0
        }

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

        // If we've ever received a sample, the hardware exists — keep retrying.
        // Only give up on initial connection if hardware was never detected.
        let shouldRetry = hasEverReceivedSample || retryCount < maxInitialRetries

        if shouldRetry {
            retryCount += 1
            let delay = min(retryBaseDelay * pow(2.0, Double(min(retryCount - 1, 3))), retryMaxDelay)
            print("[SensorRuntime] Connection failed, retry \(retryCount) in \(delay)s")

            stopActiveConnection()

            let currentGeneration = self.generation
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeRetry(for: currentGeneration)
            }
            retryWorkItem = workItem
            processingQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            retryCount = 0
            stopActiveConnection()
            onConnectionFailure?(message, generation)
        }
    }

    private func executeRetry(for generation: Int) {
        retryWorkItem = nil
        guard generation == self.generation else { return }

        signalProcessor = SignalProcessor()
        snapshotMonitoringStartedAt = nil
        lastAccelSampleTimestamp = nil

        let currentGeneration = generation

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
    }

    private func stopActiveConnection() {
        retryWorkItem?.cancel()
        retryWorkItem = nil

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

        // Use a longer threshold during initial connection — IOKit device
        // enumeration can take variable time, especially after wake.
        guard let snapshotMonitoringStartedAt else { return false }
        return now - snapshotMonitoringStartedAt > initialFreshnessThreshold
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
