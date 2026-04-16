import SwiftUI

struct LegalDocumentSheet: View {
    let title: String
    let content: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .foregroundStyle(DS.Colors.cardBorder)

            // Scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                Text(LocalizedStringKey(content))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .frame(width: 520, height: 440)
        .background(DS.Colors.bg)
    }
}
