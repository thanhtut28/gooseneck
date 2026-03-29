import Accelerate
import Foundation

/// FFT-based frequency analysis using Apple's vDSP framework.
/// Extracts energy in frequency bins for surface classification.
final class FFTAnalyzer {
    private let fftSetup: vDSP.FFT<DSPDoubleSplitComplex>
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

        fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPDoubleSplitComplex.self)!
    }

    /// Analyze frequency content of a signal.
    /// Returns (lowBinEnergy, midBinEnergy, highBinEnergy) as ratios of total energy.
    func analyze(_ signal: [Double]) -> (low: Double, mid: Double, high: Double) {
        guard signal.count >= fftLength else {
            return (0, 0, 0)
        }

        // Take the last fftLength samples and apply Hann window
        let windowed = vDSP.multiply(
            Array(signal.suffix(fftLength)),
            vDSP.window(ofType: Double.self, usingSequence: .hanningNormalized, count: fftLength, isHalfWindow: false)
        )

        // Perform real FFT
        var realPart = [Double](repeating: 0, count: fftLength / 2)
        var imagPart = [Double](repeating: 0, count: fftLength / 2)

        windowed.withUnsafeBufferPointer { inputPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPDoubleSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )

                    inputPtr.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: fftLength / 2) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftLength / 2))
                    }

                    fftSetup.transform(input: splitComplex, output: &splitComplex, direction: .forward)
                }
            }
        }

        // Compute magnitude squared (power spectrum)
        let magnitudes = zip(realPart, imagPart).map { r, i in r * r + i * i }

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

        guard totalEnergy > 0 else { return (0, 0, 0) }

        return (
            low: lowEnergy / totalEnergy,
            mid: midEnergy / totalEnergy,
            high: highEnergy / totalEnergy
        )
    }
}
