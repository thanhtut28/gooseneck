import SwiftUI

struct SettingsView: View {
    @Environment(PostureViewModel.self) private var viewModel

    @State private var breakInterval: Int = 45
    @State private var driftSensitivity: Double = 10
    @State private var fatigueThreshold: Double = 30
    @State private var notificationsEnabled: Bool = true
    @State private var showDeactivateAlert: Bool = false

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                // Posture
                settingsGroup("posture") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("Drift Sensitivity") {
                            Text(String(format: "%.0f°", driftSensitivity))
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        Slider(value: $driftSensitivity, in: 5...25, step: 1)
                            .tint(DS.Colors.accentInfo)
                            .onChange(of: driftSensitivity) { _, newValue in
                                viewModel.postureAnalyzer.driftThreshold = newValue
                            }
                    }

                    settingRow("Surface") {
                        Picker("", selection: $vm.selectedSurface) {
                            Text("Desk").tag(Surface.desk)
                            Text("Lap").tag(Surface.lap)
                            Text("Couch").tag(Surface.couch)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                }

                // Breaks
                settingsGroup("breaks") {
                    settingRow("Break Interval") {
                        Picker("", selection: $breakInterval) {
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("60 min").tag(60)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .onChange(of: breakInterval) { _, newValue in
                            viewModel.breakTracker.breakIntervalMinutes = newValue
                        }
                    }
                }

                // Fatigue
                settingsGroup("typing fatigue") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("Fatigue Threshold") {
                            Text(String(format: "+%.0f%%", fatigueThreshold))
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        Slider(value: $fatigueThreshold, in: 10...50, step: 5)
                            .tint(DS.Colors.accentInfo)
                            .onChange(of: fatigueThreshold) { _, newValue in
                                viewModel.fatigueMonitor.fatigueThresholdPercent = newValue
                            }
                    }
                }

                // Notifications
                settingsGroup("notifications") {
                    settingRow("Enable notifications") {
                        Toggle("", isOn: $notificationsEnabled)
                            .toggleStyle(.checkbox)
                            .tint(DS.Colors.accentGood)
                    }
                }

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
                    }
                }

                // License
                settingsGroup("license") {
                    settingRow("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(PostureDeskApp.licenseManager.isLicensed ? DS.Colors.accentGood : DS.Colors.accentDanger)
                                .frame(width: 6, height: 6)
                            Text(PostureDeskApp.licenseManager.isLicensed ? "Active" : "Inactive")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }

                    if let masked = PostureDeskApp.licenseManager.maskedKey {
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
                }

                // About
                settingsGroup("about") {
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
        .alert("Deactivate License", isPresented: $showDeactivateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Deactivate", role: .destructive) {
                Task {
                    await PostureDeskApp.licenseManager.deactivate()
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.showOnboarding(startAt: .activate)
                    }
                }
            }
        } message: {
            Text("This will deactivate your license and require re-activation to continue using PostureDesk.")
        }
        .onAppear {
            breakInterval = viewModel.breakTracker.breakIntervalMinutes
            driftSensitivity = viewModel.postureAnalyzer.driftThreshold
            fatigueThreshold = viewModel.fatigueMonitor.fatigueThresholdPercent
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
}
