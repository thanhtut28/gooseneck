import SwiftUI

struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 16) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("\(session.totalActiveMinutes)m · \(session.surface.label.lowercased())")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
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
        .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Colors.cardBorder, lineWidth: 1)
        )
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
