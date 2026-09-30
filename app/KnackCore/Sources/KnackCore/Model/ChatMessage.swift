import Foundation

public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }

    public enum Part: Codable, Hashable, Sendable {
        case text(String)
        /// A `data:` URL (e.g. `data:image/jpeg;base64,…`) or https URL.
        case imageURL(String)

        private enum CodingKeys: String, CodingKey { case type, text, image_url }
        private struct ImageURL: Codable, Hashable { let url: String }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "text": self = .text(try c.decode(String.self, forKey: .text))
            case "image_url": self = .imageURL(try c.decode(ImageURL.self, forKey: .image_url).url)
            case let other:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown part type \(other)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try c.encode("text", forKey: .type)
                try c.encode(text, forKey: .text)
            case .imageURL(let url):
                try c.encode("image_url", forKey: .type)
                try c.encode(ImageURL(url: url), forKey: .image_url)
            }
        }
    }

    public enum Content: Codable, Hashable, Sendable {
        case text(String)
        case parts([Part])

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) } else { self = .parts(try c.decode([Part].self)) }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s): try c.encode(s)
            case .parts(let p): try c.encode(p)
            }
        }
    }

    public let role: Role
    public let content: Content

    public init(role: Role, content: Content) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> ChatMessage { .init(role: .system, content: .text(text)) }
    public static func user(_ text: String) -> ChatMessage { .init(role: .user, content: .text(text)) }
    public static func assistant(_ text: String) -> ChatMessage { .init(role: .assistant, content: .text(text)) }
    public static func user(_ parts: [Part]) -> ChatMessage { .init(role: .user, content: .parts(parts)) }

    public var hasImages: Bool {
        if case .parts(let parts) = content {
            return parts.contains { if case .imageURL = $0 { true } else { false } }
        }
        return false
    }
}

/// Passed through to the model as OpenAI-style `response_format`.
public enum ResponseFormat: Hashable, Sendable, Encodable {
    case jsonObject

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jsonObject: try c.encode("json_object", forKey: .type)
        }
    }

    private enum CodingKeys: String, CodingKey { case type }
}

public struct GenerateRequest: Hashable, Sendable {
    public let skillId: String
    public let tier: ModelTier
    public let messages: [ChatMessage]
    public let responseFormat: ResponseFormat?
    public let stream: Bool

    public init(skillId: String, tier: ModelTier, messages: [ChatMessage], responseFormat: ResponseFormat? = nil, stream: Bool = true) {
        self.skillId = skillId
        self.tier = tier
        self.messages = messages
        self.responseFormat = responseFormat
        self.stream = stream
    }
}

public struct GenerateSummary: Hashable, Sendable {
    public var requestId: String?
    public var model: String?
    public var costUSD: Double?
    public var balanceUSD: Double?
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(requestId: String? = nil, model: String? = nil, costUSD: Double? = nil, balanceUSD: Double? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.requestId = requestId
        self.model = model
        self.costUSD = costUSD
        self.balanceUSD = balanceUSD
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum GenerateEvent: Hashable, Sendable {
    case delta(String)
    case done(GenerateSummary)
}
