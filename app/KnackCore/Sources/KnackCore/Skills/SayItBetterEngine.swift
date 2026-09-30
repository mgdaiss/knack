import Foundation

/// Say It Better prompt building (SPEC §5.1). Only the selected text, the tone and
/// (opt-in) the user's own style samples are sent to the model.
public enum SayItBetter {
    public enum Tone: String, CaseIterable, Codable, Sendable, Identifiable {
        case firmer, nicer, shorter, funnier, formal, typos

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .firmer: "Firmer but friendly"
            case .nicer: "Nicer"
            case .shorter: "Shorter"
            case .funnier: "Funnier"
            case .formal: "More formal"
            case .typos: "Fix typos only"
            }
        }

        var instruction: String {
            switch self {
            case .firmer: "Make it firmer and clearer about what's needed, while staying warm and friendly."
            case .nicer: "Make it kinder and warmer without changing what it asks for."
            case .shorter: "Make it noticeably shorter. Keep every important point."
            case .funnier: "Add a light, good-natured touch of humor. Keep the meaning."
            case .formal: "Make it more formal and professional."
            case .typos: "Fix only spelling, grammar and punctuation. Change nothing else."
            }
        }
    }

    public static let maxInputCharacters = 8_000

    public static func messages(text: String, tone: Tone, styleSamples: [String] = []) -> [ChatMessage] {
        var system = """
        You rewrite the user's text. \(tone.instruction)
        Keep the same language, point of view and any names, numbers, links and dates.
        Reply with only the rewritten text: no quotes, no preamble, no explanation.
        """
        if !styleSamples.isEmpty && tone != .typos {
            let samples = styleSamples.prefix(8).map { "- \($0.prefix(400))" }.joined(separator: "\n")
            system += "\n\nMatch the writer's own voice. Some things they've written:\n\(samples)"
        }
        return [.system(system), .user(String(text.prefix(maxInputCharacters)))]
    }

    /// Strips wrapping quotes or a stray "Here's…" line some models add.
    public static func clean(_ output: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.split(separator: "\n", maxSplits: 1).first,
           first.lowercased().hasPrefix("here") && first.hasSuffix(":") {
            s = String(s.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("\u{201C}", "\u{201D}")] where s.hasPrefix(open) && s.hasSuffix(close) && s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }
}

/// Opt-in "Sounds like you" samples: the user's own original texts, kept only on this Mac.
public actor StyleSampleStore {
    public static let maxSamples = 40

    private let fileURL: URL?
    private var samples: [String]

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
    }

    public var count: Int { samples.count }

    public func all() -> [String] { samples }

    /// Keeps a short-enough original the user chose to rewrite. Oldest samples drop off.
    public func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, trimmed.count <= 1_000, !samples.contains(trimmed) else { return }
        samples.append(trimmed)
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
        persist()
    }

    /// The most recent samples, for the prompt.
    public func recent(_ n: Int = 8) -> [String] { Array(samples.suffix(n)) }

    public func clear() {
        samples = []
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(samples).write(to: fileURL, options: .atomic)
    }
}
