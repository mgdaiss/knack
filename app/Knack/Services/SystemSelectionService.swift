import AppKit
import ApplicationServices
import KnackCore

/// Reads and replaces the selection in the frontmost app (SPEC §5.1).
/// Accessibility first; if the app doesn't expose it (Electron, many web views), borrow the
/// pasteboard with ⌘C / ⌘V and always put the user's clipboard back.
final class SystemSelectionService: SelectionService, @unchecked Sendable {
    func readSelection() async throws -> String? {
        guard AccessibilityPermission.isGranted else { throw KnackError.permissionDenied(.selectionRead) }
        if let text = Self.axSelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return try await Self.copyViaPasteboard()
    }

    func replaceSelection(with text: String) async throws {
        guard AccessibilityPermission.isGranted else { throw KnackError.permissionDenied(.selectionReplace) }
        if Self.axReplace(text) { return }
        try await Self.pasteViaPasteboard(text)
    }

    // MARK: Accessibility

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axSelectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axReplace(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    // MARK: Pasteboard fallback

    @MainActor
    private static func copyViaPasteboard() async throws -> String? {
        let pasteboard = SystemPasteboard()
        return try await pasteboard.preservingContents { () async throws -> String? in
            let before = pasteboard.changeCount
            KeySynth.commandPress(KeySynth.keyC)
            for _ in 0..<25 where pasteboard.changeCount == before {
                try await Task.sleep(nanoseconds: 12_000_000)
            }
            return pasteboard.changeCount == before ? nil : pasteboard.readString()
        }
    }

    @MainActor
    private static func pasteViaPasteboard(_ text: String) async throws {
        let pasteboard = SystemPasteboard()
        try await pasteboard.preservingContents { () async throws -> Void in
            pasteboard.writeString(text)
            KeySynth.commandPress(KeySynth.keyV)
            // Give the target app time to read the pasteboard before we restore it.
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
