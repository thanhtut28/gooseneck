import Foundation

/// Simple 1D Kalman filter for separating gravity from dynamic acceleration.
/// Applied independently to each axis.
struct KalmanFilter {
    private var estimate: Double
    private var errorEstimate: Double
    private let processNoise: Double  // Q - how much we expect the state to change
    private let measurementNoise: Double  // R - how noisy the sensor is

    init(initialEstimate: Double = 0, processNoise: Double = 0.001, measurementNoise: Double = 0.1) {
        self.estimate = initialEstimate
        self.errorEstimate = 1.0
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    /// Update with a new measurement, returns the filtered (gravity) estimate.
    mutating func update(_ measurement: Double) -> Double {
        // Reject non-finite measurements — they would poison the filter state forever.
        guard measurement.isFinite else { return estimate }

        // Clamp errorEstimate to a small positive epsilon to avoid degenerate gain.
        if !errorEstimate.isFinite || errorEstimate < 1e-9 {
            errorEstimate = 1e-9
        }

        // Prediction step
        let predictedErrorEstimate = errorEstimate + processNoise

        // Update step
        let kalmanGain = predictedErrorEstimate / (predictedErrorEstimate + measurementNoise)
        estimate = estimate + kalmanGain * (measurement - estimate)
        errorEstimate = (1 - kalmanGain) * predictedErrorEstimate

        if !estimate.isFinite { estimate = 0 }
        if !errorEstimate.isFinite || errorEstimate < 1e-9 { errorEstimate = 1e-9 }

        return estimate
    }
}

/// 3-axis Kalman filter for gravity removal.
/// Returns (gravity, dynamic) components of acceleration.
struct GravityFilter {
    private var xFilter: KalmanFilter
    private var yFilter: KalmanFilter
    private var zFilter: KalmanFilter

    init() {
        // Low process noise = slow-changing gravity estimate
        // High measurement noise = smooth out fast vibrations
        xFilter = KalmanFilter(processNoise: 0.0001, measurementNoise: 0.05)
        yFilter = KalmanFilter(processNoise: 0.0001, measurementNoise: 0.05)
        zFilter = KalmanFilter(initialEstimate: -1.0, processNoise: 0.0001, measurementNoise: 0.05)
    }

    /// Process a raw acceleration sample.
    /// Returns (gravityX, gravityY, gravityZ, dynamicX, dynamicY, dynamicZ)
    mutating func process(x: Double, y: Double, z: Double) -> (gx: Double, gy: Double, gz: Double, dx: Double, dy: Double, dz: Double) {
        let gx = xFilter.update(x)
        let gy = yFilter.update(y)
        let gz = zFilter.update(z)

        return (gx, gy, gz, x - gx, y - gy, z - gz)
    }
}
