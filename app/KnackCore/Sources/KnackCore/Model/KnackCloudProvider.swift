import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The default provider in every build: talks only to Knack Cloud (cloud/API.md).
public struct KnackCloudProvider: ModelProvider {
    let client: KnackCloudClient
    let transport: any HTTPTransport

    public init(client: KnackCloudClient, transport: any HTTPTransport = URLSessionTransport()) {
        self.client = client
        self.transport = transport
    }

    private struct Body: Encodable {
        let skillId: String
        let tier: ModelTier
        let messages: [ChatMessage]
        let responseFormat: ResponseFormat?
        let stream: Bool
    }

    private struct Delta: Decodable { let text: String }

    private struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
    }

    private struct Done: Decodable {
        let requestId: String?
        let costUSD: Double?
        let balanceUSD: Double?
        let usage: Usage?
    }

    private struct Complete: Decodable {
        let requestId: String?
        let text: String
        let costUSD: Double?
        let balanceUSD: Double?
        let usage: Usage?
    }

    public func generate(_ request: GenerateRequest) -> AsyncThrowingStream<GenerateEvent, Error> {
        let body = Body(skillId: request.skillId, tier: request.tier, messages: request.messages, responseFormat: request.responseFormat, stream: request.stream)
        let client = self.client
        let transport = self.transport
        return makeStream { continuation in
            let payload = try JSONEncoder.api.encode(body)
            if request.stream {
                let (status, lines) = try await Self.withRefresh(client) { token in
                    let (status, lines) = try await transport.lines(for: client.request("POST", "/v1/generate", body: payload, token: token))
                    return (status, (status, lines))
                }
                guard (200..<300).contains(status) else {
                    var text = ""
                    for try await line in lines { text += line }
                    throw KnackError.from(status: status, body: Data(text.utf8))
                }
                var parser = SSEParser()
                var finished = false
                for try await line in lines {
                    guard let event = parser.consume(line) else { continue }
                    let data = Data(event.data.utf8)
                    switch event.name {
                    case "delta":
                        let delta = try Self.decode(Delta.self, data)
                        continuation.yield(.delta(delta.text))
                    case "done":
                        let done = try Self.decode(Done.self, data)
                        client.noteBalance(done.balanceUSD)
                        continuation.yield(.done(GenerateSummary(
                            requestId: done.requestId, costUSD: done.costUSD, balanceUSD: done.balanceUSD,
                            promptTokens: done.usage?.promptTokens, completionTokens: done.usage?.completionTokens)))
                        finished = true
                    case "error":
                        throw KnackError.from(status: 0, body: data)
                    default:
                        continue
                    }
                }
                if !finished { throw KnackError.invalidResponse }
            } else {
                let (status, data) = try await Self.withRefresh(client) { token in
                    let (data, status) = try await transport.data(for: client.request("POST", "/v1/generate", body: payload, token: token))
                    return (status, (status, data))
                }
                guard (200..<300).contains(status) else { throw KnackError.from(status: status, body: data) }
                let result = try Self.decode(Complete.self, data)
                client.noteBalance(result.balanceUSD)
                continuation.yield(.delta(result.text))
                continuation.yield(.done(GenerateSummary(
                    requestId: result.requestId, costUSD: result.costUSD, balanceUSD: result.balanceUSD,
                    promptTokens: result.usage?.promptTokens, completionTokens: result.usage?.completionTokens)))
            }
        }
    }

    /// Runs `send` with a valid access token, refreshing and retrying once on a 401.
    static func withRefresh<T>(_ client: KnackCloudClient, _ send: (String) async throws -> (Int, T)) async throws -> T {
        let (status, result) = try await send(try await client.accessToken())
        if status != 401 { return result }
        return try await send(try await client.accessToken(forceRefresh: true)).1
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw KnackError.invalidResponse }
    }
}
