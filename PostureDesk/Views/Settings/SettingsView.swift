import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(LicenseManager.self) private var licenseManager
    @Environment(PostureViewModel.self) private var viewModel

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDeactivateAlert: Bool = false

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                // Monitoring (posture + typing fatigue)
                settingsGroup("monitoring") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("Drift Sensitivity") {
                            Text(String(format: "%.0f°", vm.driftThreshold))
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        Slider(value: $vm.driftThreshold, in: 5...25, step: 1)
                            .tint(DS.Colors.accentInfo)
                            .accessibilityLabel("Drift Sensitivity")
                        settingHint("Lower = more sensitive to posture changes")
                    }

                    settingRow("Surface") {
                        Picker("", selection: $vm.selectedSurface) {
                            Text("Desk").tag(Surface.desk)
                            Text("Lap").tag(Surface.lap)
                            Text("Couch").tag(Surface.couch)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .labelsHidden()
                        .accessibilityLabel("Surface")
                    }

                    Divider()
                        .foregroundStyle(DS.Colors.cardBorder)

                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("Fatigue Threshold") {
                            Text(String(format: "+%.0f%%", viewModel.fatigueMonitor.fatigueThresholdPercent))
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        Slider(value: Binding(
                            get: { viewModel.fatigueMonitor.fatigueThresholdPercent },
                            set: { viewModel.fatigueMonitor.fatigueThresholdPercent = $0 }
                        ), in: 10...50, step: 5)
                            .tint(DS.Colors.accentInfo)
                            .accessibilityLabel("Fatigue Threshold")
                        settingHint("Higher = more tolerance before fatigue alert")
                    }
                }

                // Breaks
                settingsGroup("breaks") {
                    VStack(alignment: .leading, spacing: 8) {
                        settingRow("Break Interval") {
                            Picker("Break Interval", selection: Binding(
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
                            .accessibilityLabel("Break Interval")
                        }

                        if viewModel.breakTracker.breakIntervalMinutes == 5 {
                            Text("5-minute intervals will trigger frequent alerts")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Colors.accentWarn)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.breakTracker.breakIntervalMinutes)

                    settingRow("Reminder Cadence") {
                        Picker("Reminder cadence", selection: Binding(
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
                        .accessibilityLabel("Reminder cadence")
                    }
                }

                // Notifications with per-category toggles
                settingsGroup("notifications") {
                    settingRow("Notifications") {
                        Toggle("Notifications", isOn: $vm.notificationsEnabled)
                            .toggleStyle(.checkbox)
                            .tint(DS.Colors.accentGood)
                            .labelsHidden()
                            .accessibilityLabel("Enable notifications")
                    }

                    if vm.notificationsEnabled {
                        VStack(spacing: 12) {
                            settingRow("Posture alerts") {
                                Toggle("Posture alerts", isOn: $vm.postureNotificationsEnabled)
                                    .toggleStyle(.checkbox)
                                    .tint(DS.Colors.accentGood)
                                    .labelsHidden()
                            }

                            settingRow("Break reminders") {
                                Toggle("Break reminders", isOn: $vm.breakNotificationsEnabled)
                                    .toggleStyle(.checkbox)
                                    .tint(DS.Colors.accentGood)
                                    .labelsHidden()
                            }

                            settingRow("Typing fatigue") {
                                Toggle("Typing fatigue", isOn: $vm.fatigueNotificationsEnabled)
                                    .toggleStyle(.checkbox)
                                    .tint(DS.Colors.accentGood)
                                    .labelsHidden()
                            }
                        }
                        .padding(.leading, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: vm.notificationsEnabled)

                // Appearance
                settingsGroup("appearance") {
                    settingRow("Theme") {
                        Picker("", selection: $vm.themeMode) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .labelsHidden()
                        .accessibilityLabel("Theme")
                    }

                    settingRow("Launch at Login") {
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
                        .toggleStyle(.checkbox)
                        .tint(DS.Colors.accentGood)
                        .labelsHidden()
                        .accessibilityLabel("Launch at Login")
                    }

                    settingRow("Posture Island") {
                        Toggle("Posture Island", isOn: $vm.dynamicIslandEnabled)
                            .toggleStyle(.checkbox)
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: vm.dynamicIslandEnabled)

                // License & About
                settingsGroup("license & about") {
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

                    HStack {
                        Text("PostureDesk")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.textPrimary)
                        Spacer()
                        Text("v1.0.0")
                            .font(DS.Font.caption())
                            .foregroundStyle(DS.Colors.textMuted)
                    }

                    Text("real-time posture monitoring using your MacBook's built-in sensors")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
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
            Text("This will deactivate your license and require re-activation to continue using PostureDesk.")
        }
    }

    // MARK: - Helpers

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            VStack(spacing: 16) {
                content()
            }
            .dsCard()
        }
    }

    private func settingRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.body())
                .foregroundStyle(DS.Colors.textPrimary)
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
