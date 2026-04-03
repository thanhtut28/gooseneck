import AppKit
import SwiftUI

// MARK: - GooseNeck Design System
// Monkeytype-inspired aesthetic, adaptive light/dark

enum DS {
    // MARK: Colors

    enum Colors {
        static let bg = adaptive(light: "F4F4F5", dark: "0E0E12")
        static let cardBg = adaptive(light: "FFFFFF", dark: "16161A")
        static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.08)
        })

        static let textPrimary = adaptive(light: "18181B", dark: "FAFAFA")
        static let textSecondary = adaptive(light: "71717A", dark: "A1A1AA")
        static let textMuted = adaptive(light: "A1A1AA", dark: "52525B")

        static let accentGood = adaptive(light: "10B981", dark: "34D399") // More vibrant emerald/spring green
        static let accentWarn = adaptive(light: "F59E0B", dark: "FBBF24") // Solid amber
        static let accentDanger = adaptive(light: "EF4444", dark: "F87171")
        static let accentInfo = adaptive(light: "6366F1", dark: "818CF8")

        private static func adaptive(light: String, dark: String) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? NSColor(hex: dark) : NSColor(hex: light)
            })
        }
    }

    // MARK: Gradients

    enum Gradients {
        static let glassBorder = LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.02),
                Color.white.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let primaryGlow = RadialGradient(
            colors: [
                DS.Colors.accentGood.opacity(0.15),
                DS.Colors.bg.opacity(0.0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 180
        )
        
        static let driftingGlow = RadialGradient(
            colors: [
                DS.Colors.accentWarn.opacity(0.25),
                DS.Colors.bg.opacity(0.0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 180
        )
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
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.cardPadding)
            .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: DS.Spacing.cardRadius))
            // Premium glass border stroke
            .overlay(
                RoundedRectangle(cornerRadius: DS.Spacing.cardRadius)
                    .stroke(
                        colorScheme == .dark ? DS.Gradients.glassBorder : LinearGradient(colors: [DS.Colors.cardBorder], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
            // Subtle drop shadow for depth
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05),
                radius: 12, x: 0, y: 4
            )
    }
}

extension View {
    func dsCard() -> some View {
        modifier(DSCard())
    }

    func dsGlass(cornerRadius: CGFloat = DS.Spacing.cardRadius) -> some View {
        modifier(DSGlass(cornerRadius: cornerRadius))
    }

    func dsGlassCircle() -> some View {
        modifier(DSGlassCircle())
    }

    func dsGlassButton() -> some View {
        modifier(DSGlassButton())
    }
}

// MARK: - Glass Effect Modifiers (macOS 26+ with fallbacks)

struct DSGlass: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(DS.Spacing.cardPadding)
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .modifier(DSCard())
        }
    }
}

struct DSGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}

struct DSGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
}
