import Foundation

/// Mirrors a skill's `skill.json` (SPEC §4.1).
public struct SkillManifest: Codable, Hashable, Sendable, Identifiable {
    public struct Character: Codable, Hashable, Sendable {
        /// Asset catalog name, e.g. `fridge-chef` (tile) / `fridge-chef-glyph`.
        public let asset: String
        /// Tile color, `#RRGGBB`.
        public let color: String
        /// Light tint for cards, `#RRGGBB`.
        public let tint: String
    }

    public enum TriggerType: String, Codable, Hashable, Sendable {
        case window, hotkey, route
    }

    public struct Trigger: Codable, Hashable, Sendable {
        public let type: TriggerType
        /// Route triggers: example sentences for ⌘K routing.
        public let examples: [String]?
        /// Hotkey triggers: the default shortcut, e.g. `option+space`.
        public let shortcut: String?
    }

    public struct ModelSpec: Codable, Hashable, Sendable {
        public let tier: ModelTier
        public let maxCostPerRunUSD: Double
    }

    public let id: String
    public let name: String
    public let tagline: String
    public let character: Character
    public let category: String
    public let permissions: [Capability]
    public let never: [Capability]
    public let triggers: [Trigger]
    public let model: ModelSpec?
    public let version: String

    public var permissionSet: Set<Capability> { Set(permissions) }

    public var routeExamples: [String] {
        triggers.filter { $0.type == .route }.flatMap { $0.examples ?? [] }
    }

    public var hotkey: String? {
        triggers.first { $0.type == .hotkey }?.shortcut
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case badID(String)
        case unknownCapability(String)
        case notGrantable(String)
        case grantedAndNever(String)
        case badColor(String)
        case modelWithoutPermission(ModelTier)
        case badCost(Double)
        case emptyName

        public var description: String {
            switch self {
            case .badID(let id): "Skill id must be reverse-DNS: \(id)"
            case .unknownCapability(let c): "Unknown capability (add it to PermissionCatalog): \(c)"
            case .notGrantable(let c): "Capability can't be requested in Phase 1: \(c)"
            case .grantedAndNever(let c): "Capability is both granted and in never: \(c)"
            case .badColor(let c): "Color must be #RRGGBB: \(c)"
            case .modelWithoutPermission(let t): "Tier \(t.rawValue) needs a model permission"
            case .badCost(let c): "maxCostPerRunUSD must be > 0 and ≤ 1: \(c)"
            case .emptyName: "Skill name is empty"
            }
        }
    }

    public func validate() throws {
        if id.range(of: #"^[a-z0-9]+(\.[a-z0-9-]+){2,}$"#, options: .regularExpression) == nil {
            throw ValidationError.badID(id)
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { throw ValidationError.emptyName }
        for c in permissions {
            guard let entry = PermissionCatalog.entry(for: c) else { throw ValidationError.unknownCapability(c.rawValue) }
            if !entry.grantable { throw ValidationError.notGrantable(c.rawValue) }
        }
        for c in never {
            if PermissionCatalog.entry(for: c) == nil { throw ValidationError.unknownCapability(c.rawValue) }
            if permissions.contains(c) { throw ValidationError.grantedAndNever(c.rawValue) }
        }
        for color in [character.color, character.tint] where color.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil {
            throw ValidationError.badColor(color)
        }
        if let model {
            if !model.tier.isPermitted(by: permissionSet) { throw ValidationError.modelWithoutPermission(model.tier) }
            if !(model.maxCostPerRunUSD > 0 && model.maxCostPerRunUSD <= 1) { throw ValidationError.badCost(model.maxCostPerRunUSD) }
        }
    }

    /// Decodes and validates a manifest.
    public static func load(from data: Data) throws -> SkillManifest {
        let manifest = try JSONDecoder().decode(SkillManifest.self, from: data)
        try manifest.validate()
        return manifest
    }
}
