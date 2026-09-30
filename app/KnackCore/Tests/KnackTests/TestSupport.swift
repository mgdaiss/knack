import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KnackCore

/// Paths into the app sources, so tests exercise the manifests and config that actually ship.
enum Repo {
    static let appDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // KnackTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // KnackCore
        .deletingLastPathComponent() // app
    static let skillsDir = appDir.appendingPathComponent("Knack/Skills")
    static let modelTiers = appDir.appendingPathComponent("Knack/Resources/ModelTiers.json")
}

func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    return try Data(contentsOf: url)
}

func manifest(
    id: String = "com.knack.test",
    permissions: [Capability] = [.modelText],
    never: [Capability] = [],
    tier: ModelTier? = .textFast
) -> SkillManifest {
    SkillManifest(
        id: id, name: "Test", tagline: "A test skill",
        character: .init(asset: "test", color: "#123456", tint: "#ABCDEF"),
        category: "test", permissions: permissions, never: never,
        triggers: [.init(type: .window, examples: nil, shortcut: nil)],
        model: tier.map { .init(tier: $0, maxCostPerRunUSD: 0.01) }, version: "1.0.0")
}

/// Scripted HTTP transport. Records requests; answers from a queue of responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { let status: Int; let body: String }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    var bodies: [[String: Any]] {
        lock.withLock { requests.compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } } }
    }

    private func next(_ request: URLRequest) -> Reply {
        lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "no more replies") : replies.removeFirst()
        }
    }

    func data(for request: URLRequest) async throws -> (Data, Int) {
        let r = next(request)
        return (Data(r.body.utf8), r.status)
    }

    func lines(for request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>) {
        let r = next(request)
        // Mirror URLSession.AsyncBytes.lines, which drops empty lines.
        let lines = r.body.split(separator: "\n").map(String.init)
        return (r.status, AsyncThrowingStream { c in
            lines.forEach { c.yield($0) }
            c.finish()
        })
    }
}

/// Provider that returns canned texts in order.
final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String]
    private(set) var requests: [GenerateRequest] = []
    var error: KnackError?

    init(_ texts: [String]) { self.texts = texts }

    func generate(_ request: GenerateRequest) -> AsyncThrowingStream<GenerateEvent, Error> {
        let text: String = lock.withLock {
            requests.append(request)
            return texts.isEmpty ? "" : texts.removeFirst()
        }
        let error = self.error
        return AsyncThrowingStream { c in
            if let error { c.finish(throwing: error); return }
            c.yield(.delta(text))
            c.yield(.done(GenerateSummary(requestId: "r", costUSD: 0.001, promptTokens: 10, completionTokens: 5)))
            c.finish()
        }
    }
}

func collect(_ stream: AsyncThrowingStream<GenerateEvent, Error>) async throws -> [GenerateEvent] {
    var out: [GenerateEvent] = []
    for try await e in stream { out.append(e) }
    return out
}

func tokenJSON(_ access: String = "access-1", _ refresh: String = "refresh-1", user: String = "u1", isNew: Bool = true) -> String {
    #"{"accessToken":"\#(access)","refreshToken":"\#(refresh)","expiresIn":3600,"user":{"id":"\#(user)","isNew":\#(isNew)}}"#
}
