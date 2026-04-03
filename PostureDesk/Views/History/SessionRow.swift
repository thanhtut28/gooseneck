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

                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.surfaceLabel)")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(DSRowGlass())
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

/// Compact card style — solid background, no glass/material (focus-safe)
private struct DSRowGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ? DS.Gradients.glassBorder : LinearGradient(colors: [DS.Colors.cardBorder], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 4)
    }
}
