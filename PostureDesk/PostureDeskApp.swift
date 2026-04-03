import AppKit
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

@main
struct GooseNeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: PostureViewModel
    let modelContainer: ModelContainer
    static let licenseManager = LicenseManager()
    static private(set) var sharedViewModel: PostureViewModel?
    static private(set) var persistentStoreLaunchIssue: String?

    init() {
        let bootstrap = Self.makeModelContainer()
        self.modelContainer = bootstrap.container
        Self.persistentStoreLaunchIssue = bootstrap.launchIssue
        let viewModel = PostureViewModel(modelContext: bootstrap.container.mainContext)
        self._viewModel = State(initialValue: viewModel)
        Self.sharedViewModel = viewModel
    }

    var body: some Scene {
        MenuBarExtra("GooseNeck", image: "MenuBarIcon") {
            MenuBarPopover()
                .environment(viewModel)
                .environment(Self.licenseManager)
        }
        .menuBarExtraStyle(.window)

        Window("GooseNeck", id: "dashboard") {
            MainWindow()
                .environment(viewModel)
                .environment(Self.licenseManager)
        }
        .defaultSize(width: 780, height: 520)
        .modelContainer(modelContainer)
        .commands {
            GooseNeckCommands(viewModel: viewModel)
        }
    }

    private struct ModelContainerBootstrap {
        let container: ModelContainer
        let launchIssue: String?
    }

    private static func makeModelContainer() -> ModelContainerBootstrap {
        let storeURL = persistentStoreURL()
        let configuration = ModelConfiguration(
            "GooseNeck",
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            return ModelContainerBootstrap(
                container: try ModelContainer(for: SessionRecord.self, configurations: configuration),
                launchIssue: nil
            )
        } catch {
            logPersistentStoreError("initial open", error: error)

            if shouldAttemptStoreReset(at: storeURL) {
                resetPersistentStore(at: storeURL)

                do {
                    return ModelContainerBootstrap(
                        container: try ModelContainer(for: SessionRecord.self, configurations: configuration),
                        launchIssue: "GooseNeck had to reset its local history store because it could not be opened."
                    )
                } catch {
                    logPersistentStoreError("reopen after reset", error: error)
                }
            }

            return ModelContainerBootstrap(
                container: makeInMemoryModelContainer(),
                launchIssue: "GooseNeck could not open its local history store. This session is using temporary in-memory storage, so history changes will not persist."
            )
        }
    }

    private static func persistentStoreURL(fileManager: FileManager = .default) -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("[Storage] Application Support directory unavailable")
        }
        let directoryURL = baseURL.appendingPathComponent("GooseNeck", isDirectory: true)

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return directoryURL.appendingPathComponent("posture-desk.store")
    }

    private static func resetPersistentStore(at storeURL: URL, fileManager: FileManager = .default) {
        for url in persistentStoreArtifacts(for: storeURL) where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func persistentStoreArtifacts(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
    }

    private static func shouldAttemptStoreReset(at storeURL: URL, fileManager: FileManager = .default) -> Bool {
        persistentStoreArtifacts(for: storeURL).contains { fileManager.fileExists(atPath: $0.path) }
    }

    private static func makeInMemoryModelContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: SessionRecord.self, configurations: configuration)
        } catch {
            fatalError("[Storage] Cannot create even an in-memory store: \(error)")
        }
    }

    private static func logPersistentStoreError(_ stage: String, error: Error) {
        #if DEBUG
        print("[Storage] \(stage) failed: \(error)")
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let onboardingSetupCompleteDefaultsKey = "onboardingSetupComplete"
    private var onboardingWindow: NSWindow?
    private var licenseRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        if let launchIssue = GooseNeckApp.persistentStoreLaunchIssue {
            presentLaunchIssueAlert(message: launchIssue)
        }

        let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        let onboardingSetupComplete = UserDefaults.standard.bool(forKey: Self.onboardingSetupCompleteDefaultsKey)
        let hasStoredLicense = GooseNeckApp.licenseManager.isLicensed

        if onboardingComplete {
            UserDefaults.standard.set(true, forKey: Self.onboardingSetupCompleteDefaultsKey)
        }

        if !onboardingComplete, !onboardingSetupComplete {
            GooseNeckApp.sharedViewModel?.unlockMonitoring()
            showOnboarding(startAt: .welcome)
        } else if !hasStoredLicense {
            // Onboarding done but license removed — re-show at activate step
            GooseNeckApp.sharedViewModel?.stop(lockMonitoring: true, finalizeSession: false)
            showOnboarding(startAt: .activate)
        }

        licenseRefreshTask = Task { [weak self] in
            guard onboardingComplete, hasStoredLicense else { return }

            await GooseNeckApp.licenseManager.refreshStatus()
            await MainActor.run {
                switch GooseNeckApp.licenseManager.licenseState {
                case .active, .gracePeriod:
                    GooseNeckApp.sharedViewModel?.unlockMonitoring()
                    GooseNeckApp.sharedViewModel?.start()
                case .unlicensed, .invalid:
                    GooseNeckApp.sharedViewModel?.stop(lockMonitoring: true, finalizeSession: false)
                    self?.showOnboarding(startAt: .activate)
                default:
                    GooseNeckApp.sharedViewModel?.stop(lockMonitoring: true, finalizeSession: false)
                    break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        licenseRefreshTask?.cancel()
        GooseNeckApp.sharedViewModel?.stop(finalizeSession: true)
    }

    func showOnboarding(startAt: OnboardingStep = .welcome) {
        guard let viewModel = GooseNeckApp.sharedViewModel else { return }

        if startAt == .welcome {
            viewModel.unlockMonitoring()
        }

        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.close()
        onboardingWindow = nil

        let binding = Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: "onboardingComplete") },
            set: { [weak self] newValue in
                UserDefaults.standard.set(newValue, forKey: "onboardingComplete")
                if newValue {
                    UserDefaults.standard.set(true, forKey: Self.onboardingSetupCompleteDefaultsKey)
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GooseNeck Setup"
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                isComplete: binding,
                initialStep: startAt
            )
            .environment(viewModel)
            .environment(GooseNeckApp.licenseManager)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func presentLaunchIssueAlert(message: String) {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "History Storage Unavailable"
        alert.informativeText = message
        alert.runModal()

        if previousPolicy == .accessory,
           onboardingWindow == nil,
           UserDefaults.standard.bool(forKey: "onboardingComplete") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let viewModel = GooseNeckApp.sharedViewModel else { return }

        switch response.actionIdentifier {
        case NotificationAction.recalibrate.rawValue:
            viewModel.calibrate()
        case NotificationAction.snooze.rawValue:
            viewModel.pauseMonitoring(for: 15 * 60)
        case NotificationAction.done.rawValue:
            viewModel.recordBreak()
        case NotificationAction.dismiss.rawValue,
             NotificationAction.gotIt.rawValue,
             UNNotificationDefaultActionIdentifier,
             UNNotificationDismissActionIdentifier:
            break
        default:
            break
        }
    }
}
