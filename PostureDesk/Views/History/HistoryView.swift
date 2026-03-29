import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessions: [SessionRecord]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.sectionGap) {
                if sessions.isEmpty {
                    emptyState
                } else {
                    weeklySummary
                    weeklyChart
                    sessionList
                }
            }
            .padding(DS.Spacing.pageInset)
        }
        .background(DS.Colors.bg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(DS.Colors.textMuted)

            Text("no sessions yet")
                .font(DS.Font.metric(28))
                .foregroundStyle(DS.Colors.textSecondary)

            Text("your posture sessions will appear here\nas you use PostureDesk throughout the day")
                .font(DS.Font.body())
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Weekly Summary

    private var thisWeekSessions: [SessionRecord] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return sessions.filter { $0.startedAt >= startOfWeek }
    }

    private var lastWeekSessions: [SessionRecord] {
        let calendar = Calendar.current
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
        return sessions.filter { $0.startedAt >= lastWeekStart && $0.startedAt < thisWeekStart }
    }

    private var weeklySummary: some View {
        let thisWeek = thisWeekSessions
        let lastWeek = lastWeekSessions

        let totalMinutes = thisWeek.reduce(0) { $0 + $1.totalActiveMinutes }
        let totalAlerts = thisWeek.reduce(0) { $0 + $1.postureAlertCount }
        let totalBreaks = thisWeek.reduce(0) { $0 + $1.breaksTaken }
        let avgSession = thisWeek.isEmpty ? 0 : totalMinutes / thisWeek.count

        // Trend vs last week
        let lastWeekMinutes = lastWeek.reduce(0) { $0 + $1.totalActiveMinutes }
        let lastWeekAlerts = lastWeek.reduce(0) { $0 + $1.postureAlertCount }

        return VStack(alignment: .leading, spacing: 20) {
            Text("this week")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            HStack(spacing: 0) {
                summaryMetric(
                    value: formatDuration(totalMinutes),
                    label: "total active",
                    trend: lastWeekMinutes > 0 ? trendText(current: totalMinutes, previous: lastWeekMinutes) : nil,
                    trendPositive: true
                )

                Spacer()

                summaryMetric(
                    value: "\(thisWeek.count)",
                    label: "sessions",
                    trend: nil,
                    trendPositive: true
                )

                Spacer()

                summaryMetric(
                    value: "\(totalAlerts)",
                    label: "posture alerts",
                    trend: lastWeekAlerts > 0 ? trendText(current: totalAlerts, previous: lastWeekAlerts) : nil,
                    trendPositive: totalAlerts <= lastWeekAlerts
                )

                Spacer()

                summaryMetric(
                    value: "\(totalBreaks)",
                    label: "breaks taken",
                    trend: nil,
                    trendPositive: true
                )

                Spacer()

                summaryMetric(
                    value: avgSession > 0 ? "\(avgSession)m" : "—",
                    label: "avg session",
                    trend: nil,
                    trendPositive: true
                )
            }
        }
        .dsCard()
    }

    private func summaryMetric(value: String, label: String, trend: String?, trendPositive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(DS.Font.metric(24))
                .foregroundStyle(DS.Colors.textPrimary)

            Text(label)
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textMuted)

            if let trend {
                Text(trend)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(trendPositive ? DS.Colors.accentGood : DS.Colors.accentWarn)
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func trendText(current: Int, previous: Int) -> String {
        guard previous > 0 else { return "" }
        let change = Int(round(Double(current - previous) / Double(previous) * 100))
        if change == 0 { return "same" }
        return change > 0 ? "+\(change)%" : "\(change)%"
    }

    // MARK: - Weekly Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("daily active time")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            Chart(dailySummaries, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Minutes", day.activeMinutes)
                )
                .foregroundStyle(
                    day.alertRate > 2 ? DS.Colors.accentWarn.opacity(0.7) : DS.Colors.accentInfo.opacity(0.7)
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(DS.Colors.textMuted.opacity(0.3))
                    AxisValueLabel {
                        if let mins = value.as(Int.self) {
                            Text("\(mins)m")
                                .foregroundStyle(DS.Colors.textMuted)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .dsCard()
    }

    private var dailySummaries: [DailySummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let daySessions = sessions.filter {
                calendar.isDate($0.startedAt, inSameDayAs: date)
            }
            let totalMinutes = daySessions.reduce(0) { $0 + $1.totalActiveMinutes }
            let totalAlerts = daySessions.reduce(0) { $0 + $1.postureAlertCount }
            let alertRate = totalMinutes > 0 ? Double(totalAlerts) / Double(totalMinutes) * 60 : 0
            return DailySummary(date: date, activeMinutes: totalMinutes, alertRate: alertRate)
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recent sessions")
                .font(DS.Font.label())
                .foregroundStyle(DS.Colors.textMuted)
                .textCase(.uppercase)
                .tracking(1.5)

            LazyVStack(spacing: 8) {
                ForEach(sessions.prefix(20)) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}

private struct DailySummary {
    let date: Date
    let activeMinutes: Int
    let alertRate: Double  // alerts per hour
}
