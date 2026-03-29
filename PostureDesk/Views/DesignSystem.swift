import AppKit
import SwiftUI

// MARK: - PostureDesk Design System
// Monkeytype-inspired aesthetic, adaptive light/dark

enum DS {
    // MARK: Colors

    enum Colors {
        static let bg = adaptive(light: "F4F4F5", dark: "1B1B1F")
        static let cardBg = adaptive(light: "FFFFFF", dark: "242428")
        static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.06)
        })

        static let textPrimary = adaptive(light: "18181B", dark: "E4E4E7")
        static let textSecondary = adaptive(light: "71717A", dark: "71717A")
        static let textMuted = adaptive(light: "A1A1AA", dark: "52525B")

        static let accentGood = adaptive(light: "16A34A", dark: "4ADE80")
        static let accentWarn = adaptive(light: "D97706", dark: "FBBF24")
        static let accentDanger = adaptive(light: "DC2626", dark: "F87171")
        static let accentInfo = adaptive(light: "6366F1", dark: "818CF8")

        private static func adaptive(light: String, dark: String) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? NSColor(hex: dark) : NSColor(hex: light)
            })
        }
    }

    // MARK: Typography

    enum Font {
        static func hero(_ size: CGFloat = 56) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func metric(_ size: CGFloat = 40) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func label() -> SwiftUI.Font {
            .system(size: 11, weight: .medium, design: .rounded)
        }
        static func caption() -> SwiftUI.Font {
            .system(size: 10, weight: .regular, design: .rounded)
        }
        static func body() -> SwiftUI.Font {
            .system(size: 13, weight: .regular, design: .rounded)
        }
    }

    // MARK: Spacing

    enum Spacing {
        static let cardPadding: CGFloat = 24
        static let sectionGap: CGFloat = 20
        static let cardRadius: CGFloat = 20
        static let pageInset: CGFloat = 32
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - SwiftUI Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Card View Modifier

struct DSCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.cardPadding)
            .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: DS.Spacing.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Spacing.cardRadius)
                    .stroke(DS.Colors.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func dsCard() -> some View {
        modifier(DSCard())
    }
}
