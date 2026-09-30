import Foundation

/// Fridge Chef pipeline (SPEC §5.3): photo → detected items (vision call) → three recipes (text call).
public enum FridgeChef {
    public static let pantryStaples = ["rice", "pasta", "beans", "flour", "olive oil", "butter", "garlic", "onions", "salt & pepper", "soy sauce", "canned tomatoes", "stock"]

    public struct Filters: Equatable, Hashable, Sendable, Codable {
        public var under30: Bool = false
        public var kidFriendly: Bool = false
        public var vegetarian: Bool = false
        public var useItUpFirst: Bool = false
        public var serves: Int = 4

        public init(under30: Bool = false, kidFriendly: Bool = false, vegetarian: Bool = false, useItUpFirst: Bool = false, serves: Int = 4) {
            self.under30 = under30
            self.kidFriendly = kidFriendly
            self.vegetarian = vegetarian
            self.useItUpFirst = useItUpFirst
            self.serves = serves
        }

        var requirements: [String] {
            var r = ["Each recipe serves \(serves)."]
            if under30 { r.append("Each recipe takes 30 minutes or less in total.") }
            if kidFriendly { r.append("Kid friendly: mild flavors, familiar foods.") }
            if vegetarian { r.append("Vegetarian: no meat or fish.") }
            if useItUpFirst { r.append("Prioritize items marked useSoon.") }
            return r
        }
    }

    public static func detectMessages(photo: PickedImage) -> [ChatMessage] {
        [
            .system("""
            You look at a photo of a fridge or pantry and list the food you can see.
            Reply with JSON only: {"items":[{"name":"eggs","quantity":"about 8","useSoon":false}]}
            Use short everyday names. quantity is optional. Set useSoon true for things that look like they need using soon.
            Don't guess at things you can't see. If there's no food, return {"items":[]}.
            """),
            .user([.text("What food is in this photo?"), .imageURL(photo.dataURL)]),
        ]
    }

    public static func recipeMessages(items: [DetectedItem], pantry: [String], filters: Filters) -> [ChatMessage] {
        let have = items.map { item -> String in
            var s = item.name
            if let q = item.quantity, !q.isEmpty { s += " (\(q))" }
            if item.useSoon == true { s += " [useSoon]" }
            return s
        }
        return [
            .system("""
            You suggest exactly three dinners someone can cook tonight, mostly from what they already have.
            \(filters.requirements.joined(separator: " "))
            Reply with JSON only, matching:
            {"recipes":[{"title":"","summary":"one sentence","minutes":25,"serves":\(filters.serves),"vegetarian":false,"kidFriendly":true,
            "usesUp":["names from the list"],"ingredients":[{"name":"","amount":""}],
            "steps":[{"text":"one clear step","timerSeconds":300}]}]}
            Steps are short and one action each. Add timerSeconds only for steps that involve waiting (simmer, bake, boil).
            """),
            .user("In the fridge: \(have.joined(separator: ", ")).\nPantry: \(pantry.isEmpty ? "nothing extra" : pantry.joined(separator: ", "))."),
        ]
    }

    /// Items the recipe needs that aren't in the fridge or pantry.
    public static func missing(for recipe: Recipe, items: [DetectedItem], pantry: [String]) -> [String] {
        let have = (items.map(\.name) + pantry).map { $0.lowercased() }
        return recipe.ingredients.map(\.name).filter { ingredient in
            let i = ingredient.lowercased()
            return !have.contains { i.contains($0) || $0.contains(i) }
        }
    }
}
