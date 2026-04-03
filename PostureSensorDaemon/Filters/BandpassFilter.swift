import Accelerate
import Foundation

/// Biquad bandpass filter using Apple's Accelerate/vDSP framework.
/// Filters accelerometer data to isolate keystroke vibrations (5-45Hz).
/// Implemented as cascaded high-pass + low-pass 2nd-order Butterworth sections.
final class BandpassFilter {
    // Two cascaded biquad sections: HP then LP
    private var coefficients: [Double]  // 10 coefficients (5 per section * 2 sections)
    private var delays: [Double]        // 8 delay elements (4 per section * 2 sections)

    init(lowCutoff: Double = 5.0, highCutoff: Double = 45.0, sampleRate: Double = 100.0) {
        let hp = BandpassFilter.designHighPass(cutoff: lowCutoff, sampleRate: sampleRate)
        let lp = BandpassFilter.designLowPass(cutoff: highCutoff, sampleRate: sampleRate)
        self.coefficients = hp + lp
        self.delays = [Double](repeating: 0, count: 4 + 4)  // 2 sections * (2 input + 2 output delays)
    }

    /// Apply the bandpass filter to a buffer of samples.
    func apply(_ input: [Double]) -> [Double] {
        var output = [Double](repeating: 0, count: input.count)
        var temp = input

        // Apply each biquad section sequentially using direct form II transposed
        for section in 0..<2 {
            let cOffset = section * 5
            let dOffset = section * 4
            let b0 = coefficients[cOffset]
            let b1 = coefficients[cOffset + 1]
            let b2 = coefficients[cOffset + 2]
            let a1 = coefficients[cOffset + 3]
            let a2 = coefficients[cOffset + 4]

            var d1 = delays[dOffset]
            var d2 = delays[dOffset + 1]

            for i in 0..<temp.count {
                let x = temp[i]
                let y = b0 * x + d1
                d1 = b1 * x - a1 * y + d2
                d2 = b2 * x - a2 * y
                output[i] = y
            }

            delays[dOffset] = d1
            delays[dOffset + 1] = d2
            temp = output
        }

        return output
    }

    // MARK: - Filter Design

    /// 2nd-order Butterworth high-pass: [b0, b1, b2, a1, a2] (a0 normalized to 1)
    private static func designHighPass(cutoff: Double, sampleRate: Double) -> [Double] {
        let w0 = 2.0 * Double.pi * cutoff / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * sqrt(2.0))

        let a0 = 1.0 + alpha
        return [
            (1.0 + cosW0) / 2.0 / a0,
            -(1.0 + cosW0) / a0,
            (1.0 + cosW0) / 2.0 / a0,
            -2.0 * cosW0 / a0,
            (1.0 - alpha) / a0,
        ]
    }

    /// 2nd-order Butterworth low-pass: [b0, b1, b2, a1, a2] (a0 normalized to 1)
    private static func designLowPass(cutoff: Double, sampleRate: Double) -> [Double] {
        let w0 = 2.0 * Double.pi * cutoff / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * sqrt(2.0))

        let a0 = 1.0 + alpha
        return [
            (1.0 - cosW0) / 2.0 / a0,
            (1.0 - cosW0) / a0,
            (1.0 - cosW0) / 2.0 / a0,
            -2.0 * cosW0 / a0,
            (1.0 - alpha) / a0,
        ]
    }
}
