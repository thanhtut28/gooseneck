import SwiftUI

/// Visual picker showing miniature island silhouettes — 4 columns that
/// reflow to fewer columns when the container is narrow.
struct IslandVariantPicker: View {
    @Binding var selection: IslandVariant

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Try 4-col first
            row(columns: 4)
            // Fall back to 2-col
            row(columns: 2)
        }
    }

    private func row(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(IslandVariant.allCases) { variant in
                IslandVariantCard(variant: variant, isSelected: selection == variant)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selection = variant
                        }
                    }
            }
        }
    }
}

// MARK: - Single Variant Card

private struct IslandVariantCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let variant: IslandVariant
    let isSelected: Bool

    private var pillBg: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
    private var dotColor: Color {
        isSelected
            ? (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
            : (colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2))
    }
    private var labelColor: Color { colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2) }
    private var valueColor: Color {
        isSelected
            ? (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
            : (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
    }
    private var chipBg: Color { colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            islandSilhouette

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(variant.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? DS.Colors.accentInfo : DS.Colors.textMuted)
                }

                Text(variantSubtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .padding(2) // inset so thick stroke doesn't clip
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? DS.Colors.accentInfo.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? DS.Colors.accentInfo.opacity(0.7) : DS.Colors.cardBorder.opacity(0.6),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Silhouette

    private var islandSilhouette: some View {
        VStack(spacing: 3) {
            collapsedBar
            expandedChips
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(pillBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(dotColor)
                .frame(width: 4, height: 4)
                .padding(.leading, 6)

            Spacer()

            Text(variant.previewMinimalValue)
                .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor)
                .padding(.trailing, 6)
        }
        .frame(height: 14)
        .background(pillBg, in: Capsule())
    }

    private var expandedChips: some View {
        HStack(spacing: 3) {
            chip(label: variant.expandedCard1.label, value: variant.expandedCard1.value)
            chip(label: variant.expandedCard2.label, value: variant.expandedCard2.value)
        }
    }

    private func chip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 5, weight: .medium))
                .foregroundStyle(labelColor)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(chipBg, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var variantSubtitle: String {
        switch variant {
        case .lidAngle: "How far your screen lid has moved"
        case .tiltAngle: "How much you're leaning forward or back"
        case .sessionTime: "Expanded view reveals both angles"
        case .typingIntensity: "Typing intensity vs your baseline"
        }
    }
}
