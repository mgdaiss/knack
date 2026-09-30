#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DEBUG builds only: calls OpenRouter directly with a developer key, for local work without Knack Cloud.
/// Compiled out of Release builds entirely.
public struct DirectOpenRouterProvider: ModelProvider {
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    let apiKey: @Sendable () async throws -> String
    let tiers: TierMap
    let transport: any HTTPTransport

    public init(apiKey: @escaping @Sendable () async throws -> String, tiers: TierMap, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.tiers = tiers
        self.transport = transport
    }

    private struct Body: Encodable {
        struct UsageFlag: Encodable { let include = true }
        let model: String
        let messages: [ChatMessage]
        let max_tokens: Int
        let stream: Bool
        let response_format: ResponseFormat?
        let usage = UsageFlag()
    }

    private struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let cost: Double?
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            struct Message: Decodable { let content: String? }
            let delta: Delta?
            let message: Message?
        }
        let id: String?
        let choices: [Choice]?
        let usage: Usage?
        let error: AnyError?
    }

    private struct AnyError: Decodable {}

    public func generate(_ request: GenerateRequest) -> AsyncThrowingStream<GenerateEvent, Error> {
        let tiers = self.tiers
        let apiKey = self.apiKey
        let transport = self.transport
        return makeStream { continuation in
            let entry = try tiers.entry(for: request.tier)
            let body = Body(model: entry.model, messages: request.messages, max_tokens: entry.maxTokens, stream: request.stream, response_format: request.responseFormat)
            var urlRequest = URLRequest(url: Self.endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(try await apiKey())", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Knack (debug)", forHTTPHeaderField: "X-Title")
            urlRequest.httpBody = try JSONEncoder.api.encode(body)

            func summary(_ id: String?, _ usage: Usage?) -> GenerateSummary {
                GenerateSummary(requestId: id, model: entry.model, costUSD: usage?.cost,
                                promptTokens: usage?.prompt_tokens, completionTokens: usage?.completion_tokens)
            }

            if request.stream {
                let (status, lines) = try await transport.lines(for: urlRequest)
                guard (200..<300).contains(status) else { throw Self.error(status) }
                var parser = SSEParser()
                var id: String?
                var usage: Usage?
                for try await line in lines {
                    guard let event = parser.consume(line) else { continue }
                    if event.data == "[DONE]" { break }
                    guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(event.data.utf8)) else { continue }
                    if chunk.error != nil { throw KnackError.modelUnavailable }
                    id = id ?? chunk.id
                    if let u = chunk.usage { usage = u }
                    if let text = chunk.choices?.first?.delta?.content, !text.isEmpty { continuation.yield(.delta(text)) }
                }
                continuation.yield(.done(summary(id, usage)))
            } else {
                let (data, status) = try await transport.data(for: urlRequest)
                guard (200..<300).contains(status) else { throw Self.error(status) }
                guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
                      let text = chunk.choices?.first?.message?.content else { throw KnackError.invalidResponse }
                continuation.yield(.delta(text))
                continuation.yield(.done(summary(chunk.id, chunk.usage)))
            }
        }
    }

    static func error(_ status: Int) -> KnackError {
        switch status {
        case 401, 403: .unauthorized
        case 402: .outOfCredit
        case 429: .rateLimited
        default: .modelUnavailable
        }
    }
}
#endif
