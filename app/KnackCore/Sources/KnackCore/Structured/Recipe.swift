import Foundation

// Fridge Chef structured outputs (SPEC §5.3).

public struct DetectedItem: Codable, Hashable, Sendable {
    public var name: String
    public var quantity: String?
    /// "use it up first" hint, e.g. wilting greens.
    public var useSoon: Bool?

    public init(name: String, quantity: String? = nil, useSoon: Bool? = nil) {
        self.name = name
        self.quantity = quantity
        self.useSoon = useSoon
    }
}

public struct DetectedItems: StructuredOutput, Codable, Hashable {
    public var items: [DetectedItem]

    public func validate() throws {
        if items.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw StructuredOutputError("an item has an empty name")
        }
    }
}

public struct Ingredient: Codable, Hashable, Sendable {
    public var name: String
    public var amount: String?
}

public struct RecipeStep: Codable, Hashable, Sendable {
    public var text: String
    /// Cook mode shows a timer button when present.
    public var timerSeconds: Int?
}

public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var summary: String
    public var minutes: Int
    public var serves: Int
    public var vegetarian: Bool
    public var kidFriendly: Bool
    /// Detected items this recipe uses up.
    public var usesUp: [String]
    public var ingredients: [Ingredient]
    public var steps: [RecipeStep]
}

public struct RecipeSet: StructuredOutput, Codable, Hashable {
    public var recipes: [Recipe]

    public func validate() throws {
        guard recipes.count == 3 else { throw StructuredOutputError("expected exactly 3 recipes, got \(recipes.count)") }
        for r in recipes {
            if r.title.trimmingCharacters(in: .whitespaces).isEmpty { throw StructuredOutputError("a recipe has no title") }
            if r.steps.isEmpty { throw StructuredOutputError("\"\(r.title)\" has no steps") }
            if r.minutes <= 0 || r.serves <= 0 { throw StructuredOutputError("\"\(r.title)\" needs positive minutes and serves") }
            if r.steps.contains(where: { ($0.timerSeconds ?? 1) <= 0 }) {
                throw StructuredOutputError("\"\(r.title)\" has a non-positive timer")
            }
        }
    }
}
