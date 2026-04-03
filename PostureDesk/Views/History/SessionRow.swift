import SwiftUI

struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 14) {
            // Duration + time
            VStack(alignment: .leading, spacing: 3) {
                Text(DisplayFormatter.sessionDuration(minutes: session.totalActiveMinutes))
                    .font(DS.Font.rowTitle())
                    .foregroundStyle(DS.Colors.textPrimary)
                    .tracking(-0.3)

                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.surface.label)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Spacer()

            // Stats
            HStack(spacing: 16) {
                miniStat("\(session.postureAlertCount)", label: "alerts",
                         color: session.postureAlertCount > 0 ? DS.Colors.accentWarn : DS.Colors.textMuted)
                miniStat("\(session.breaksTaken)", label: "breaks",
                         color: DS.Colors.accentInfo)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .dsGlass(cornerRadius: 12)
    }

    private func miniStat(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .tracking(0.5)
        }
    }
}
