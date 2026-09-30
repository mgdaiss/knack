import SwiftUI

/// Design tokens for direction E, "Little Characters" (SPEC §7).
/// Views take every color, font, radius and shadow from here. Never hardcode hex values in a view.
enum Theme {
    enum Colors {
        static let bg = Color(hex: 0xFDF3E7)
        static let sidebar = Color(hex: 0xF7E8D6)
        static let surface = Color(hex: 0xFFFFFF)
        static let ink = Color(hex: 0x1B1A17)
        static let muted = Color(hex: 0x6B6259)
        static let keycap = Color(hex: 0x5A5048)
        static let hairline = Color(hex: 0xF3E6D6)
        static let windowBorder = Color(hex: 0xE6D6C2)
        static let indigo = Color(hex: 0x5B61C9)
        static let indigoPressed = Color(hex: 0x4A4FB0)
        static let coral = Color(hex: 0xE06A4E)
        static let danger = Color(hex: 0xE0463A)
        static let onAccent = Color(hex: 0xFFFFFF)
        static let blobEye = ink
    }

    /// Nunito, bundled (SIL OFL). Weights 600/700/800/900.
    enum Fonts {
        enum Weight: String {
            case semibold = "Nunito-SemiBold"
            case bold = "Nunito-Bold"
            case extraBold = "Nunito-ExtraBold"
            case black = "Nunito-Black"
        }

        static func nunito(_ size: CGFloat, _ weight: Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
            .custom(weight.rawValue, size: size, relativeTo: style)
        }

        static let greeting = nunito(30, .black, relativeTo: .largeTitle)
        static let sectionTitle = nunito(20, .black, relativeTo: .title2)
        static let cardTitle = nunito(17, .black, relativeTo: .headline)
        static let body = nunito(15, .semibold)
        static let bodyBold = nunito(15, .bold)
        static let nav = nunito(15, .bold)
        static let button = nunito(14, .extraBold)
        static let label = nunito(13, .bold, relativeTo: .callout)
        static let caption = nunito(12, .extraBold, relativeTo: .caption)
        static let logo = nunito(26, .black, relativeTo: .largeTitle)
        static let bigNumber = nunito(22, .black, relativeTo: .title)
    }

    enum Radius {
        static let card: CGFloat = 24
        static let bigCard: CGFloat = 26
        static let hero: CGFloat = 30
        static let tile: CGFloat = 24
        static let smallTile: CGFloat = 12
        static let sidebarCard: CGFloat = 20
        static let stat: CGFloat = 18
        static let keycap: CGFloat = 8
        static let window: CGFloat = 14
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadows {
        // CSS `0 6px 16px rgba(120,80,40,0.08)` ≈ SwiftUI radius of half the blur.
        static let card = Shadow(color: Color(red: 120 / 255, green: 80 / 255, blue: 40 / 255).opacity(0.08), radius: 8, y: 6)
        static let tile = Shadow(color: Color(red: 120 / 255, green: 80 / 255, blue: 40 / 255).opacity(0.16), radius: 7, y: 6)
        static let navSelected = Shadow(color: Color(red: 120 / 255, green: 80 / 255, blue: 40 / 255).opacity(0.08), radius: 3, y: 2)
        static let askBar = Shadow(color: Color(red: 120 / 255, green: 80 / 255, blue: 40 / 255).opacity(0.08), radius: 6, y: 4)
    }

    enum Size {
        static let tile: CGFloat = 72
        static let tileArt: CGFloat = 56
        static let smallTile: CGFloat = 36
        static let sidebarWidth: CGFloat = 224
        static let blob: CGFloat = 32
        static let blobEye: CGFloat = 5
        static let buttonHeight: CGFloat = 40
    }
}

extension View {
    func themeShadow(_ shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// White rounded card with the standard shadow.
    func card(radius: CGFloat = Theme.Radius.card, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .themeShadow(Theme.Shadows.card)
    }
}

extension Color {
    /// For design tokens (0xRRGGBB literals in Theme only).
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// For colors that arrive as data, e.g. a manifest's `#RRGGBB` character color.
    init?(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
