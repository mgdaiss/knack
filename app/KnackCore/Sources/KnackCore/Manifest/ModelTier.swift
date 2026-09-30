import Foundation

/// Abstract model tiers. Skills only ever name a tier; concrete model IDs live in server config
/// (Knack Cloud) or in `ModelTiers.json` for the DEBUG-only direct provider.
public enum ModelTier: String, Codable, Sendable, CaseIterable {
    case textFast = "text-fast"
    case textSmart = "text-smart"
    case visionFast = "vision-fast"

    public var acceptsImages: Bool { self == .visionFast }

    /// The permission a skill needs to use this tier. Vision permission also covers text-only calls.
    public func isPermitted(by permissions: Set<Capability>) -> Bool {
        if acceptsImages { return permissions.contains(.modelVision) }
        return permissions.contains(.modelText) || permissions.contains(.modelVision)
    }
}
