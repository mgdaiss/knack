import Foundation

/// Explain This prompt building and response parsing (SPEC §5.2).
public enum ExplainThis {
    public static let meaningHeading = "## What this means for you"
    public static let maxInputCharacters = 12_000

    public static func messages(text: String) -> [ChatMessage] {
        [
            .system("""
            You explain things in plain, friendly English for someone busy and non-technical.
            Start with a short explanation (2–5 sentences, no heading). Define any jargon you keep.
            Then, only if it's relevant to the reader (bills, letters, contracts, medical or legal text, instructions),
            add a line "\(meaningHeading)" followed by 1–3 short bullet points on what they should do or know.
            No other headings. Don't repeat the original text.
            """),
            .user(String(text.prefix(maxInputCharacters))),
        ]
    }

    /// One clarifying follow-up. Carries the original text and the explanation so far.
    public static func followUp(text: String, explanation: String, question: String) -> [ChatMessage] {
        messages(text: text) + [
            .assistant(explanation),
            .user("Follow-up question: \(question.prefix(500))\nAnswer in 1–4 plain sentences."),
        ]
    }

    public struct Sections: Equatable, Sendable {
        public var explanation: String
        public var meaning: String?
    }

    /// Splits the (possibly still streaming) response into its two parts.
    public static func sections(_ response: String) -> Sections {
        guard let range = response.range(of: meaningHeading) else {
            return Sections(explanation: response.trimmingCharacters(in: .whitespacesAndNewlines), meaning: nil)
        }
        let explanation = response[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = response[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Sections(explanation: explanation, meaning: meaning.isEmpty ? nil : meaning)
    }
}
