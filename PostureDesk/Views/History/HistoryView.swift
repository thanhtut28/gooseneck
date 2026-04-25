import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PostureViewModel.self) private var viewModel
    @State private var selectedDate: Date?
    @State private var historyData = HistorySnapshot.empty
    @State private var isLoadingSessions = true

    var body: some View {
        let history = historyData

        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                if isLoadingSessions {
                    loadingState
                } else if history.recentSessions.isEmpty {
                    emptyState
                } else {
                    weeklySummary(using: history)
                    weeklyChart(using: history)
                    sessionList(using: history)
                }
            }
            .padding(DS.Spacing.pageInset)
        }
        .background(DS.Colors.bg)
        .task {
            reloadHistory()
        }
        .onChange(of: viewModel.historyRefreshToken) {
            reloadHistory()
        }
    }

    private func reloadHistory() {
        isLoadingSessions = true
        Task { @MainActor in
            do {
                historyData = try HistoryStore.load(from: modelContext)
            } catch {
                #if DEBUG
                print("[History] Failed to load history: \(error)")
                #endif
                historyData = .empty
            }
            isLoadingSessions = false
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(DS.Colors.textMuted)
            Text("Loading history…")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.Colors.textSecondary)
                .padding(.bottom, 12)

            Text("no sessions yet")
                .font(DS.Font.metric(28))
                .foregroundStyle(DS.Colors.textPrimary)

            Text("your posture insights will appear here\nas you use GooseNeck throughout the day")
                .font(DS.Font.body())
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Weekly Summary

    private func weeklySummary(using history: HistorySnapshot) -> some View {
        let thisWeek = history.thisWeek
        let lastWeek = history.lastWeek

        return VStack(alignment: .leading, spacing: DS.Spacing.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("this week")
                    .font(DS.Font.rowTitle())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)

                Text(weekDateRange)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
            }

            // Featured Card
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("total active")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.0)

                    AnimatedDurationFormatter(minutes: thisWeek.activeMinutes, font: DS.Font.metric(48), color: DS.Colors.textPrimary)

                    let trend = trendText(current: thisWeek.activeMinutes, previous: lastWeek.activeMinutes)
                    if !trend.isEmpty {
                        Text("\(trend) from last week")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(thisWeek.activeMinutes >= lastWeek.activeMinutes ? DS.Colors.accentGood : DS.Colors.accentDanger)
                    }
                }
                Spacer()
            }
            .padding(24)
            .dsCard()

            // Bento Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sectionGap) {
                bentoCard(
                    value: thisWeek.sessionCount,
                    label: "sessions"
                )

                bentoCard(
                    value: thisWeek.alertCount,
                    label: "posture alerts",
                    trend: (thisWeek.alertCount > 0 && lastWeek.alertCount > 0) ? alertTrendText(current: thisWeek.alertCount, previous: lastWeek.alertCount) : nil,
                    trendPositive: thisWeek.alertCount <= lastWeek.alertCount
                )

                bentoCard(
                    value: thisWeek.breaksTaken,
                    label: "breaks taken"
                )

                bentoCard(
                    value: thisWeek.averageSessionMinutes,
                    suffix: "m",
                    emptyText: "—",
                    label: "avg session"
                )
            }
        }
    }

    private func bentoCard(value: Int, suffix: String = "", emptyText: String? = nil, label: String, trend: String? = nil, trendPositive: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let trend {
                HStack {
                    Spacer()
                    Text(trend)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(trendPositive ? DS.Colors.accentGood : DS.Colors.accentDanger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((trendPositive ? DS.Colors.accentGood : DS.Colors.accentDanger).opacity(0.15), in: Capsule())
                }
            } else {
                Spacer().frame(height: 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                if value == 0, let emptyText {
                    Text(emptyText)
                        .font(DS.Font.metric(28))
                        .foregroundStyle(DS.Colors.textPrimary)
                } else {
                    AnimatedMetricValue(value: value, suffix: suffix, font: DS.Font.metric(28), color: DS.Colors.textPrimary)
                }

                Text(label)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dsCard()
    }

    private var weekDateRange: String {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? Date()
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(weekStart.formatted(fmt)) – \(weekEnd.formatted(fmt))"
    }

    private func trendText(current: Int, previous: Int) -> String {
        guard current > 0, previous > 0 else { return "" }
        let change = Int(round(Double(current - previous) / Double(previous) * 100))
        if change == 0 { return "" }
        return change > 0 ? "+\(change)%" : "\(change)%"
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    /// For alerts, fewer = better. Show as "↓25% fewer" or "↑25% more"
    private func alertTrendText(current: Int, previous: Int) -> String {
        guard current > 0, previous > 0 else { return "" }
        let change = Int(round(Double(current - previous) / Double(previous) * 100))
        if change == 0 { return "" }
        if change < 0 { return "↓\(abs(change))% fewer" }
        return "↑\(change)% more"
    }

    // MARK: - Weekly Chart

    private func weeklyChart(using history: HistorySnapshot) -> some View {
        let maxMinutes = history.dailySummaries.map(\.activeMinutes).max() ?? 0
        let yMax = max(maxMinutes + 10, 30) // ensure a minimum range with padding

        return VStack(alignment: .leading, spacing: 16) {
            Text("daily active time")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1.5)

            Chart(history.dailySummaries, id: \.date) { day in
                AreaMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.activeMinutes)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DS.Colors.accentInfo.opacity(0.3),
                            DS.Colors.accentInfo.opacity(0.12),
                            DS.Colors.accentInfo.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.activeMinutes)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DS.Colors.accentInfo)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.activeMinutes)
                )
                .foregroundStyle(day.alertRate > 2 ? DS.Colors.accentWarn : DS.Colors.accentInfo)
                .symbolSize(isSelected(day.date) ? 35 : 20)
                .symbol {
                    let color = day.alertRate > 2 ? DS.Colors.accentWarn : DS.Colors.accentInfo
                    if isSelected(day.date) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .strokeBorder(color, lineWidth: 1.5)
                            .frame(width: 5, height: 5)
                    }
                }

                if let selectedDate,
                   Calendar.current.isDate(day.date, inSameDayAs: selectedDate) {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(DS.Colors.accentInfo.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(DS.Font.caption())
                                    .foregroundStyle(DS.Colors.textMuted)

                                Text("\(DisplayFormatter.sessionDuration(minutes: day.activeMinutes)) active")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.textPrimary)

                                if day.alertRate > 0 {
                                    Text("\(String(format: "%.1f", day.alertRate)) alerts/hr")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(DS.Colors.accentWarn)
                                }
                            }
                            .padding(12)
                            .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Colors.textMuted.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedDate)
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(DS.Colors.textMuted.opacity(0.2))
                    AxisValueLabel {
                        if let mins = value.as(Int.self) {
                            Text(DisplayFormatter.sessionDuration(minutes: mins))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.Colors.textMuted)
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(.top, 8)
        }
        .padding(24)
        .dsCard()
    }

    // MARK: - Session List

    private func sessionList(using history: HistorySnapshot) -> some View {
        let grouped = groupSessionsByDate(history.recentSessions)

        return VStack(alignment: .leading, spacing: 12) {
            Text("recent sessions")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1.5)

            LazyVStack(spacing: 10) {
                ForEach(grouped, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .padding(.leading, 4)

                        ForEach(group.sessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }
            }
        }
    }

    private struct SessionGroup {
        let label: String
        let sessions: [SessionRecord]
    }

    private func groupSessionsByDate(_ sessions: [SessionRecord]) -> [SessionGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today

        var todaySessions: [SessionRecord] = []
        var yesterdaySessions: [SessionRecord] = []
        var thisWeekSessions: [SessionRecord] = []
        var earlierSessions: [SessionRecord] = []

        for session in sessions {
            let day = cal.startOfDay(for: session.startedAt)
            if day == today {
                todaySessions.append(session)
            } else if day == yesterday {
                yesterdaySessions.append(session)
            } else if day >= weekAgo {
                thisWeekSessions.append(session)
            } else {
                earlierSessions.append(session)
            }
        }

        var groups: [SessionGroup] = []
        if !todaySessions.isEmpty { groups.append(SessionGroup(label: "Today", sessions: todaySessions)) }
        if !yesterdaySessions.isEmpty { groups.append(SessionGroup(label: "Yesterday", sessions: yesterdaySessions)) }
        if !thisWeekSessions.isEmpty { groups.append(SessionGroup(label: "This Week", sessions: thisWeekSessions)) }
        if !earlierSessions.isEmpty { groups.append(SessionGroup(label: "Earlier", sessions: earlierSessions)) }
        return groups
    }
}

// MARK: - Animations & Formatters

private struct AnimatedMetricValue: View {
    let value: Int
    let suffix: String
    @State private var animatedValue: Double = 0
    let font: SwiftUI.Font
    let color: Color

    var body: some View {
        AnimatableSuffixText(value: animatedValue, suffix: suffix)
            .font(font)
            .foregroundStyle(color)
            .onAppear {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                    animatedValue = Double(value)
                }
            }
            .onChange(of: value) {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                    animatedValue = Double(value)
                }
            }
    }
}

private struct AnimatableSuffixText: View, Animatable {
    var value: Double
    var suffix: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value))\(suffix)")
    }
}

private struct AnimatedDurationFormatter: View {
    let minutes: Int
    @State private var animatedMinutes: Double = 0
    let font: SwiftUI.Font
    let color: Color

    var body: some View {
        AnimatableDurationText(minutes: animatedMinutes)
            .font(font)
            .foregroundStyle(color)
            .onAppear {
                withAnimation(.spring(response: 1.5, dampingFraction: 0.8)) {
                    animatedMinutes = Double(minutes)
                }
            }
            .onChange(of: minutes) {
                withAnimation(.spring(response: 1.5, dampingFraction: 0.8)) {
                    animatedMinutes = Double(minutes)
                }
            }
    }
}

private struct AnimatableDurationText: View, Animatable {
    var minutes: Double

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    var body: some View {
        let mins = Int(minutes)
        let h = mins / 60
        let m = mins % 60
        if h > 0 { Text(m > 0 ? "\(h)h \(m)m" : "\(h)h") }
        else { Text("\(m)m") }
    }
}

struct DailySummary {
    let date: Date
    let activeMinutes: Int
    let alertRate: Double
}

struct WeeklyAggregate {
    let activeMinutes: Int
    let alertCount: Int
    let breaksTaken: Int
    let sessionCount: Int
    let averageSessionMinutes: Int

    static let empty = WeeklyAggregate(
        activeMinutes: 0,
        alertCount: 0,
        breaksTaken: 0,
        sessionCount: 0,
        averageSessionMinutes: 0
    )
}

struct HistoryWindow {
    let calendar: Calendar
    let today: Date
    let chartStart: Date
    let thisWeekStart: Date
    let lastWeekStart: Date
    let nextWeekStart: Date
    let bucketRangeStart: Date

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
        self.chartStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        self.thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        self.lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
        self.nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart) ?? thisWeekStart
        self.bucketRangeStart = min(chartStart, lastWeekStart)
    }
}

struct HistorySnapshot {
    let recentSessions: [SessionRecord]
    let dailySummaries: [DailySummary]
    let thisWeek: WeeklyAggregate
    let lastWeek: WeeklyAggregate

    static let empty = HistorySnapshot(
        recentSessions: [],
        dailySummaries: [],
        thisWeek: .empty,
        lastWeek: .empty
    )

    static func build(
        recentSessions: [SessionRecord],
        aggregateSessions: [SessionRecord],
        window: HistoryWindow
    ) -> HistorySnapshot {
        var dayBuckets: [Date: DayAccumulator] = [:]
        var thisWeekSessions: [SessionRecord] = []
        var lastWeekSessions: [SessionRecord] = []

        for session in aggregateSessions {
            guard let endedAt = session.endedAt else { continue }

            if endedAt >= window.thisWeekStart, endedAt < window.nextWeekStart {
                thisWeekSessions.append(session)
            } else if endedAt >= window.lastWeekStart, endedAt < window.thisWeekStart {
                lastWeekSessions.append(session)
            }

            distribute(
                session: session,
                endedAt: endedAt,
                into: &dayBuckets,
                from: window.bucketRangeStart,
                to: window.nextWeekStart,
                calendar: window.calendar
            )
        }

        let dailySummaries = (0..<7).reversed().map { offset in
            let date = window.calendar.date(byAdding: .day, value: -offset, to: window.today) ?? window.today
            let bucket = dayBuckets[date] ?? DayAccumulator()
            let activeMinutes = Int(bucket.activeMinutes.rounded())
            let alerts = bucket.alertCount.rounded()
            let alertRate = activeMinutes > 0 ? alerts / Double(activeMinutes) * 60 : 0

            return DailySummary(date: date, activeMinutes: activeMinutes, alertRate: alertRate)
        }

        return HistorySnapshot(
            recentSessions: recentSessions,
            dailySummaries: dailySummaries,
            thisWeek: weeklyAggregate(
                for: DateInterval(start: window.thisWeekStart, end: window.nextWeekStart),
                using: dayBuckets,
                sessions: thisWeekSessions,
                calendar: window.calendar
            ),
            lastWeek: weeklyAggregate(
                for: DateInterval(start: window.lastWeekStart, end: window.thisWeekStart),
                using: dayBuckets,
                sessions: lastWeekSessions,
                calendar: window.calendar
            )
        )
    }

    static func weeklyAggregate(
        for interval: DateInterval,
        using dayBuckets: [Date: DayAccumulator],
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> WeeklyAggregate {
        var activeMinutes = 0.0
        var alertCount = 0.0
        var breaksTaken = 0.0

        var day = interval.start
        while day < interval.end {
            let bucket = dayBuckets[day] ?? DayAccumulator()
            activeMinutes += bucket.activeMinutes
            alertCount += bucket.alertCount
            breaksTaken += bucket.breaksTaken
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }

        let averageSessionMinutes: Int
        if sessions.isEmpty {
            averageSessionMinutes = 0
        } else {
            averageSessionMinutes = sessions.reduce(0) { $0 + $1.totalActiveMinutes } / sessions.count
        }

        return WeeklyAggregate(
            activeMinutes: Int(activeMinutes.rounded()),
            alertCount: Int(alertCount.rounded()),
            breaksTaken: Int(breaksTaken.rounded()),
            sessionCount: sessions.count,
            averageSessionMinutes: averageSessionMinutes
        )
    }

    static func distribute(
        session: SessionRecord,
        endedAt: Date,
        into dayBuckets: inout [Date: DayAccumulator],
        from rangeStart: Date,
        to rangeEnd: Date,
        calendar: Calendar
    ) {
        let startedAt = session.startedAt
        let effectiveStart = max(startedAt, rangeStart)
        let effectiveEnd = min(endedAt, rangeEnd)

        guard effectiveStart < effectiveEnd else {
            let dayStart = calendar.startOfDay(for: startedAt)
            guard dayStart >= rangeStart, dayStart < rangeEnd else { return }

            var bucket = dayBuckets[dayStart] ?? DayAccumulator()
            bucket.activeMinutes += Double(session.totalActiveMinutes)
            bucket.alertCount += Double(session.postureAlertCount)
            bucket.breaksTaken += Double(session.breaksTaken)
            dayBuckets[dayStart] = bucket
            return
        }

        let totalDuration = max(endedAt.timeIntervalSince(startedAt), 1)
        var dayStart = calendar.startOfDay(for: effectiveStart)

        while dayStart < effectiveEnd {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? effectiveEnd
            let overlapStart = max(startedAt, dayStart)
            let overlapEnd = min(endedAt, dayEnd)

            if overlapStart < overlapEnd {
                let ratio = overlapEnd.timeIntervalSince(overlapStart) / totalDuration
                var bucket = dayBuckets[dayStart] ?? DayAccumulator()
                bucket.activeMinutes += Double(session.totalActiveMinutes) * ratio
                bucket.alertCount += Double(session.postureAlertCount) * ratio
                bucket.breaksTaken += Double(session.breaksTaken) * ratio
                dayBuckets[dayStart] = bucket
            }

            dayStart = dayEnd
        }
    }
}

enum HistoryStore {
    @MainActor
    static func load(
        from modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> HistorySnapshot {
        let window = HistoryWindow(now: now, calendar: calendar)
        let recentSessions = try modelContext.fetch(recentSessionsDescriptor())
        let aggregateSessions = try modelContext.fetch(aggregationDescriptor(for: window))

        return HistorySnapshot.build(
            recentSessions: recentSessions,
            aggregateSessions: aggregateSessions,
            window: window
        )
    }

    static func recentSessionsDescriptor() -> FetchDescriptor<SessionRecord> {
        var descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate<SessionRecord> { session in
                session.endedAt != nil && session.totalActiveMinutes > 0
            },
            sortBy: [SortDescriptor(\SessionRecord.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        return descriptor
    }

    static func aggregationDescriptor(for window: HistoryWindow) -> FetchDescriptor<SessionRecord> {
        let bucketRangeStart = window.bucketRangeStart
        let nextWeekStart = window.nextWeekStart

        var descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate<SessionRecord> { session in
                session.totalActiveMinutes > 0
                    && session.startedAt < nextWeekStart
                    && (session.endedAt ?? bucketRangeStart) > bucketRangeStart
            },
            sortBy: [SortDescriptor(\SessionRecord.startedAt)]
        )
        descriptor.fetchLimit = 500
        return descriptor
    }
}

struct DayAccumulator {
    var activeMinutes: Double = 0
    var alertCount: Double = 0
    var breaksTaken: Double = 0
}
