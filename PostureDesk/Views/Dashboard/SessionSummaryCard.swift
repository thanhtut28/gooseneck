import SwiftUI

struct SessionSummaryCard: View {
    @Environment(PostureViewModel.self) private var viewModel

    // Session
    private var seconds: Int { viewModel.breakTracker.totalActiveSeconds }
    private var hours: Int { seconds / 3600 }
    private var minutes: Int { (seconds % 3600) / 60 }

    // Break
    private var target: Int { viewModel.breakTracker.breakIntervalMinutes * 60 }
    private var breakSeconds: Int { viewModel.breakTracker.secondsSinceLastBreak }
    private var remaining: Int { max(0, target - breakSeconds) }
    private var minutesLeft: Int { remaining / 60 }
    private var isBreakTime: Bool { remaining <= 0 }

    private var breakChipColor: Color {
        if isBreakTime { return DS.Colors.accentDanger }
        if Double(breakSeconds) / Double(target) > 0.8 { return DS.Colors.accentWarn }
        return DS.Colors.accentInfo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row: label + skip button
            HStack {
                Text("session")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.5)

                Spacer()

                Button {
                    viewModel.breakTracker.recordBreak()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "forward.end")
                            .font(.system(size: 10, weight: .medium))
                        Text("Skip Break")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(DS.Colors.textPrimary.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.Colors.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.Colors.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Hero: session duration
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if hours > 0 {
                    Text("\(hours)")
                        .font(DS.Font.hero())
                        .foregroundStyle(DS.Colors.textPrimary)
                        .contentTransition(.numericText())
                    Text("h")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                Text("\(minutes)")
                    .font(DS.Font.hero())
                    .foregroundStyle(DS.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text("m")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
            }

            // Bottom row: status dots + break chip
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    statusDot(
                        viewModel.breakTracker.state == .active ? DS.Colors.accentGood : DS.Colors.textMuted,
                        label: viewModel.breakTracker.state == .active ? "active" : "away"
                    )
                    statusDot(
                        surfaceColor,
                        label: viewModel.selectedSurface.label.lowercased()
                    )
                }

                Spacer()

                Text(isBreakTime ? "break time" : "break in \(minutesLeft)m")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(breakChipColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(breakChipColor.opacity(0.12), in: Capsule())
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: minutesLeft)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .dsCard()
    }

    private var surfaceColor: Color {
        switch viewModel.selectedSurface {
        case .desk: DS.Colors.accentInfo
        case .lap: DS.Colors.accentInfo
        case .couch: DS.Colors.accentWarn
        case .unknown: DS.Colors.textMuted
        }
    }

    private func statusDot(_ color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }
}
