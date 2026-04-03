import Foundation

enum BreakTrackerPresenceState {
    case active
    case away
    case paused
}

enum BreakReminderCadence: String, CaseIterable {
    case once
    case every5Minutes
    case every10Minutes
    case every15Minutes

    var label: String {
        switch self {
        case .once:
            return "Once"
        case .every5Minutes:
            return "Every 5 min"
        case .every10Minutes:
            return "Every 10 min"
        case .every15Minutes:
            return "Every 15 min"
        }
    }

    var repeatIntervalSeconds: Int? {
        switch self {
        case .once:
            return nil
        case .every5Minutes:
            return 5 * 60
        case .every10Minutes:
            return 10 * 60
        case .every15Minutes:
            return 15 * 60
        }
    }
}

struct BreakTrackerUpdateResult {
    let previousState: BreakTrackerPresenceState
    let currentState: BreakTrackerPresenceState
    let startedNewSession: Bool
    let previousSessionEndedAt: Date?
    let completedSessionActiveSeconds: Int?
    let completedSessionBreaksTaken: Int?
    let breakReminderDue: Bool

    init(
        previousState: BreakTrackerPresenceState,
        currentState: BreakTrackerPresenceState,
        startedNewSession: Bool = false,
        previousSessionEndedAt: Date? = nil,
        completedSessionActiveSeconds: Int? = nil,
        completedSessionBreaksTaken: Int? = nil,
        breakReminderDue: Bool = false
    ) {
        self.previousState = previousState
        self.currentState = currentState
        self.startedNewSession = startedNewSession
        self.previousSessionEndedAt = previousSessionEndedAt
        self.completedSessionActiveSeconds = completedSessionActiveSeconds
        self.completedSessionBreaksTaken = completedSessionBreaksTaken
        self.breakReminderDue = breakReminderDue
    }
}

/// Tracks user presence and work sessions, sends break reminders.
@MainActor @Observable
final class BreakTracker {

    private static let breakIntervalDefaultsKey = "breakIntervalMinutes"
    private static let breakReminderCadenceDefaultsKey = "breakReminderCadence"

    private(set) var state: BreakTrackerPresenceState = .away
    private(set) var sessionStartTime: Date?
    private(set) var totalActiveSeconds: Int = 0
    private(set) var secondsSinceLastBreak: Int = 0
    private(set) var breaksTaken: Int = 0
    private(set) var isBreakOverdue = false

    /// Configurable break interval in minutes
    var breakIntervalMinutes: Int = BreakTracker.loadBreakIntervalMinutes() {
        didSet {
            UserDefaults.standard.set(breakIntervalMinutes, forKey: Self.breakIntervalDefaultsKey)
        }
    }
    var breakReminderCadence: BreakReminderCadence = BreakTracker.loadBreakReminderCadence() {
        didSet {
            UserDefaults.standard.set(breakReminderCadence.rawValue, forKey: Self.breakReminderCadenceDefaultsKey)
        }
    }

    // Internal tracking
    private var lastActivityTime: Date?
    private var awayStartedAt: Date?
    private var lastBreakReminderSecondMark: Int?
    private let awayThreshold: TimeInterval = 30     // 30 seconds of no activity = away
    private let sessionResetThreshold: TimeInterval = 300  // 5 min away = new session

    /// Process activity status from sensor snapshot (called at 1Hz).
    func update(isActive: Bool, at time: Date = Date()) -> BreakTrackerUpdateResult {
        guard state != .paused else {
            return BreakTrackerUpdateResult(previousState: .paused, currentState: .paused)
        }

        let previousState = state
        var result = BreakTrackerUpdateResult(previousState: previousState, currentState: previousState)

        if isActive {
            let previousLastActivity = lastActivityTime
            lastActivityTime = time

            if state != .active {
                result = transitionToActive(
                    from: previousState,
                    at: time,
                    previousLastActivity: previousLastActivity
                )
            }
        }

        // Check for away transition
        if state == .active,
           let lastActivityTime,
           time.timeIntervalSince(lastActivityTime) > awayThreshold {
            result = transitionToAway(from: previousState, at: time)
        }

        // Increment active time
        if state == .active {
            totalActiveSeconds += 1
            secondsSinceLastBreak += 1
            result = BreakTrackerUpdateResult(
                previousState: result.previousState,
                currentState: state,
                startedNewSession: result.startedNewSession,
                previousSessionEndedAt: result.previousSessionEndedAt,
                completedSessionActiveSeconds: result.completedSessionActiveSeconds,
                completedSessionBreaksTaken: result.completedSessionBreaksTaken,
                breakReminderDue: checkBreakReminder()
            )
        }

        return result
    }

    /// Reset session (e.g., after calibration or manual reset).
    func resetSession(at time: Date = Date()) {
        totalActiveSeconds = 0
        secondsSinceLastBreak = 0
        breaksTaken = 0
        sessionStartTime = state == .active ? time : nil
        if state == .active {
            lastActivityTime = time
        }
        isBreakOverdue = false
        lastBreakReminderSecondMark = nil
    }

    /// Record that a break was taken (resets break countdown).
    func recordBreak() {
        secondsSinceLastBreak = 0
        breaksTaken += 1
        isBreakOverdue = false
        lastBreakReminderSecondMark = nil
    }

    func pause() {
        guard state != .paused else { return }
        state = .paused
        awayStartedAt = nil
    }

    func resume(isActive: Bool, at time: Date = Date()) -> BreakTrackerUpdateResult {
        guard state == .paused else {
            return update(isActive: isActive, at: time)
        }

        if isActive {
            let previousLastActivity = lastActivityTime
            lastActivityTime = time
            return transitionToActive(
                from: .paused,
                at: time,
                previousLastActivity: previousLastActivity
            )
        }

        awayStartedAt = time
        state = .away
        return BreakTrackerUpdateResult(previousState: .paused, currentState: .away)
    }

    /// Reset runtime presence/session state when monitoring fully stops.
    func stop() {
        state = .away
        sessionStartTime = nil
        totalActiveSeconds = 0
        secondsSinceLastBreak = 0
        breaksTaken = 0
        isBreakOverdue = false
        lastActivityTime = nil
        awayStartedAt = nil
        lastBreakReminderSecondMark = nil
    }

    // MARK: - State Transitions

    private func transitionToActive(
        from previousState: BreakTrackerPresenceState,
        at time: Date,
        previousLastActivity: Date?
    ) -> BreakTrackerUpdateResult {
        let priorAwayStartedAt = awayStartedAt
        state = .active
        awayStartedAt = nil

        // Check if this is a new session (was away for 5+ min)
        if let priorAwayStartedAt,
           time.timeIntervalSince(priorAwayStartedAt) > sessionResetThreshold {
            let completedSessionActiveSeconds = totalActiveSeconds
            let completedSessionBreaksTaken = breaksTaken
            totalActiveSeconds = 0
            secondsSinceLastBreak = 0
            breaksTaken = 0
            isBreakOverdue = false
            lastBreakReminderSecondMark = nil
            sessionStartTime = time
            return BreakTrackerUpdateResult(
                previousState: previousState,
                currentState: .active,
                startedNewSession: true,
                previousSessionEndedAt: previousLastActivity ?? priorAwayStartedAt,
                completedSessionActiveSeconds: completedSessionActiveSeconds,
                completedSessionBreaksTaken: completedSessionBreaksTaken
            )
        }

        if sessionStartTime == nil {
            sessionStartTime = time
        }

        return BreakTrackerUpdateResult(previousState: previousState, currentState: .active)
    }

    private func transitionToAway(from previousState: BreakTrackerPresenceState, at time: Date) -> BreakTrackerUpdateResult {
        state = .away
        awayStartedAt = lastActivityTime ?? time
        return BreakTrackerUpdateResult(previousState: previousState, currentState: .away)
    }

    // MARK: - Break Reminders

    private func checkBreakReminder() -> Bool {
        let reminderThreshold = breakIntervalMinutes * 60
        guard reminderThreshold > 0 else {
            isBreakOverdue = false
            lastBreakReminderSecondMark = nil
            return false
        }

        guard secondsSinceLastBreak >= reminderThreshold else {
            isBreakOverdue = false
            lastBreakReminderSecondMark = nil
            return false
        }

        isBreakOverdue = true

        if let repeatIntervalSeconds = breakReminderCadence.repeatIntervalSeconds {
            if let lastBreakReminderSecondMark,
               secondsSinceLastBreak - lastBreakReminderSecondMark < repeatIntervalSeconds {
                return false
            }
        } else if lastBreakReminderSecondMark != nil {
            return false
        }

        lastBreakReminderSecondMark = secondsSinceLastBreak
        return true
    }

    private static func loadBreakReminderCadence() -> BreakReminderCadence {
        guard let rawValue = UserDefaults.standard.string(forKey: breakReminderCadenceDefaultsKey),
              let cadence = BreakReminderCadence(rawValue: rawValue) else {
            return .every10Minutes
        }
        return cadence
    }

    private static func loadBreakIntervalMinutes() -> Int {
        let storedValue = UserDefaults.standard.integer(forKey: breakIntervalDefaultsKey)
        return storedValue > 0 ? storedValue : 45
    }
}
