#if DEBUG
import Foundation
import SwiftData

// MARK: - Deterministic PRNG

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Session Seeder

enum SessionSeeder {

    /// Deletes all existing sessions and inserts ~1 year of realistic data.
    /// Returns the number of sessions created.
    @MainActor
    static func seed(into context: ModelContext, days: Int = 365) throws -> Int {
        try clearAll(from: context)

        var rng = SeededRNG(seed: 42)
        let calendar = Calendar.current
        let now = Date()
        var totalRecords = 0
        var batch: [SessionRecord] = []

        let vacationDays = vacationDayOffsets(totalDays: days, rng: &rng)

        for dayOffset in (1...days).reversed() {
            let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: now)!
            let weekday = calendar.component(.weekday, from: dayDate) // 1=Sun, 7=Sat
            let isWeekend = weekday == 1 || weekday == 7

            // Skip days: vacations, random sick days, many weekends
            if vacationDays.contains(dayOffset) { continue }
            if !isWeekend && chance(0.05, rng: &rng) { continue }
            if isWeekend && chance(0.40, rng: &rng) { continue }

            let sessionCount = isWeekend
                ? Int.random(in: 1...2, using: &rng)
                : Int.random(in: 2...5, using: &rng)

            var hourCursor = isWeekend ? 10.0 : 8.0

            for _ in 0..<sessionCount {
                let session = makeSession(
                    dayDate: dayDate,
                    startHour: hourCursor,
                    isWeekend: isWeekend,
                    calendar: calendar,
                    rng: &rng
                )
                batch.append(session)

                let durationHours = Double(session.totalActiveMinutes) / 60.0
                hourCursor += durationHours + Double.random(in: 0.5...2.0, using: &rng)

                let cutoff = isWeekend ? 22.0 : 19.0
                if hourCursor > cutoff { break }
            }

            if batch.count >= 50 {
                for record in batch { context.insert(record) }
                try context.save()
                totalRecords += batch.count
                batch.removeAll()
            }
        }

        // Flush remaining
        if !batch.isEmpty {
            for record in batch { context.insert(record) }
            try context.save()
            totalRecords += batch.count
        }

        return totalRecords
    }

    /// Deletes every SessionRecord.
    @MainActor
    static func clearAll(from context: ModelContext) throws {
        let descriptor = FetchDescriptor<SessionRecord>()
        let all = try context.fetch(descriptor)
        for record in all { context.delete(record) }
        try context.save()
    }

    // MARK: - Private Helpers

    private static func makeSession(
        dayDate: Date,
        startHour: Double,
        isWeekend: Bool,
        calendar: Calendar,
        rng: inout SeededRNG
    ) -> SessionRecord {
        let hour = Int(startHour)
        let minute = Int((startHour - Double(hour)) * 60)
        let startDate = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: dayDate
        )!

        // Duration: workdays weighted toward 45-120 min, weekends shorter
        let activeMinutes: Int
        if isWeekend {
            activeMinutes = Int.random(in: 20...90, using: &rng)
        } else {
            // Weighted: 60% chance of 45-120, 25% of 120-180, 15% of 30-45
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.15 {
                activeMinutes = Int.random(in: 30...45, using: &rng)
            } else if roll < 0.75 {
                activeMinutes = Int.random(in: 45...120, using: &rng)
            } else {
                activeMinutes = Int.random(in: 120...240, using: &rng)
            }
        }

        // End time includes idle overhead (10-30%)
        let overhead = Double(activeMinutes) * Double.random(in: 0.10...0.30, using: &rng)
        let endDate = startDate.addingTimeInterval(Double(activeMinutes + Int(overhead)) * 60)

        // Surface
        let surface: Surface
        if isWeekend {
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.30 { surface = .desk }
            else if roll < 0.70 { surface = .lap }
            else { surface = .couch }
        } else {
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.85 { surface = .desk }
            else if roll < 0.95 { surface = .lap }
            else { surface = .couch }
        }

        // Posture alerts: ~1-3 per hour, more on non-desk surfaces
        let hoursActive = max(1.0, Double(activeMinutes) / 60.0)
        let baseRate: Double
        switch surface {
        case .desk: baseRate = Double.random(in: 0.5...2.5, using: &rng)
        case .lap: baseRate = Double.random(in: 1.5...3.5, using: &rng)
        case .couch: baseRate = Double.random(in: 2.0...4.0, using: &rng)
        default: baseRate = Double.random(in: 1.0...3.0, using: &rng)
        }
        let alertCount = max(0, Int(hoursActive * baseRate))

        // Breaks: ~1 per 45 min
        let breaksTaken = max(0, Int(Double(activeMinutes) / 45.0 * Double.random(in: 0.5...1.5, using: &rng)))

        // Typing intensity
        let hasTyping = chance(0.80, rng: &rng)
        let avgTyping = hasTyping ? Double.random(in: 0.15...0.40, using: &rng) : 0
        let peakTyping = hasTyping ? min(0.90, avgTyping + Double.random(in: 0.15...0.50, using: &rng)) : 0

        let session = SessionRecord()
        session.startedAt = startDate
        session.endedAt = endDate
        session.surface = surface
        session.totalActiveMinutes = activeMinutes
        session.postureAlertCount = alertCount
        session.breaksTaken = breaksTaken
        session.typingIntensityAvailable = hasTyping
        session.avgTypingIntensity = avgTyping
        session.peakTypingIntensity = peakTyping
        return session
    }

    /// Generate vacation blocks (1-2 blocks of 5-10 days each).
    private static func vacationDayOffsets(totalDays: Int, rng: inout SeededRNG) -> Set<Int> {
        var offsets = Set<Int>()
        let blockCount = Int.random(in: 1...2, using: &rng)
        for _ in 0..<blockCount {
            let length = Int.random(in: 5...10, using: &rng)
            let start = Int.random(in: 30...(totalDays - length - 10), using: &rng)
            for d in start..<(start + length) {
                offsets.insert(d)
            }
        }
        return offsets
    }

    private static func chance(_ probability: Double, rng: inout SeededRNG) -> Bool {
        Double.random(in: 0..<1, using: &rng) < probability
    }
}
#endif
