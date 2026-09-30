import AppKit
import KnackCore

/// `NSPasteboard.general` as a `PasteboardAccess`, copying every item and type so it can be restored exactly.
/// Used from the main actor (see `SystemSelectionService`).
final class SystemPasteboard: PasteboardAccess {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func readItems() -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [String: Data]()) { result, type in
                if let data = item.data(forType: type) { result[type.rawValue] = data }
            }
        }
    }

    func writeItems(_ items: [[String: Data]]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        pasteboard.writeObjects(objects)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

/// Synthesizes ⌘C / ⌘V into the frontmost app.
enum KeySynth {
    static let keyC: CGKeyCode = 8
    static let keyV: CGKeyCode = 9

    static func commandPress(_ key: CGKeyCode) {
        // A private source so the ⌥ the user may still be holding from the hotkey doesn't leak in.
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
