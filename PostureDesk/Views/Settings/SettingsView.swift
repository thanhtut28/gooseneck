import ServiceManagement
import Sparkle
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LicenseManager.self) private var licenseManager
    @Environment(PostureViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDeactivateAlert: Bool = false
    @ObservedObject private var checkForUpdatesVM = CheckForUpdatesViewModel(
        updater: GooseNeckApp.sharedUpdater
    )
    @State private var automaticallyChecksForUpdates = GooseNeckApp.sharedUpdater?.automaticallyChecksForUpdates ?? true
    @State private var automaticallyDownloadsUpdates = GooseNeckApp.sharedUpdater?.automaticallyDownloadsUpdates ?? false

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // --- MONITORING ---
                sectionHeader("Monitoring", isFirst: true)
                monitoringSection

                sectionDivider

                // --- BREAKS ---
                sectionHeader("Breaks")
                breaksSection

                sectionDivider

                // --- NOTIFICATIONS ---
                sectionHeader("Notifications")
                notificationsSection

                sectionDivider

                // --- APPEARANCE ---
                sectionHeader("Appearance")
                appearanceSection

                sectionDivider

                // --- UPDATES ---
                sectionHeader("Updates")
                updatesSection

                sectionDivider

                // --- LICENSE & ABOUT ---
                sectionHeader("License & About")
                licenseSection

            }
            .dsCard()
            .padding(DS.Spacing.pageInset)
        }
        .background(DS.Colors.bg)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Deactivate License", isPresented: $showDeactivateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Deactivate", role: .destructive) {
                Task {
                    await licenseManager.deactivate()
                    await MainActor.run {
                        viewModel.stop(lockMonitoring: true)
                        UserDefaults.standard.set(false, forKey: "onboardingComplete")
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.showOnboarding(startAt: .activate)
                        }
                    }
                }
            }
        } message: {
            Text("This will deactivate your license and require re-activation to continue using GooseNeck.")
        }
    }

    // MARK: - Monitoring

    @ViewBuilder
    private var monitoringSection: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("Posture Sensitivity") {
                    Text(String(format: "%.0f\u{00B0}", vm.driftThreshold))
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                Slider(value: $vm.driftThreshold, in: 5...25, step: 1)
                    .tint(DS.Colors.accentInfo)
                    .accessibilityLabel("Posture Sensitivity")
                settingHint("Lower values detect smaller posture shifts")
            }

            VStack(alignment: .leading, spacing: 12) {
                settingRow("Typing Fatigue Tolerance") {
                    Text(String(format: "+%.0f%%", viewModel.fatigueMonitor.fatigueThresholdPercent))
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                Slider(value: Binding(
                    get: { viewModel.fatigueMonitor.fatigueThresholdPercent },
                    set: { viewModel.fatigueMonitor.fatigueThresholdPercent = $0 }
                ), in: 10...50, step: 5)
                    .tint(DS.Colors.accentInfo)
                    .accessibilityLabel("Typing Fatigue Tolerance")
                settingHint("Higher values allow more intensity before alerting")
            }

        }
    }

    // MARK: - Breaks

    @ViewBuilder
    private var breaksSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                settingRow("Break Reminder", description: "Time before suggesting a break") {
                    Picker("Break Reminder", selection: Binding(
                        get: { viewModel.breakTracker.breakIntervalMinutes },
                        set: { viewModel.breakTracker.breakIntervalMinutes = $0 }
                    )) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .labelsHidden()
                    .accessibilityLabel("Break Reminder")
                }

                if viewModel.breakTracker.breakIntervalMinutes == 5 {
                    Text("5-minute intervals will trigger frequent alerts")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.accentWarn)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.breakTracker.breakIntervalMinutes)

            settingRow("Repeat Reminder", description: "How often to re-remind once a break is due") {
                Picker("Repeat Reminder", selection: Binding(
                    get: { viewModel.breakTracker.breakReminderCadence },
                    set: { viewModel.breakTracker.breakReminderCadence = $0 }
                )) {
                    ForEach(BreakReminderCadence.allCases, id: \.self) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .labelsHidden()
                .accessibilityLabel("Repeat Reminder")
            }
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        @Bindable var vm = viewModel
        let systemDenied = NotificationManager.shared.systemAuthorizationDenied
        VStack(spacing: 16) {
            settingRow("Notifications", description: "Send alerts for posture, breaks, and fatigue") {
                Toggle("Notifications", isOn: $vm.notificationsEnabled)
                    .toggleStyle(.switch)
                    .tint(DS.Colors.accentGood)
                    .labelsHidden()
                    .accessibilityLabel("Enable notifications")
            }

            if vm.notificationsEnabled && systemDenied {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.accentWarn)
                    Text("Blocked by macOS — enable in")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textMuted)
                    Button("System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(DS.Font.caption())
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Colors.accentWarn)
                    Spacer()
                }
            }

            if vm.notificationsEnabled && !systemDenied {
                settingRow("Posture Alerts", description: "Drift detection warnings") {
                    Toggle("Posture Alerts", isOn: $vm.postureNotificationsEnabled)
                        .toggleStyle(.switch)
                        .tint(DS.Colors.accentGood)
                        .labelsHidden()
                        .accessibilityLabel("Posture Alerts")
                        .accessibilityHint("Drift detection warnings")
                }

                settingRow("Break Reminders", description: "Stand-up suggestions") {
                    Toggle("Break Reminders", isOn: $vm.breakNotificationsEnabled)
                        .toggleStyle(.switch)
                        .tint(DS.Colors.accentGood)
                        .labelsHidden()
                        .accessibilityLabel("Break Reminders")
                        .accessibilityHint("Stand-up suggestions")
                }

                settingRow("Typing Fatigue", description: "Intensity spike alerts") {
                    Toggle("Typing Fatigue", isOn: $vm.fatigueNotificationsEnabled)
                        .toggleStyle(.switch)
                        .tint(DS.Colors.accentGood)
                        .labelsHidden()
                        .accessibilityLabel("Typing Fatigue")
                        .accessibilityHint("Intensity spike alerts")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.notificationsEnabled)
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 16) {
            settingRow("Theme", description: "Color scheme preference") {
                Picker("", selection: $vm.themeMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .labelsHidden()
                .accessibilityLabel("Theme")
            }

            settingRow("Launch at Login", description: "Start GooseNeck when you log in") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                        } catch {
                            // Registration failed — toggle stays at current state
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(DS.Colors.accentGood)
                .labelsHidden()
                .accessibilityLabel("Launch at Login")
            }

            settingRow("Posture Island", description: "Floating overlay on your desktop") {
                Toggle("Posture Island", isOn: $vm.dynamicIslandEnabled)
                    .toggleStyle(.switch)
                    .tint(DS.Colors.accentGood)
                    .labelsHidden()
                    .accessibilityLabel("Posture Island")
            }

            if vm.dynamicIslandEnabled {
                Divider()
                    .foregroundStyle(DS.Colors.cardBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Island Style")
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Colors.textPrimary)

                    IslandVariantPicker(selection: $vm.islandVariant)
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: vm.dynamicIslandEnabled)
    }

    // MARK: - Updates

    @ViewBuilder
    private var updatesSection: some View {
        VStack(spacing: 16) {
            settingRow("Check Automatically", description: "Periodically check for new versions") {
                Toggle("Check Automatically", isOn: $automaticallyChecksForUpdates)
                    .toggleStyle(.switch)
                    .tint(DS.Colors.accentGood)
                    .labelsHidden()
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        GooseNeckApp.sharedUpdater?.automaticallyChecksForUpdates = newValue
                    }
                    .accessibilityLabel("Automatically check for updates")
            }

            settingRow("Download Automatically", description: "Download updates in the background") {
                Toggle("Download Automatically", isOn: $automaticallyDownloadsUpdates)
                    .toggleStyle(.switch)
                    .tint(DS.Colors.accentGood)
                    .labelsHidden()
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                        GooseNeckApp.sharedUpdater?.automaticallyDownloadsUpdates = newValue
                    }
                    .accessibilityLabel("Automatically download updates")
            }

            HStack {
                Spacer()
                Button("Check for Updates\u{2026}") {
                    GooseNeckApp.sharedUpdater?.checkForUpdates()
                }
                .disabled(!checkForUpdatesVM.canCheckForUpdates)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.accentInfo)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - License & About

    @ViewBuilder
    private var licenseSection: some View {
        VStack(spacing: 16) {
            settingRow("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(licenseStatusColor)
                        .frame(width: 6, height: 6)
                    Text(licenseManager.stateLabel)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("License status \(licenseManager.stateLabel)")
            }

            if let detail = licenseManager.stateDetail {
                Text(detail)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
            }

            if let masked = licenseManager.maskedKey {
                settingRow("Key") {
                    Text(masked)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }

            HStack {
                Spacer()
                Button("Deactivate License") {
                    showDeactivateAlert = true
                }
                .foregroundStyle(DS.Colors.accentDanger)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
            }

            Divider()
                .foregroundStyle(DS.Colors.cardBorder)

            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("GooseNeck")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)

                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textSecondary)

                    Text("© 2026 GooseNeck")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
    }


    // MARK: - Helpers

    private func sectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        Text(title)
            .font(DS.Font.label())
            .foregroundStyle(DS.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(1.5)
            .padding(.top, isFirst ? 0 : 8)
            .padding(.bottom, 12)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(DS.Colors.textMuted.opacity(0.3))
            .padding(.vertical, 16)
    }

    private func settingRow<Trailing: View>(
        _ label: String,
        description: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textPrimary)
                if let description {
                    Text(description)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
            Spacer()
            trailing()
        }
    }

    private func settingHint(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.caption())
            .foregroundStyle(DS.Colors.textMuted)
    }

    private var licenseStatusColor: Color {
        switch licenseManager.licenseState {
        case .active:
            return DS.Colors.accentGood
        case .gracePeriod:
            return DS.Colors.accentWarn
        case .validating:
            return DS.Colors.accentInfo
        default:
            return DS.Colors.accentDanger
        }
    }
}
