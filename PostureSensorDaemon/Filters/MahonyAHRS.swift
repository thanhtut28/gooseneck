import Foundation

/// Mahony AHRS (Attitude and Heading Reference System) filter.
/// Computes device orientation (pitch/roll) from accelerometer + gyroscope data.
/// When gyroscope is unavailable, uses accelerometer-only orientation with smoothing.
///
/// Reference: https://ahrs.readthedocs.io/en/latest/filters/mahony.html
final class MahonyAHRS {
    // Quaternion representing device orientation
    private var q0: Double = 1.0
    private var q1: Double = 0.0
    private var q2: Double = 0.0
    private var q3: Double = 0.0

    // Filter gains
    private let kp: Double  // Proportional gain
    private let ki: Double  // Integral gain

    // Integral error for gyro bias correction
    private var integralErrorX: Double = 0
    private var integralErrorY: Double = 0
    private var integralErrorZ: Double = 0

    /// Sample period in seconds
    private let samplePeriod: Double

    /// Counts how many times the quaternion had to be reset due to denormalization (observability).
    private var denormResetCount: Int = 0

    init(kp: Double = 0.5, ki: Double = 0.0, sampleRate: Double = 100.0) {
        self.kp = kp
        self.ki = ki
        self.samplePeriod = 1.0 / sampleRate
    }

    /// Update with accelerometer + gyroscope data.
    /// All values in SI units (m/s², rad/s).
    func update(ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double) {
        var ax = ax, ay = ay, az = az
        var gx = gx, gy = gy, gz = gz

        // Normalize accelerometer
        let norm = sqrt(ax * ax + ay * ay + az * az)
        guard norm > 0.01 else { return }
        ax /= norm; ay /= norm; az /= norm

        // Estimated gravity direction from quaternion
        let vx = 2.0 * (q1 * q3 - q0 * q2)
        let vy = 2.0 * (q0 * q1 + q2 * q3)
        let vz = q0 * q0 - q1 * q1 - q2 * q2 + q3 * q3

        // Error is cross product of estimated and measured gravity
        let ex = ay * vz - az * vy
        let ey = az * vx - ax * vz
        let ez = ax * vy - ay * vx

        // Apply integral feedback (gyro bias correction)
        if ki > 0 {
            integralErrorX += ki * ex * samplePeriod
            integralErrorY += ki * ey * samplePeriod
            integralErrorZ += ki * ez * samplePeriod
            gx += integralErrorX
            gy += integralErrorY
            gz += integralErrorZ
        }

        // Apply proportional feedback
        gx += kp * ex
        gy += kp * ey
        gz += kp * ez

        // Integrate rate of change of quaternion
        let halfDt = 0.5 * samplePeriod
        let dq0 = (-q1 * gx - q2 * gy - q3 * gz) * halfDt
        let dq1 = ( q0 * gx + q2 * gz - q3 * gy) * halfDt
        let dq2 = ( q0 * gy - q1 * gz + q3 * gx) * halfDt
        let dq3 = ( q0 * gz + q1 * gy - q2 * gx) * halfDt

        q0 += dq0; q1 += dq1; q2 += dq2; q3 += dq3

        // Normalize quaternion
        let qnorm = sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
        guard qnorm > 1e-10 else {
            q0 = 1.0; q1 = 0.0; q2 = 0.0; q3 = 0.0
            denormResetCount += 1
            #if DEBUG
            if denormResetCount == 1 || denormResetCount % 10 == 0 {
                print("[Mahony] quaternion denorm reset #\(denormResetCount)")
            }
            #endif
            return
        }
        q0 /= qnorm; q1 /= qnorm; q2 /= qnorm; q3 /= qnorm
    }

    /// Update with accelerometer only (no gyroscope).
    /// Uses a simplified complementary-like update.
    func updateAccelOnly(ax: Double, ay: Double, az: Double) {
        // When no gyro, treat as zero angular velocity
        update(ax: ax, ay: ay, az: az, gx: 0, gy: 0, gz: 0)
    }

    /// Current pitch in degrees (rotation around Y axis — forward/backward tilt)
    var pitch: Double {
        let sinp = 2.0 * (q0 * q2 - q3 * q1)
        let clamped = max(-1.0, min(1.0, sinp))
        return asin(clamped) * 180.0 / .pi
    }

    /// Current roll in degrees (rotation around X axis — left/right tilt)
    var roll: Double {
        let sinr = 2.0 * (q0 * q1 + q2 * q3)
        let cosr = 1.0 - 2.0 * (q1 * q1 + q2 * q2)
        return atan2(sinr, cosr) * 180.0 / .pi
    }
}
