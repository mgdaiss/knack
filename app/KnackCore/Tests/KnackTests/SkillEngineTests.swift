import Foundation
import Testing
@testable import KnackCore

@Suite("Say It Better")
struct SayItBetterTests {
    @Test func sendsOnlyTheSelectedTextAndTone() {
        let messages = SayItBetter.messages(text: "send me the file", tone: .nicer)
        #expect(messages.count == 2)
        #expect(messages[1] == .user("send me the file"))
        guard case .text(let system) = messages[0].content else { Issue.record("system prompt"); return }
        #expect(system.contains("kinder"))
        #expect(!system.contains("voice"))
    }

    @Test func includesStyleSamplesOnlyWhenGiven() {
        let messages = SayItBetter.messages(text: "hi", tone: .firmer, styleSamples: ["hey all! quick one:"])
        guard case .text(let system) = messages[0].content else { return }
        #expect(system.contains("hey all! quick one:"))
        let typos = SayItBetter.messages(text: "hi", tone: .typos, styleSamples: ["hey all!"])
        guard case .text(let typoSystem) = typos[0].content else { return }
        #expect(!typoSystem.contains("hey all!"))
    }

    @Test func cleansQuotesAndPreambles() {
        #expect(SayItBetter.clean("\"Hi Dana!\"") == "Hi Dana!")
        #expect(SayItBetter.clean("Here's a nicer version:\nHi Dana!") == "Hi Dana!")
        #expect(SayItBetter.clean("  Hi \"Dana\"  ") == "Hi \"Dana\"")
    }

    @Test func styleSamplesAreCappedAndClearable() async {
        let store = StyleSampleStore(fileURL: nil)
        for i in 0..<50 { await store.add("sample message number \(i)") }
        await store.add("short")
        #expect(await store.count == StyleSampleStore.maxSamples)
        #expect(await store.recent(1) == ["sample message number 49"])
        await store.clear()
        #expect(await store.count == 0)
    }
}

@Suite("Explain This")
struct ExplainThisTests {
    @Test func splitsExplanationAndMeaning() {
        let s = ExplainThis.sections("A deductible is what you pay first.\n\n## What this means for you\n- You pay the first $500.")
        #expect(s.explanation == "A deductible is what you pay first.")
        #expect(s.meaning == "- You pay the first $500.")
        #expect(ExplainThis.sections("Just an explanation.") == .init(explanation: "Just an explanation.", meaning: nil))
        #expect(ExplainThis.sections("Partial\n## What this means for you").meaning == nil)
    }

    @Test func followUpCarriesContext() {
        let m = ExplainThis.followUp(text: "APR 24.9%", explanation: "It's the yearly interest.", question: "Is that high?")
        #expect(m.count == 4)
        #expect(m[1] == .user("APR 24.9%"))
        #expect(m[2] == .assistant("It's the yearly interest."))
    }
}

@Suite("Fridge Chef pipeline")
struct FridgeChefTests {
    @Test func photoToDetectedItemsToThreeRecipes() async throws {
        let photo = PickedImage(data: try fixture("fridge.jpg"), mimeType: "image/jpeg")
        let provider = ScriptedProvider([
            String(decoding: try fixture("detected-items.json"), as: UTF8.self),
            String(decoding: try fixture("recipes.json"), as: UTF8.self),
        ])
        let router = ModelRouter(provider: provider, usage: UsageLog(fileURL: nil))
        let manifest = try SkillManifest.load(from: Data(contentsOf: Repo.skillsDir.appendingPathComponent("FridgeChef/skill.json")))
        let model = try SkillContext(manifest: manifest, services: RuntimeServices(router: router)).model()

        let detected = try await model.decode(DetectedItems.self, FridgeChef.detectMessages(photo: photo))
        #expect(detected.items.count == 10)
        #expect(detected.items.first { $0.name == "spinach" }?.useSoon == true)

        let filters = FridgeChef.Filters(under30: true, vegetarian: true, serves: 5)
        let recipes = try await model.decode(RecipeSet.self, FridgeChef.recipeMessages(items: detected.items, pantry: ["rice", "pasta"], filters: filters))
        #expect(recipes.recipes.count == 3)

        // The vision call carries the photo; the recipe call carries only item names.
        #expect(provider.requests[0].messages.contains { $0.hasImages })
        #expect(provider.requests[0].tier == .visionFast)
        #expect(!provider.requests[1].messages.contains { $0.hasImages })
        guard case .text(let system) = provider.requests[1].messages[0].content,
              case .text(let user) = provider.requests[1].messages[1].content else { Issue.record("text messages"); return }
        #expect(system.contains("30 minutes or less"))
        #expect(system.contains("Vegetarian"))
        #expect(system.contains("serves 5"))
        #expect(user.contains("spinach [useSoon]"))
        #expect(user.contains("Pantry: rice, pasta"))
    }

    @Test func missingIngredients() throws {
        let set = try RecipeSet.parse(String(decoding: try fixture("recipes.json"), as: UTF8.self))
        let missing = FridgeChef.missing(for: set.recipes[1], items: [DetectedItem(name: "chicken thighs"), DetectedItem(name: "peppers")], pantry: [])
        #expect(missing == ["soy sauce"])
    }
}

@Suite("⌘K routing")
struct AskRouterTests {
    let skills: [SkillManifest] = ["SayItBetter", "ExplainThis", "FridgeChef"].map {
        try! SkillManifest.load(from: Data(contentsOf: Repo.skillsDir.appendingPathComponent("\($0)/skill.json")))
    }

    @Test func dinnerGoesToFridgeChef() {
        #expect(AskRouter.routeLocally("what's for dinner", skills: skills)?.skillId == "com.knack.fridge-chef")
        #expect(AskRouter.routeLocally("What should I make tonight?", skills: skills)?.skillId == "com.knack.fridge-chef")
    }

    @Test func makeThisNicerGoesToSayItBetterWithInput() {
        let route = AskRouter.routeLocally("make this nicer: send me the invoice today", skills: skills)
        #expect(route == AskRoute(skillId: "com.knack.say-it-better", input: "send me the invoice today", tone: .nicer))
    }

    @Test func explainGoesToExplainThis() {
        let route = AskRouter.routeLocally("explain this: amortization schedule", skills: skills)
        #expect(route?.skillId == "com.knack.explain-this")
        #expect(route?.input == "amortization schedule")
    }

    @Test func unrelatedSentencesFallThroughToTheModel() async throws {
        #expect(AskRouter.routeLocally("book me a flight to Rome", skills: skills) == nil)
        let provider = ScriptedProvider([#"{"skillId":"none","input":""}"#])
        let router = ModelRouter(provider: provider, usage: UsageLog(fileURL: nil))
        let model = try SkillContext(manifest: AskRouter.manifest, services: RuntimeServices(router: router)).model()
        #expect(try await AskRouter.route("book me a flight to Rome", skills: skills, model: model) == nil)
        #expect(provider.requests.first?.skillId == "com.knack.router")
    }

    @Test func modelCanOnlyPickInstalledSkills() async throws {
        let provider = ScriptedProvider([#"{"skillId":"com.evil.skill","input":"x"}"#, #"{"skillId":"com.knack.explain-this","input":"escrow"}"#])
        let router = ModelRouter(provider: provider, usage: UsageLog(fileURL: nil))
        let model = try SkillContext(manifest: AskRouter.manifest, services: RuntimeServices(router: router)).model()
        #expect(try await AskRouter.route("hmm escrow??", skills: skills, model: model) == nil)
        #expect(try await AskRouter.route("hmm escrow??", skills: skills, model: model) == AskRoute(skillId: "com.knack.explain-this", input: "escrow"))
    }
}
