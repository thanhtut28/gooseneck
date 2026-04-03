import SwiftUI

/// Compact inline visual for the typing detection test in onboarding.
/// Shows a prompt to type with live RMS-driven bars that react to keystroke vibration.
struct TypingTestVisual: View {
    let typingRMS: Double
    let isDetected: Bool

    private let barCount = 8
    private let detectionThreshold: Double = 0.0001

    /// Normalize RMS to a 0–1 range for bar display.
    /// Typical typing RMS ranges from 0.0001 to ~0.01.
    private var normalizedLevel: Double {
        guard typingRMS > detectionThreshold else { return 0 }
        let clamped = min(typingRMS, 0.008)
        return (clamped - detectionThreshold) / (0.008 - detectionThreshold)
    }

    var body: some View {
        VStack(spacing: 14) {
            // RMS bar meter
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    let threshold = Double(i) / Double(barCount)
                    let filled = isDetected || normalizedLevel > threshold
                    RoundedRectangle(cornerRadius: 2)
                        .fill(filled ? barColor(for: i) : DS.Colors.textMuted.opacity(0.12))
                        .frame(height: 24)
                        .animation(
                            .easeOut(duration: 0.15).delay(Double(i) * 0.02),
                            value: normalizedLevel
                        )
                }
            }

            // Prompt or result
            if isDetected {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.accentGood)
                    Text("Typing detected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.accentGood)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text("Type a few words on your keyboard...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(DS.Colors.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func barColor(for index: Int) -> Color {
        if isDetected { return DS.Colors.accentGood }
        let fraction = Double(index) / Double(barCount)
        if fraction < 0.5 { return DS.Colors.accentInfo }
        return DS.Colors.accentGood
    }
}
