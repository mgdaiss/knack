import Foundation

/// A thing a skill can (or promises it never will) touch, e.g. `selection.read`.
/// Every capability must have a user-facing sentence in `PermissionCatalog`.
public struct Capability: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    // Phase 1 grantable permissions (SPEC §4.2).
    public static let selectionRead: Capability = "selection.read"
    public static let selectionReplace: Capability = "selection.replace"
    public static let imageInput: Capability = "image.input"
    public static let modelText: Capability = "model.text"
    public static let modelVision: Capability = "model.vision"
    public static let notifications: Capability = "notifications"
}
