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
                pitchDrift: viewModel.postureAnalyzer.pitchDrift,
                lidAngleDrift: viewModel.postureAnalyzer.lidAngleDrift,
                isDrifting: viewModel.iconState == .drifting
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(heroTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text(heroSubtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary.opacity(0.55))

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
                actionButton(
                    sensorError == nil ? "Recalibrate" : "Retry Sensors",
                    icon: sensorError == nil ? "scope" : "arrow.clockwise",
                    hint: sensorError == nil
                        ? "Sets the current posture as your new baseline."
                        : "Attempts to reconnect the built-in sensors."
                ) {
                    if sensorError == nil {
                        viewModel.calibrate()
                    } else {
                        viewModel.start()
                    }
                }
                actionButton(
                    viewModel.isPaused ? "Resume" : "Pause",
                    icon: viewModel.isPaused ? "play" : "pause",
                    hint: viewModel.isPaused
                        ? "Resumes posture monitoring."
                        : "Pauses posture monitoring until you resume it."
                ) {
                    if viewModel.isPaused {
                        viewModel.resumeMonitoring()
                    } else {
                        viewModel.pauseMonitoring()
                    }
                }
            }
        }
        .dsCard()
    }

    private var heroTitle: String {
        if sensorError != nil {
            return "sensor unavailable"
        }

        switch viewModel.iconState {
        case .good:
            return "posture looks good"
        case .drifting:
            return driftGuidance
        case .breakNeeded:
            return "take a break"
        case .unavailable:
            return "sensor unavailable"
        case .away:
            return "welcome back"
        }
    }

    private var driftGuidance: String {
        let pitch = viewModel.postureAnalyzer.pitchDrift
        let lid = viewModel.postureAnalyzer.lidAngleDrift
        let absPitch = abs(pitch)
        let absLid = abs(lid)

        // Show the dominant drift direction
        if absPitch > absLid && absPitch > 2 {
            return pitch > 0 ? "straighten up — leaning forward" : "straighten up — leaning back"
        } else if absLid > 2 {
            return lid > 0 ? "adjust screen — lid opening" : "adjust screen — lid closing"
        }
        return "time to readjust"
    }

    private var heroSubtitle: String {
        if let sensorError {
            return sensorError
        }

        let duration = DisplayFormatter.activeDuration(seconds: viewModel.breakTracker.totalActiveSeconds)
        return "\(duration) active · \(viewModel.selectedSurface.label.lowercased())"
    }

    private func actionButton(_ title: String, icon: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(DS.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .dsGlassButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private var sensorError: String? {
        viewModel.sensorClient.connectionError
    }
}
