import Foundation
import UserNotifications

enum NotificationCategory: String {
    case posture
    case breakReminder = "break"
    case fatigue
    case surface
}

enum NotificationAction: String {
    case recalibrate
    case dismiss
    case snooze
    case done
    case gotIt = "gotit"
}

/// Manages all PostureDesk notifications with throttling to prevent spam.
final class NotificationManager {

    static let shared = NotificationManager()
    private static let notificationsEnabledDefaultsKey = "notificationsEnabled"

    // Throttle tracking: category → last fire time
    private var lastNotificationTime: [String: Date] = [:]

    // Throttle intervals per category
    private let throttleIntervals: [String: TimeInterval] = [
        "posture": 15 * 60,   // Max 1 per 15 min
        "break": 5 * 60,      // Max 1 per 5 min
        "fatigue": 30 * 60,   // Max 1 per 30 min
        "surface": 60,        // Max 1 per 1 min
    ]

    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: notificationsEnabledDefaultsKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsEnabledDefaultsKey)
            if notificationsEnabled {
                requestPermission()
            }
        }
    }

    var postureEnabled: Bool = UserDefaults.standard.object(forKey: "notif.posture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(postureEnabled, forKey: "notif.posture") }
    }

    var breakEnabled: Bool = UserDefaults.standard.object(forKey: "notif.break") as? Bool ?? true {
        didSet { UserDefaults.standard.set(breakEnabled, forKey: "notif.break") }
    }

    var fatigueEnabled: Bool = UserDefaults.standard.object(forKey: "notif.fatigue") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fatigueEnabled, forKey: "notif.fatigue") }
    }

    private init() {}

    /// Request notification permission on first use.
    func requestPermission() {
        guard notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            #if DEBUG
            if let error { print("[Notifications] Auth error: \(error)") }
            print("[Notifications] Permission granted: \(granted)")
            #endif
        }

        // Register action categories
        let recalibrateAction = UNNotificationAction(identifier: NotificationAction.recalibrate.rawValue, title: "Recalibrate")
        let dismissAction = UNNotificationAction(identifier: NotificationAction.dismiss.rawValue, title: "Dismiss")
        let snoozeAction = UNNotificationAction(identifier: NotificationAction.snooze.rawValue, title: "Snooze 15m")
        let doneAction = UNNotificationAction(identifier: NotificationAction.done.rawValue, title: "Done")
        let gotItAction = UNNotificationAction(identifier: NotificationAction.gotIt.rawValue, title: "Got it")

        let postureCategory = UNNotificationCategory(identifier: NotificationCategory.posture.rawValue, actions: [recalibrateAction, dismissAction], intentIdentifiers: [])
        let breakCategory = UNNotificationCategory(identifier: NotificationCategory.breakReminder.rawValue, actions: [snoozeAction, doneAction], intentIdentifiers: [])
        let fatigueCategory = UNNotificationCategory(identifier: NotificationCategory.fatigue.rawValue, actions: [gotItAction], intentIdentifiers: [])
        let surfaceCategory = UNNotificationCategory(identifier: NotificationCategory.surface.rawValue, actions: [gotItAction], intentIdentifiers: [])

        center.setNotificationCategories([postureCategory, breakCategory, fatigueCategory, surfaceCategory])
    }

    /// Send a notification if not throttled.
    func send(category: String, title: String, body: String) {
        guard notificationsEnabled else { return }

        // Per-category check
        switch category {
        case "posture": guard postureEnabled else { return }
        case "break": guard breakEnabled else { return }
        case "fatigue": guard fatigueEnabled else { return }
        default: break
        }

        // Check throttle
        if let lastTime = lastNotificationTime[category],
           let interval = throttleIntervals[category],
           Date().timeIntervalSince(lastTime) < interval {
            return  // Throttled
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(category)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error { print("[Notifications] Error: \(error)") }
            #endif
        }

        lastNotificationTime[category] = Date()
    }
}
