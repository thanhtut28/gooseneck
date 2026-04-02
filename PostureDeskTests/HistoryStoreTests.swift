import SwiftData
import XCTest
@testable import PostureDesk

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testSnapshotBuildAggregatesThisWeekAndLastWeek() {
        let calendar = makeCalendar()
        let now = fixedNow(calendar: calendar)
        let window = HistoryWindow(now: now, calendar: calendar)

        let thisWeekMorning = makeSession(
            startedAt: date(in: calendar, from: window.thisWeekStart, dayOffset: 0, hourOffset: 9),
            endedAt: date(in: calendar, from: window.thisWeekStart, dayOffset: 0, hourOffset: 10),
            totalActiveMinutes: 60,
            postureAlertCount: 2,
            breaksTaken: 1
        )
        let thisWeekAfternoon = makeSession(
            startedAt: date(in: calendar, from: window.thisWeekStart, dayOffset: 2, hourOffset: 14),
            endedAt: date(in: calendar, from: window.thisWeekStart, dayOffset: 2, hourOffset: 14, minuteOffset: 30),
            totalActiveMinutes: 30,
            postureAlertCount: 1,
            breaksTaken: 0
        )
        let lastWeekSession = makeSession(
            startedAt: date(in: calendar, from: window.lastWeekStart, dayOffset: 3, hourOffset: 11),
            endedAt: date(in: calendar, from: window.lastWeekStart, dayOffset: 3, hourOffset: 11, minuteOffset: 45),
            totalActiveMinutes: 45,
            postureAlertCount: 3,
            breaksTaken: 1
        )

        let snapshot = HistorySnapshot.build(
            recentSessions: [thisWeekAfternoon, thisWeekMorning, lastWeekSession],
            aggregateSessions: [thisWeekMorning, thisWeekAfternoon, lastWeekSession],
            window: window
        )

        XCTAssertEqual(snapshot.recentSessions.count, 3)
        XCTAssertEqual(snapshot.thisWeek.activeMinutes, 90)
        XCTAssertEqual(snapshot.thisWeek.alertCount, 3)
        XCTAssertEqual(snapshot.thisWeek.breaksTaken, 1)
        XCTAssertEqual(snapshot.thisWeek.sessionCount, 2)
        XCTAssertEqual(snapshot.thisWeek.averageSessionMinutes, 45)
        XCTAssertEqual(snapshot.lastWeek.activeMinutes, 45)
        XCTAssertEqual(snapshot.lastWeek.alertCount, 3)
        XCTAssertEqual(snapshot.lastWeek.breaksTaken, 1)
        XCTAssertEqual(snapshot.lastWeek.sessionCount, 1)
        XCTAssertEqual(snapshot.lastWeek.averageSessionMinutes, 45)
    }

    func testSnapshotBuildDistributesSpanningSessionAcrossDays() {
        let calendar = makeCalendar()
        let now = fixedNow(calendar: calendar)
        let window = HistoryWindow(now: now, calendar: calendar)

        let overnightSession = makeSession(
            startedAt: calendar.date(byAdding: .minute, value: -30, to: window.today)!,
            endedAt: calendar.date(byAdding: .minute, value: 30, to: window.today)!,
            totalActiveMinutes: 60,
            postureAlertCount: 2,
            breaksTaken: 0
        )

        let snapshot = HistorySnapshot.build(
            recentSessions: [overnightSession],
            aggregateSessions: [overnightSession],
            window: window
        )

        let yesterday = calendar.date(byAdding: .day, value: -1, to: window.today)!
        let yesterdaySummary = summary(for: yesterday, in: snapshot.dailySummaries, calendar: calendar)
        let todaySummary = summary(for: window.today, in: snapshot.dailySummaries, calendar: calendar)

        XCTAssertEqual(yesterdaySummary?.activeMinutes, 30)
        XCTAssertEqual(todaySummary?.activeMinutes, 30)
        XCTAssertEqual(snapshot.thisWeek.activeMinutes, 60)
        XCTAssertEqual(snapshot.thisWeek.sessionCount, 1)
    }

    func testHistoryStoreLoadLimitsRecentSessionsAndFetchesOverlappingSessions() throws {
        let calendar = makeCalendar()
        let now = fixedNow(calendar: calendar)
        let window = HistoryWindow(now: now, calendar: calendar)
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        for index in 0..<25 {
            let start = calendar.date(byAdding: .hour, value: -index, to: now)!
            let end = calendar.date(byAdding: .minute, value: 10, to: start)!
            context.insert(
                makeSession(
                    startedAt: start,
                    endedAt: end,
                    totalActiveMinutes: 10,
                    postureAlertCount: 0,
                    breaksTaken: 0
                )
            )
        }

        let overlappingSession = makeSession(
            startedAt: calendar.date(byAdding: .hour, value: -1, to: window.chartStart)!,
            endedAt: calendar.date(byAdding: .hour, value: 1, to: window.chartStart)!,
            totalActiveMinutes: 120,
            postureAlertCount: 2,
            breaksTaken: 1
        )
        context.insert(overlappingSession)

        let oldSession = makeSession(
            startedAt: calendar.date(byAdding: .day, value: -30, to: window.chartStart)!,
            endedAt: calendar.date(byAdding: .day, value: -30, to: window.chartStart.addingTimeInterval(600))!,
            totalActiveMinutes: 50,
            postureAlertCount: 5,
            breaksTaken: 2
        )
        context.insert(oldSession)

        try context.save()

        let aggregateSessions = try context.fetch(HistoryStore.aggregationDescriptor(for: window))
        let snapshot = try HistoryStore.load(from: context, now: now, calendar: calendar)
        let chartStartSummary = summary(for: window.chartStart, in: snapshot.dailySummaries, calendar: calendar)

        XCTAssertTrue(aggregateSessions.contains(where: { $0.persistentModelID == overlappingSession.persistentModelID }))
        XCTAssertFalse(aggregateSessions.contains(where: { $0.persistentModelID == oldSession.persistentModelID }))
        XCTAssertEqual(snapshot.recentSessions.count, 20)
        XCTAssertEqual(chartStartSummary?.activeMinutes, 60)
        XCTAssertEqual(chartStartSummary?.alertRate, 1)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
    }

    private func makeSession(
        startedAt: Date,
        endedAt: Date,
        totalActiveMinutes: Int,
        postureAlertCount: Int,
        breaksTaken: Int
    ) -> SessionRecord {
        let session = SessionRecord()
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.totalActiveMinutes = totalActiveMinutes
        session.postureAlertCount = postureAlertCount
        session.breaksTaken = breaksTaken
        return session
    }

    private func summary(
        for day: Date,
        in summaries: [DailySummary],
        calendar: Calendar
    ) -> DailySummary? {
        summaries.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func fixedNow(calendar: Calendar) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 31,
            hour: 12
        )
        return calendar.date(from: components)!
    }

    private func date(
        in calendar: Calendar,
        from base: Date,
        dayOffset: Int = 0,
        hourOffset: Int = 0,
        minuteOffset: Int = 0
    ) -> Date {
        let withDays = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        let withHours = calendar.date(byAdding: .hour, value: hourOffset, to: withDays)!
        return calendar.date(byAdding: .minute, value: minuteOffset, to: withHours)!
    }
}
