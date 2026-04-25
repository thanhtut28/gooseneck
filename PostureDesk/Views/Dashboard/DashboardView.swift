import SwiftUI

struct DashboardView: View {
    @Environment(PostureViewModel.self) private var viewModel

    /// Read NotificationManager directly so SwiftUI observes its @Observable
    /// state (systemAuthorizationDenied flips reactively after requestPermission()
    /// resolves to a denial — without this, the banner would only update after
    /// some other viewModel property changed).
    private var systemNotificationsMuted: Bool {
        viewModel.notificationsEnabled && NotificationManager.shared.systemAuthorizationDenied
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                if case .failing = viewModel.storageHealth {
                    storageWarningBanner
                }

                if systemNotificationsMuted {
                    notificationWarningBanner
                }

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

    // MARK: - Storage Warning

    private var storageWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(DS.Colors.accentDanger)

            VStack(alignment: .leading, spacing: 2) {
                Text("History isn't saving")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.textPrimary)
                Text("GooseNeck couldn't save your recent session. Try restarting the app — recent data may be lost.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(DS.Colors.accentDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Spacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Spacing.cardRadius, style: .continuous)
                .strokeBorder(DS.Colors.accentDanger.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Notification Warning

    private var notificationWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.Colors.accentDanger)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off in System Settings")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.textPrimary)
                Text("GooseNeck can't alert you about posture, breaks, or fatigue. Turn off notifications in Settings \u{2192} Notifications to hide this banner.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer()

            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.accentDanger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.Colors.accentDanger.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(DS.Colors.accentDanger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Spacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Spacing.cardRadius, style: .continuous)
                .strokeBorder(DS.Colors.accentDanger.opacity(0.2), lineWidth: 1)
        )
    }
}
