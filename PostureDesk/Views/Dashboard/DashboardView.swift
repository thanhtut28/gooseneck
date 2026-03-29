import SwiftUI

struct DashboardView: View {
    @Environment(PostureViewModel.self) private var viewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                // Hero: posture figure + status
                heroSection

                // Row 1: Lid Angle + Tilt
                HStack(spacing: DS.Spacing.sectionGap) {
                    LidAngleCard()
                    TiltCard()
                }

                // Row 2: Session summary
                SessionSummaryCard()

                // Row 3: Typing — full width with coach mark
                TypingIntensityCard()
            }
            .padding(DS.Spacing.pageInset)
        }
        .background(DS.Colors.bg)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(spacing: 32) {
            PostureFigure(
                drift: viewModel.postureAnalyzer.currentDrift,
                isDrifting: viewModel.iconState == .drifting
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(heroTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text(heroSubtitle)
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)

                if viewModel.isPaused {
                    Text("paused")
                        .font(DS.Font.label())
                        .foregroundStyle(DS.Colors.accentWarn.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.Colors.accentWarn.opacity(0.1), in: Capsule())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                actionButton("Recalibrate", icon: "scope") {
                    viewModel.calibrate()
                }
                actionButton(viewModel.isPaused ? "Resume" : "Pause", icon: viewModel.isPaused ? "play" : "pause") {
                    viewModel.isPaused.toggle()
                    if viewModel.isPaused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3600) {
                            viewModel.isPaused = false
                        }
                    }
                }
            }
        }
        .dsCard()
    }

    private var heroTitle: String {
        switch viewModel.iconState {
        case .good: "posture looks good"
        case .drifting: "time to readjust"
        case .breakNeeded: "take a break"
        case .away: "welcome back"
        }
    }

    private var heroSubtitle: String {
        let s = viewModel.breakTracker.totalActiveSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        let dur = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(dur) active · \(viewModel.selectedSurface.label.lowercased())"
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(DS.Colors.textPrimary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DS.Colors.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
