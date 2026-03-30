import SwiftUI

struct MetricCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DS.Gradients.glassBorder, lineWidth: 1.5)
                    .opacity(0.8)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}
