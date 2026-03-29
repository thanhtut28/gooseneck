import Foundation
import UserNotifications

/// Manages all PostureDesk notifications with throttling to prevent spam.
final class NotificationManager {

    static let shared = NotificationManager()

    // Throttle tracking: category → last fire time
    private var lastNotificationTime: [String: Date] = [:]

    // Throttle intervals per category
    private let throttleIntervals: [String: TimeInterval] = [
        "posture": 15 * 60,   // Max 1 per 15 min
        "break": 5 * 60,      // Max 1 per 5 min
        "fatigue": 30 * 60,   // Max 1 per 30 min
        "surface": 60,        // Max 1 per 1 min
    ]

    private init() {}

    /// Request notification permission on first use.
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            #if DEBUG
            if let error { print("[Notifications] Auth error: \(error)") }
            print("[Notifications] Permission granted: \(granted)")
            #endif
        }

        // Register action categories
        let recalibrateAction = UNNotificationAction(identifier: "recalibrate", title: "Recalibrate")
        let dismissAction = UNNotificationAction(identifier: "dismiss", title: "Dismiss")
        let snoozeAction = UNNotificationAction(identifier: "snooze", title: "Snooze 15m")
        let doneAction = UNNotificationAction(identifier: "done", title: "Done")
        let gotItAction = UNNotificationAction(identifier: "gotit", title: "Got it")

        let postureCategory = UNNotificationCategory(identifier: "posture", actions: [recalibrateAction, dismissAction], intentIdentifiers: [])
        let breakCategory = UNNotificationCategory(identifier: "break", actions: [snoozeAction, doneAction], intentIdentifiers: [])
        let fatigueCategory = UNNotificationCategory(identifier: "fatigue", actions: [gotItAction], intentIdentifiers: [])
        let surfaceCategory = UNNotificationCategory(identifier: "surface", actions: [gotItAction], intentIdentifiers: [])

        center.setNotificationCategories([postureCategory, breakCategory, fatigueCategory, surfaceCategory])
    }

    /// Send a notification if not throttled.
    func send(category: String, title: String, body: String) {
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
