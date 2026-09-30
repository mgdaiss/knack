import SwiftUI

/// Filled pill button: indigo by default, darker when pressed.
struct PillButtonStyle: ButtonStyle {
    var fill: Color = Theme.Colors.indigo
    var pressedFill: Color = Theme.Colors.indigoPressed
    var foreground: Color = Theme.Colors.onAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.Size.buttonHeight)
            .background(configuration.isPressed ? pressedFill : fill, in: Capsule())
            .contentShape(Capsule())
    }
}

/// Quiet pill on the cream background.
struct SoftPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.button)
            .foregroundStyle(Theme.Colors.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.Size.buttonHeight)
            .background(configuration.isPressed ? Theme.Colors.hairline : Theme.Colors.sidebar, in: Capsule())
            .contentShape(Capsule())
    }
}

/// Keyboard shortcut hint, e.g. "⌘ K".
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.keycap)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.Colors.sidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.keycap, style: .continuous))
    }
}
