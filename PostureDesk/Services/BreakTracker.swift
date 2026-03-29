import Foundation

/// Tracks user presence and work sessions, sends break reminders.
@Observable
final class BreakTracker {

    enum PresenceState {
        case active
        case away
    }

    private(set) var state: PresenceState = .away
    private(set) var sessionStartTime: Date?
    private(set) var totalActiveSeconds: Int = 0
    private(set) var secondsSinceLastBreak: Int = 0
    private(set) var breaksTaken: Int = 0

    /// Configurable break interval in minutes
    var breakIntervalMinutes: Int = 45

    // Internal tracking
    private var lastActivityTime: Date?
    private let awayThreshold: TimeInterval = 30     // 30 seconds of no activity = away
    private let sessionResetThreshold: TimeInterval = 300  // 5 min away = new session

    /// Process activity status from sensor snapshot (called at 1Hz).
    func update(isActive: Bool) {
        let now = Date()

        if isActive {
            lastActivityTime = now

            if state == .away {
                // Transition: Away → Active
                transitionToActive(at: now)
            }
        }

        // Check for away transition
        if let lastActivity = lastActivityTime,
           now.timeIntervalSince(lastActivity) > awayThreshold {
            if state == .active {
                transitionToAway(at: now)
            }
        }

        // Increment active time
        if state == .active {
            totalActiveSeconds += 1
            secondsSinceLastBreak += 1
            checkBreakReminder()
        }
    }

    /// Reset session (e.g., after calibration or manual reset).
    func resetSession() {
        totalActiveSeconds = 0
        secondsSinceLastBreak = 0
        breaksTaken = 0
        sessionStartTime = Date()
    }

    /// Record that a break was taken (resets break countdown).
    func recordBreak() {
        secondsSinceLastBreak = 0
        breaksTaken += 1
    }

    // MARK: - State Transitions

    private func transitionToActive(at time: Date) {
        state = .active

        // Check if this is a new session (was away for 5+ min)
        if let lastActivity = lastActivityTime,
           time.timeIntervalSince(lastActivity) > sessionResetThreshold {
            // New session
            totalActiveSeconds = 0
            secondsSinceLastBreak = 0
            breaksTaken = 0
            sessionStartTime = time
        } else if sessionStartTime == nil {
            sessionStartTime = time
        }
    }

    private func transitionToAway(at time: Date) {
        state = .away
    }

    // MARK: - Break Reminders

    private func checkBreakReminder() {
        let minutesSinceBreak = secondsSinceLastBreak / 60

        if minutesSinceBreak >= breakIntervalMinutes {
            let hours = totalActiveSeconds / 3600
            let minutes = (totalActiveSeconds % 3600) / 60

            var durationStr: String
            if hours > 0 {
                durationStr = "\(hours)h \(minutes)m"
            } else {
                durationStr = "\(minutes)m"
            }

            NotificationManager.shared.send(
                category: "break",
                title: "PostureDesk",
                body: "You've been working for \(durationStr) straight. Stand up, stretch, look at something far away."
            )

            // Auto-reset break timer after sending (prevents repeated notifications)
            secondsSinceLastBreak = 0
            breaksTaken += 1
        }
    }
}
