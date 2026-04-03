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
    private var overdueMinutes: Int { max(0, breakSeconds - target) / 60 }
    private var breakProgress: Double {
        guard target > 0 else { return 0 }
        return min(Double(breakSeconds) / Double(target), 1.0)
    }

    private var breakColor: Color {
        if isBreakTime { return DS.Colors.accentDanger }
        if breakProgress > 0.8 { return DS.Colors.accentWarn }
        return DS.Colors.accentGood
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row: label + break button
            HStack {
                Text("session")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.5)

                Spacer()

                Button {
                    viewModel.recordBreak()
                } label: {
                    Text("Took a Break")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
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

            // Main content: time + break progress
            HStack(alignment: .center, spacing: 24) {
                // Session duration
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

                // Break sprint progress
                VStack(alignment: .leading, spacing: 8) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            Capsule()
                                .fill(DS.Colors.textMuted.opacity(0.12))
                                .frame(height: 6)

                            // Fill
                            Capsule()
                                .fill(breakColor)
                                .frame(width: max(6, geo.size.width * breakProgress), height: 6)
                                .animation(.easeInOut(duration: 0.8), value: breakProgress)
                        }
                    }
                    .frame(height: 6)

                    // Break label
                    HStack {
                        Text(isBreakTime ? "break time — \(overdueMinutes)m overdue" : "next break in \(minutesLeft)m")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(breakColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: isBreakTime ? overdueMinutes : minutesLeft)

                        Spacer()

                        Text("\(Int(breakProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DS.Colors.textMuted)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Status dots
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

        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
    }
}
