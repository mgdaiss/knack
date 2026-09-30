import Foundation

/// Tier → concrete OpenRouter model, from one config file (`ModelTiers.json`).
/// Used by the DEBUG-only direct provider; Knack Cloud keeps its own copy server-side (cloud/config/tiers.json).
public struct TierMap: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let model: String
        public let maxTokens: Int
    }

    public enum MapError: Error, Equatable { case missingTier(ModelTier) }

    public let entries: [String: Entry]

    public init(entries: [ModelTier: Entry]) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.rawValue, $0.value) })
    }

    public init(from decoder: Decoder) throws {
        entries = try decoder.singleValueContainer().decode([String: Entry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    public func entry(for tier: ModelTier) throws -> Entry {
        guard let e = entries[tier.rawValue] else { throw MapError.missingTier(tier) }
        return e
    }

    /// Decodes and checks that every tier is mapped.
    public static func load(from data: Data) throws -> TierMap {
        let map = try JSONDecoder().decode(TierMap.self, from: data)
        for tier in ModelTier.allCases { _ = try map.entry(for: tier) }
        return map
    }
}
