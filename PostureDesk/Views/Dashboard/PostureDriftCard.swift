import SwiftUI

/// A progress bar that grows outward from center. Positive = right, negative = left.
struct CenterProgressBar: View {
    let value: Double  // -1.0 to 1.0
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let half = w / 2
            let barLen = half * min(abs(value), 1.0)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DS.Colors.bg)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: max(barLen, 0), height: 3)
                    .offset(x: value >= 0 ? half : half - barLen)
                    .animation(.easeInOut(duration: 0.5), value: value)
            }
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(DS.Colors.textMuted.opacity(0.4))
                    .frame(width: 1, height: 7)
            }
        }
        .frame(height: 7)
        .clipped()
    }
}

/// Lid angle drift card
struct LidAngleCard: View {
    @Environment(PostureViewModel.self) private var viewModel

    private var drift: Double { viewModel.postureAnalyzer.lidAngleDrift }
    private var magnitude: Double { abs(drift) }
    private var threshold: Double { viewModel.postureAnalyzer.driftThreshold }
    private var progress: Double { min(magnitude / threshold, 1.0) }

    private var accentColor: Color {
        if progress > 0.8 { return DS.Colors.accentWarn }
        if progress > 0.5 { return DS.Colors.accentWarn.opacity(0.7) }
        return DS.Colors.accentGood
    }

    private var formattedDrift: String {
        let sign = drift >= 0 ? "+" : ""
        return String(format: "%@%.1f", sign, drift)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("lid angle")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            Spacer()

            HStack(alignment: .top, spacing: 2) {
                Text(formattedDrift)
                    .font(DS.Font.metric(40))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: drift)

                Text("°")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
                    .padding(.top, 6)
            }

            CenterProgressBar(
                value: drift >= 0 ? progress : -progress,
                color: accentColor
            )

            Text(magnitude < 1 ? "centered" : drift > 0 ? "lid opening" : "lid closing")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .dsCard()
    }
}

/// Device tilt (pitch) card
struct TiltCard: View {
    @Environment(PostureViewModel.self) private var viewModel

    private var drift: Double { viewModel.postureAnalyzer.pitchDrift }
    private var magnitude: Double { abs(drift) }
    private var threshold: Double { viewModel.postureAnalyzer.driftThreshold }
    private var progress: Double { min(magnitude / threshold, 1.0) }

    private var accentColor: Color {
        if progress > 0.8 { return DS.Colors.accentWarn }
        if progress > 0.5 { return DS.Colors.accentWarn.opacity(0.7) }
        return DS.Colors.accentGood
    }

    private var formattedDrift: String {
        let sign = drift >= 0 ? "+" : ""
        return String(format: "%@%.1f", sign, drift)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("tilt")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            Spacer()

            HStack(alignment: .top, spacing: 2) {
                Text(formattedDrift)
                    .font(DS.Font.metric(40))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: drift)

                Text("°")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
                    .padding(.top, 6)
            }

            CenterProgressBar(
                value: drift >= 0 ? progress : -progress,
                color: accentColor
            )

            Text(magnitude < 1 ? "level" : drift > 0 ? "leaning forward" : "leaning back")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .dsCard()
    }
}
