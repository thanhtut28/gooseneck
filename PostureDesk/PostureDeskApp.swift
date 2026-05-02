import AppKit
import Foundation
import Sparkle
import SwiftData
import SwiftUI
import UserNotifications

@main
struct GooseNeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: PostureViewModel
    let modelContainer: ModelContainer
    let updaterController: SPUStandardUpdaterController
    static let licenseManager = LicenseManager()
    static private(set) var sharedViewModel: PostureViewModel?
    static private(set) var sharedUpdater: SPUUpdater?
    static private(set) var persistentStoreLaunchIssue: String?

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Self.sharedUpdater = updaterController.updater

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
            // Fallback to temp directory — data won't survive reboot but app won't crash
            return fileManager.temporaryDirectory.appendingPathComponent("posture-desk.store")
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
        do {
            return try ModelContainer(
                for: SessionRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            // Catastrophic: even in-memory store failed. Surface a user-facing alert, then quit.
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "GooseNeck cannot start"
            alert.informativeText = "History storage could not be initialized. Try reinstalling GooseNeck or contact support."
            alert.addButton(withTitle: "Quit")
            _ = alert.runModal()
            NSApp.terminate(nil)
            fatalError("Catastrophic storage failure: \(error)")
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
    /// Static back-reference. `NSApp.delegate as? AppDelegate` is unreliable
    /// from some SwiftUI contexts (the delegate wrapper @NSApplicationDelegateAdaptor
    /// installs sometimes hides the underlying instance) — particularly when
    /// called directly from a SwiftUI Button action outside an alert. Always
    /// reach for `AppDelegate.shared` instead from view code.
    static private(set) weak var shared: AppDelegate?

    private static let onboardingSetupCompleteDefaultsKey = "onboardingSetupComplete"
    private var onboardingWindow: NSWindow?
    private var licenseRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
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

        // Track whether onboarding is taking over the launch — if so we must
        // not race a background license refresh against the user's flow.
        var willShowOnboarding = false

        if !onboardingComplete, !onboardingSetupComplete {
            GooseNeckApp.sharedViewModel?.stop(lockMonitoring: true, finalizeSession: false)
            showOnboarding(startAt: .welcome)
            willShowOnboarding = true
        } else if !hasStoredLicense {
            // Onboarding done but license removed — re-show at activate step
            GooseNeckApp.sharedViewModel?.stop(lockMonitoring: true, finalizeSession: false)
            showOnboarding(startAt: .activate)
            willShowOnboarding = true
        }

        // Skip the background refresh entirely while onboarding is owning
        // the launch. The onboarding flow drives its own activation/refresh
        // and we don't want this task interleaving with it.
        guard !willShowOnboarding, onboardingComplete, hasStoredLicense else { return }

        licenseRefreshTask = Task { [weak self] in
            // Run the network call off the main actor, then collapse the
            // entire decision path into a single MainActor.run hop so it
            // can't interleave with an in-flight start() from another path.
            // PostureViewModel.start() / stop() are already idempotent under
            // the @ObservationIgnored `monitoringLocked` + `isStarted`
            // guards, so re-issuing them on this hop is safe.
            await GooseNeckApp.licenseManager.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                let viewModel = GooseNeckApp.sharedViewModel
                switch GooseNeckApp.licenseManager.licenseState {
                case .active, .gracePeriod:
                    viewModel?.unlockMonitoring()
                    viewModel?.start()
                case .unlicensed, .invalid:
                    viewModel?.stop(lockMonitoring: true, finalizeSession: false)
                    self.showOnboarding(startAt: .activate)
                default:
                    viewModel?.stop(lockMonitoring: true, finalizeSession: false)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        licenseRefreshTask?.cancel()
        GooseNeckApp.sharedViewModel?.stop(finalizeSession: true)
    }

    /// Fires when the user clicks the Dock icon. If no windows are visible,
    /// open the dashboard so the user has a reliable path back into the app
    /// after completing onboarding (when Sparkle / SwiftUI haven't yet
    /// auto-opened any window for them).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Look for the dashboard NSWindow SwiftUI registered for the
            // Window scene with id "dashboard". If found, just bring it
            // forward. Otherwise let SwiftUI's default reopen behavior fire.
            if let dashboard = NSApp.windows.first(where: { window in
                window.identifier?.rawValue == "dashboard"
                    || window.title == "GooseNeck"
            }) {
                dashboard.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }

    func showOnboarding(startAt: OnboardingStep = .welcome) {
        guard let viewModel = GooseNeckApp.sharedViewModel else { return }

        if startAt == .welcome {
            viewModel.unlockMonitoring()
        }

        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.close()
        onboardingWindow = nil

        let setupCompleteKey = Self.onboardingSetupCompleteDefaultsKey
        let onComplete: () -> Void = { [weak self] in
            // Defer to the next runloop tick so SwiftUI finishes its current
            // view-tree pass before we tear down the AppKit window.
            DispatchQueue.main.async { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                UserDefaults.standard.set(true, forKey: setupCompleteKey)
                guard let window = self?.onboardingWindow else { return }
                // Drop the SwiftUI hosting controller first so its retain on
                // the view tree is released before AppKit tears the window
                // down. Closing with the contentViewController still attached
                // lets a SwiftUI-owned object slip into the next autorelease
                // pool drain — the v1.0.10/11 over-release crash.
                window.contentViewController = nil
                window.close()
                self?.onboardingWindow = nil
                // Restore the menu-bar-agent baseline (LSUIElement = true in
                // Info.plist). showOnboarding() flips to .regular so the
                // window joins the Dock — without this reset the Dock icon
                // lingers after Done. Lost in the v1.0.11 closure rewrite,
                // restored here.
                NSApp.setActivationPolicy(.accessory)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GooseNeck Setup"
        // CRITICAL: programmatically-created NSWindows default to
        // isReleasedWhenClosed = true. Combined with our strong
        // `onboardingWindow` reference, close() releases once and ARC
        // releases again on `onboardingWindow = nil` → over-release →
        // SIGSEGV in objc_release during the next autorelease pool drain.
        // This was the v1.0.6–v1.0.11 "Done click" crash. ARC owns lifetime.
        window.isReleasedWhenClosed = false
        // Animations disabled — the default .documentWindow transform
        // animation crashes on dealloc with SwiftUI content.
        window.animationBehavior = .none

        // NSHostingController is the canonical container for SwiftUI views
        // hosted as an NSWindow contentViewController. Apple's docs note
        // it manages the SwiftUI lifecycle (environment, scene, layout)
        // more correctly than NSHostingView, which is intended for
        // embedding SwiftUI inside an existing AppKit view hierarchy.
        // Using NSHostingController eliminates a class of autorelease
        // pool over-release crashes on macOS 26.
        let onboardingViewController = NSHostingController(
            rootView: OnboardingView(
                onComplete: onComplete,
                initialStep: startAt
            )
            .environment(viewModel)
            .environment(GooseNeckApp.licenseManager)
        )
        window.contentViewController = onboardingViewController
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Local notifications are suppressed by default while the app is frontmost.
        // GooseNeck should still surface posture/break/fatigue alerts in that state.
        [.banner, .list, .sound]
    }
}
