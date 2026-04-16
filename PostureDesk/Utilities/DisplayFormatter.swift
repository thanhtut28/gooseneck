import Foundation

enum DisplayFormatter {
    static func activeDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        if seconds < 60 { return "< 1m" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(minutes)m"
    }

    static func sessionDuration(minutes: Int) -> String {
        guard minutes > 0 else { return "< 1m" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func breakCountdown(elapsedSeconds: Int, intervalMinutes: Int) -> String {
        let target = max(0, intervalMinutes) * 60
        guard target > 0 else { return "break time" }

        let remaining = max(0, target - elapsedSeconds)
        if remaining == 0 { return "break time" }
        if remaining < 60 { return "< 1 min" }
        return "in \(remaining / 60) min"
    }

    static func shortBreakCountdown(elapsedSeconds: Int, intervalMinutes: Int) -> String {
        let target = max(0, intervalMinutes) * 60
        guard target > 0 else { return "break time" }

        let remaining = max(0, target - elapsedSeconds)
        if remaining == 0 { return "break time" }
        if remaining < 60 { return "< 1 min" }
        return "in \(remaining / 60)m"
    }
}
