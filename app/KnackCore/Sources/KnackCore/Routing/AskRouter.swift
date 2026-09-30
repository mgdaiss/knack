import Foundation

/// ⌘K "Ask anything": routes a sentence to an installed skill with its input pre-filled.
/// It never answers questions itself (SPEC §2).
public struct AskRoute: Equatable, Sendable, Decodable {
    public let skillId: String
    /// Text to pre-fill in the skill (e.g. the text to rewrite). Empty if none.
    public let input: String
    public let tone: SayItBetter.Tone?

    public init(skillId: String, input: String, tone: SayItBetter.Tone? = nil) {
        self.skillId = skillId
        self.input = input
        self.tone = tone
    }
}

public enum AskRouter {
    public static let manifest = SkillManifest(
        id: "com.knack.router", name: "Ask", tagline: "Finds the right helper.",
        character: .init(asset: "knack-logo", color: "#E06A4E", tint: "#FBE0D8"),
        category: "system", permissions: [.modelText], never: [],
        triggers: [], model: .init(tier: .textFast, maxCostPerRunUSD: 0.002), version: "1.0.0")

    static let sayItBetterID = "com.knack.say-it-better"

    /// Cheap, deterministic routing first: "<instruction>: <text>" patterns and route-example overlap.
    public static func routeLocally(_ sentence: String, skills: [SkillManifest]) -> AskRoute? {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // "make this nicer: …", "rewrite: …", "explain: …"
        if let colon = trimmed.firstIndex(of: ":") {
            let head = trimmed[..<colon].lowercased()
            let body = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !body.isEmpty, let skill = bestMatch(String(head), skills: skills, threshold: 0.34) {
                return AskRoute(skillId: skill.id, input: body, tone: skill.id == sayItBetterID ? tone(in: String(head)) : nil)
            }
        }
        if let skill = bestMatch(lower, skills: skills, threshold: 0.5) {
            return AskRoute(skillId: skill.id, input: "", tone: skill.id == sayItBetterID ? tone(in: lower) : nil)
        }
        return nil
    }

    /// Falls back to a tiny model call that picks among installed skills.
    public static func route(_ sentence: String, skills: [SkillManifest], model: SkillModelClient?) async throws -> AskRoute? {
        if let local = routeLocally(sentence, skills: skills) { return local }
        guard let model, !skills.isEmpty else { return nil }
        let catalog = skills.map { "- \($0.id): \($0.name). \($0.tagline) e.g. \($0.routeExamples.prefix(3).joined(separator: "; "))" }.joined(separator: "\n")
        let decision = try await model.decode(RouteDecision.self, [
            .system("""
            Pick which helper should handle the user's sentence. Helpers:
            \(catalog)
            Reply with JSON only: {"skillId":"<id or none>","input":"<text from the sentence the helper should work on, or empty>"}
            Use "none" if no helper fits. Never answer the sentence yourself.
            """),
            .user(String(sentence.prefix(2_000))),
        ])
        guard decision.skillId != "none", skills.contains(where: { $0.id == decision.skillId }) else { return nil }
        return AskRoute(skillId: decision.skillId, input: decision.input, tone: nil)
    }

    struct RouteDecision: StructuredOutput {
        let skillId: String
        let input: String
        func validate() throws {
            if skillId.isEmpty { throw StructuredOutputError("skillId is empty") }
        }
    }

    static func tone(in text: String) -> SayItBetter.Tone? {
        let t = text.lowercased()
        if t.contains("nicer") || t.contains("kinder") || t.contains("polite") || t.contains("friendlier") { return .nicer }
        if t.contains("shorter") || t.contains("concise") || t.contains("shorten") { return .shorter }
        if t.contains("funnier") || t.contains("funny") { return .funnier }
        if t.contains("formal") || t.contains("professional") { return .formal }
        if t.contains("typo") || t.contains("spelling") || t.contains("grammar") { return .typos }
        if t.contains("firmer") || t.contains("firm") || t.contains("assertive") { return .firmer }
        return nil
    }

    private static func words(_ s: String) -> Set<String> {
        let stop: Set<String> = ["a", "an", "the", "i", "me", "my", "to", "for", "of", "this", "that", "it", "is", "can", "do", "what", "s", "please"]
        let parts = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return Set(parts).subtracting(stop)
    }

    /// Scores each skill by the best word overlap with any of its route examples.
    private static func bestMatch(_ text: String, skills: [SkillManifest], threshold: Double) -> SkillManifest? {
        let input = words(text)
        guard !input.isEmpty else { return nil }
        var best: (SkillManifest, Double)?
        for skill in skills {
            for example in skill.routeExamples {
                let ex = words(example)
                guard !ex.isEmpty else { continue }
                let score = Double(input.intersection(ex).count) / Double(ex.count)
                if score >= threshold, score > (best?.1 ?? 0) { best = (skill, score) }
            }
            if input.isSuperset(of: words(skill.name)) { return skill }
        }
        return best?.0
    }
}
