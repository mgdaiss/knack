import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let sayItBetter = Self("sayItBetter", default: .init(.space, modifiers: [.option]))
    static let explainThis = Self("explainThis", default: .init(.e, modifiers: [.option]))
}

/// Global shortcuts (SPEC §3). Shortcut → skill ID; the user can rebind them in Settings.
@MainActor
enum HotkeyService {
    static let bindings: [(KeyboardShortcuts.Name, String)] = [
        (.sayItBetter, "com.knack.say-it-better"),
        (.explainThis, "com.knack.explain-this"),
    ]

    static func name(for skillID: String) -> KeyboardShortcuts.Name? {
        bindings.first { $0.1 == skillID }?.0
    }

    /// Current shortcut as text, e.g. "⌥Space", or nil if unset.
    static func display(for skillID: String) -> String? {
        guard let name = name(for: skillID), let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        return shortcut.description
    }

    static func register(_ handler: @escaping @MainActor (String) -> Void) {
        for (name, skillID) in bindings {
            // Key-down, not key-up: the panel should appear as fast as possible (< 150 ms).
            KeyboardShortcuts.onKeyDown(for: name) { handler(skillID) }
        }
    }
}
