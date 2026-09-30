import Foundation
import Testing
@testable import KnackCore

@Suite("Recipe JSON decoding")
struct StructuredOutputTests {
    @Test func decodesTheFixture() throws {
        let set = try RecipeSet.parse(String(decoding: try fixture("recipes.json"), as: UTF8.self))
        #expect(set.recipes.count == 3)
        #expect(set.recipes[0].steps[1].timerSeconds == 120)
        #expect(set.recipes[0].ingredients[2].amount == nil)
        #expect(set.recipes[1].vegetarian == false)
    }

    @Test func toleratesFencesAndChatter() throws {
        let raw = "Sure! Here you go:\n```json\n{\"items\":[{\"name\":\"eggs\",\"quantity\":\"6\"}]}\n```"
        #expect(try DetectedItems.parse(raw).items == [DetectedItem(name: "eggs", quantity: "6")])
    }

    @Test func validationRejectsWrongRecipeCount() throws {
        var set = try RecipeSet.parse(String(decoding: try fixture("recipes.json"), as: UTF8.self))
        set.recipes.removeLast()
        #expect(throws: StructuredOutputError("expected exactly 3 recipes, got 2")) { try set.validate() }
    }

    @Test func reportsMissingKeys() {
        #expect(throws: StructuredOutputError("missing key \"items\"")) { try DetectedItems.parse("{}") }
        #expect(throws: StructuredOutputError("not valid JSON")) { try DetectedItems.parse("no idea") }
    }

    @Test func retriesOnceOnParseFailureThenSucceeds() async throws {
        let recipes = String(decoding: try fixture("recipes.json"), as: UTF8.self)
        let provider = ScriptedProvider(["{\"recipes\": []}", recipes])
        let client = try context(provider).model()
        let result = try await client.decode(RecipeSet.self, [.user("ideas please")])
        #expect(result.recipes.count == 3)
        #expect(provider.requests.count == 2)
        #expect(provider.requests.allSatisfy { $0.responseFormat == .jsonObject })
        // The retry carries the bad answer and the validation error.
        let retry = provider.requests[1].messages
        #expect(retry.count == 3)
        #expect(retry[2].content == .text("That wasn't valid: expected exactly 3 recipes, got 0. Reply again with only JSON matching the requested shape."))
    }

    @Test func givesUpAfterOneRetry() async throws {
        let provider = ScriptedProvider(["nope", "still nope", "never asked"])
        let client = try context(provider).model()
        await #expect(throws: KnackError.invalidResponse) {
            try await client.decode(RecipeSet.self, [.user("ideas please")])
        }
        #expect(provider.requests.count == 2)
    }

    private func context(_ provider: ScriptedProvider) -> SkillContext {
        let router = ModelRouter(provider: provider, usage: UsageLog(fileURL: nil))
        return SkillContext(manifest: manifest(id: "com.knack.fridge-chef", permissions: [.modelVision, .imageInput], tier: .visionFast),
                            services: RuntimeServices(router: router))
    }
}
