import Foundation

/// The pasteboard operations the selection fallback needs. The app adapts `NSPasteboard`;
/// tests use an in-memory fake.
public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    /// Every item, as type identifier → raw data.
    func readItems() -> [[String: Data]]
    /// Replaces the contents with `items`.
    func writeItems(_ items: [[String: Data]])
    func readString() -> String?
    func writeString(_ string: String)
}

/// A full copy of the pasteboard, taken before we borrow it for ⌘C/⌘V.
public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }

    public static func capture(_ pasteboard: PasteboardAccess) -> PasteboardSnapshot {
        PasteboardSnapshot(items: pasteboard.readItems())
    }

    public func restore(to pasteboard: PasteboardAccess) {
        pasteboard.writeItems(items)
    }
}

extension PasteboardAccess {
    /// Runs `body` with the pasteboard, then always puts the user's original contents back,
    /// whether `body` returns, throws or is cancelled (SPEC §5.1).
    public func preservingContents<T>(_ body: () async throws -> T) async rethrows -> T {
        let snapshot = PasteboardSnapshot.capture(self)
        defer { snapshot.restore(to: self) }
        return try await body()
    }
}
