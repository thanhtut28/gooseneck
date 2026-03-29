import Foundation
import ServiceManagement

/// Manages installation and status of the PostureSensorDaemon via SMAppService.
@Observable
final class DaemonInstaller {

    enum DaemonStatus: Equatable {
        case notInstalled
        case installing
        case installed
        case requiresApproval
        case failed(String)
    }

    private(set) var status: DaemonStatus = .notInstalled

    private let daemonService: SMAppService

    init() {
        self.daemonService = SMAppService.daemon(plistName: "com.posturedesk.sensor-daemon.plist")
        refreshStatus()
    }

    /// Register the daemon with launchd via SMAppService.
    /// This triggers a macOS system prompt for admin authorization.
    func install() {
        status = .installing

        do {
            try daemonService.register()
            refreshStatus()
            #if DEBUG
            print("[DaemonInstaller] Daemon registered successfully")
            #endif
        } catch {
            let errorMsg = error.localizedDescription
            #if DEBUG
            print("[DaemonInstaller] Registration failed: \(errorMsg)")
            #endif

            if errorMsg.contains("approval") || errorMsg.contains("authorization") {
                status = .requiresApproval
            } else {
                status = .failed(errorMsg)
            }
        }
    }

    /// Unregister the daemon.
    func uninstall() {
        do {
            try daemonService.unregister()
            status = .notInstalled
            #if DEBUG
            print("[DaemonInstaller] Daemon unregistered")
            #endif
        } catch {
            #if DEBUG
            print("[DaemonInstaller] Unregister failed: \(error)")
            #endif
        }
    }

    /// Check current daemon status.
    func refreshStatus() {
        switch daemonService.status {
        case .enabled:
            status = .installed
        case .notRegistered:
            status = .notInstalled
        case .notFound:
            status = .notInstalled
        case .requiresApproval:
            status = .requiresApproval
        @unknown default:
            status = .notInstalled
        }
    }
}
