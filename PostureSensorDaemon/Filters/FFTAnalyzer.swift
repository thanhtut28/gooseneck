import Accelerate
import Foundation

/// FFT-based frequency analysis using Apple's vDSP framework.
/// Extracts energy in frequency bins for surface classification.
final class FFTAnalyzer {
    private let fftSetup: vDSP.FFT<DSPDoubleSplitComplex>?
    private let fftLength: Int
    private let log2n: vDSP_Length
    private let sampleRate: Double

    /// Frequency bin boundaries in Hz
    private let lowBinMax: Double = 10.0
    private let midBinMax: Double = 50.0
    // High bin: 50+ Hz

    init(fftLength: Int = 128, sampleRate: Double = 100.0) {
        self.fftLength = fftLength
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(fftLength)))

        fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPDoubleSplitComplex.self)
    }

    /// Analyze frequency content of a signal.
    /// Returns (lowBinEnergy, midBinEnergy, highBinEnergy) as ratios of total energy.
    func analyze(_ signal: [Double]) -> (low: Double, mid: Double, high: Double) {
        guard signal.count >= fftLength, let fft = fftSetup else {
            return (0, 0, 0)
        }

        // Cap input to expected length, sanitize non-finite inputs.
        let tail = signal.suffix(fftLength).map { $0.isFinite ? $0 : 0 }
        let windowed = vDSP.multiply(
            tail,
            vDSP.window(ofType: Double.self, usingSequence: .hanningNormalized, count: fftLength, isHalfWindow: false)
        )

        // Perform real FFT
        var realPart = [Double](repeating: 0, count: fftLength / 2)
        var imagPart = [Double](repeating: 0, count: fftLength / 2)

        windowed.withUnsafeBufferPointer { inputPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let inputBase = inputPtr.baseAddress else { return }

                    var splitComplex = DSPDoubleSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )

                    inputBase.withMemoryRebound(to: DSPDoubleComplex.self, capacity: fftLength / 2) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftLength / 2))
                    }

                    fft.transform(input: splitComplex, output: &splitComplex, direction: .forward)
                }
            }
        }

        // Compute magnitude squared (power spectrum), replacing non-finite values with 0.
        let magnitudes = zip(realPart, imagPart).map { r, i -> Double in
            let m = r * r + i * i
            return m.isFinite ? m : 0
        }

        // Bin the frequencies
        let freqResolution = sampleRate / Double(fftLength)  // Hz per bin
        var lowEnergy = 0.0
        var midEnergy = 0.0
        var highEnergy = 0.0
        var totalEnergy = 0.0

        for (i, mag) in magnitudes.enumerated() {
            let freq = Double(i) * freqResolution
            totalEnergy += mag

            if freq <= lowBinMax {
                lowEnergy += mag
            } else if freq <= midBinMax {
                midEnergy += mag
            } else {
                highEnergy += mag
            }
        }

        if !totalEnergy.isFinite { totalEnergy = 0 }
        guard totalEnergy > 0 else { return (0, 0, 0) }

        return (
            low: lowEnergy / totalEnergy,
            mid: midEnergy / totalEnergy,
            high: highEnergy / totalEnergy
        )
    }
}
