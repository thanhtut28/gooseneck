import SwiftUI

struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 16) {
            // Date
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("\(DisplayFormatter.sessionDuration(minutes: session.totalActiveMinutes)) · \(session.surface.label.lowercased())")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Spacer()

            // Stats
            HStack(spacing: 12) {
                miniStat("\(session.postureAlertCount)", label: "alerts",
                         color: session.postureAlertCount > 0 ? DS.Colors.accentWarn : DS.Colors.textMuted)
                miniStat("\(session.breaksTaken)", label: "breaks",
                         color: DS.Colors.accentInfo)
            }
        }
        .padding(16)
        .dsGlass(cornerRadius: 16)
    }

    private func miniStat(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textMuted)
        }
    }
}
