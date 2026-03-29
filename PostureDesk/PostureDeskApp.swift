import AppKit
import SwiftData
import SwiftUI

@main
struct PostureDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: PostureViewModel
    let modelContainer: ModelContainer
    static let licenseManager = LicenseManager()

    init() {
        let container = try! ModelContainer(
            for: SessionRecord.self, CalibrationProfile.self, UserSettings.self
        )
        self.modelContainer = container
        self._viewModel = State(initialValue: PostureViewModel(modelContext: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra("PostureDesk", systemImage: viewModel.iconState.rawValue) {
            MenuBarPopover()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)

        Window("PostureDesk", id: "dashboard") {
            MainWindow()
                .environment(viewModel)
        }
        .defaultSize(width: 780, height: 520)
        .modelContainer(modelContainer)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        let hasLicense = PostureDeskApp.licenseManager.isLicensed

        if !onboardingComplete {
            showOnboarding(startAt: .welcome)
        } else if !hasLicense {
            // Onboarding done but license removed — re-show at activate step
            showOnboarding(startAt: .activate)
        }
    }

    func showOnboarding(startAt: OnboardingStep = .welcome) {
        NSApp.setActivationPolicy(.regular)

        let binding = Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: "onboardingComplete") },
            set: { [weak self] newValue in
                UserDefaults.standard.set(newValue, forKey: "onboardingComplete")
                if newValue {
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PostureDesk Setup"
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                isComplete: binding,
                licenseManager: PostureDeskApp.licenseManager,
                initialStep: startAt
            )
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        onboardingWindow = window
    }
}
