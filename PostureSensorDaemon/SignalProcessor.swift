import Foundation

/// Processes raw accelerometer samples through the signal processing pipeline:
/// Raw IMU → Gravity removal → Mahony AHRS → Bandpass → FFT → SensorSnapshot
final class SignalProcessor {

    // Filters
    private var gravityFilter = GravityFilter()
    private let ahrs: MahonyAHRS
    private let bandpass: BandpassFilter
    private let fftAnalyzer: FFTAnalyzer

    // Accumulation buffers (1 second at ~100Hz)
    private var dynamicSamples: [(dx: Double, dy: Double, dz: Double)] = []
    private var bandpassBuffer: [Double] = []  // Magnitude of bandpass-filtered dynamic accel
    private let lock = NSLock()

    // Latest processed values
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var typingRMS: Double = 0
    private(set) var vibrationVariance: Double = 0
    private(set) var fftLow: Double = 0
    private(set) var fftMid: Double = 0
    private(set) var fftHigh: Double = 0
    private(set) var isActive: Bool = false

    init(sampleRate: Double = 100.0) {
        ahrs = MahonyAHRS(kp: 4.0, ki: 0.0, sampleRate: sampleRate)
        bandpass = BandpassFilter(lowCutoff: 5.0, highCutoff: 45.0, sampleRate: sampleRate)
        fftAnalyzer = FFTAnalyzer(fftLength: 128, sampleRate: sampleRate)
    }

    /// Process a raw accelerometer sample (~100Hz)
    func processSample(_ sample: AccelSample) {
        // 1. Gravity removal via Kalman filter
        let result = gravityFilter.process(x: sample.x, y: sample.y, z: sample.z)

        // 2. Orientation via Mahony AHRS (using raw accel, no gyro for now)
        ahrs.updateAccelOnly(ax: sample.x, ay: sample.y, az: sample.z)

        lock.lock()

        // Store dynamic component for bandpass/FFT
        dynamicSamples.append((dx: result.dx, dy: result.dy, dz: result.dz))

        // Compute dynamic magnitude for bandpass input
        let dynamicMag = sqrt(result.dx * result.dx + result.dy * result.dy + result.dz * result.dz)
        bandpassBuffer.append(dynamicMag)

        lock.unlock()
    }

    /// Compute 1-second aggregated snapshot values.
    /// Call this at 1Hz from a timer.
    func computeSnapshot() {
        lock.lock()
        let samples = dynamicSamples
        let bpInput = bandpassBuffer
        dynamicSamples.removeAll(keepingCapacity: true)
        bandpassBuffer.removeAll(keepingCapacity: true)
        lock.unlock()

        guard !samples.isEmpty else { return }

        // Orientation from AHRS
        pitch = ahrs.pitch
        roll = ahrs.roll

        // 3. Bandpass filter for typing detection
        if bpInput.count >= 10 {
            let filtered = bandpass.apply(bpInput)
            let rms = sqrt(filtered.map { $0 * $0 }.reduce(0, +) / Double(filtered.count))
            typingRMS = rms
        }

        // 4. Vibration variance (gravity vector stability for surface classification)
        let avgDx = samples.map(\.dx).reduce(0, +) / Double(samples.count)
        let avgDy = samples.map(\.dy).reduce(0, +) / Double(samples.count)
        let avgDz = samples.map(\.dz).reduce(0, +) / Double(samples.count)

        let xVar = samples.map { ($0.dx - avgDx) * ($0.dx - avgDx) }.reduce(0, +) / Double(samples.count)
        let yVar = samples.map { ($0.dy - avgDy) * ($0.dy - avgDy) }.reduce(0, +) / Double(samples.count)
        let zVar = samples.map { ($0.dz - avgDz) * ($0.dz - avgDz) }.reduce(0, +) / Double(samples.count)
        vibrationVariance = xVar + yVar + zVar

        // 5. FFT for frequency distribution (surface classification)
        if bpInput.count >= 128 {
            let fftResult = fftAnalyzer.analyze(bpInput)
            fftLow = fftResult.low
            fftMid = fftResult.mid
            fftHigh = fftResult.high
        }

        // 6. Activity detection — handled by CGEventSource in the app layer, not here
        // isActive is left for the app to override via system idle time
    }
}
