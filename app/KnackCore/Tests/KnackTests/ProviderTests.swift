import Foundation
import Testing
@testable import KnackCore

private let base = URL(string: "https://cloud.test")!

private func signedInClient(_ transport: MockTransport, expiresAt: Date = .distantFuture) -> KnackCloudClient {
    KnackCloudClient(baseURL: base, store: InMemorySessionStore(StoredSession(accessToken: "access-0", refreshToken: "refresh-0", accessExpiresAt: expiresAt)), transport: transport)
}

private let request = GenerateRequest(skillId: "com.knack.say-it-better", tier: .textFast, messages: [.system("Rewrite."), .user("send me the file")])

/// Every ModelProvider must satisfy the same contract (see ModelProvider.swift).
private func assertContract(_ events: [GenerateEvent], text: String) {
    let doneCount = events.filter { if case .done = $0 { true } else { false } }.count
    #expect(doneCount == 1)
    if case .done = events.last {} else { Issue.record("last event must be .done") }
    let joined = events.compactMap { if case .delta(let t) = $0 { t } else { nil } }.joined()
    #expect(joined == text)
}

@Suite("ModelProvider contract: KnackCloudProvider")
struct KnackCloudProviderTests {
    @Test func streamsDeltasThenDone() async throws {
        let transport = MockTransport([.init(status: 200, body: """
            event: delta
            data: {"text":"Could you "}

            event: delta
            data: {"text":"send the file?"}

            event: done
            data: {"requestId":"r1","costUSD":0.0005,"balanceUSD":999.5,"usage":{"promptTokens":30,"completionTokens":6}}

            """)])
        let client = signedInClient(transport)
        let events = try await collect(KnackCloudProvider(client: client, transport: transport).generate(request))
        assertContract(events, text: "Could you send the file?")
        #expect(events.last == .done(GenerateSummary(requestId: "r1", costUSD: 0.0005, balanceUSD: 999.5, promptTokens: 30, completionTokens: 6)))
        #expect(client.lastKnownBalanceUSD == 999.5)

        let sent = transport.requests[0]
        #expect(sent.url?.absoluteString == "https://cloud.test/v1/generate")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer access-0")
        let body = transport.bodies[0]
        #expect(body["skillId"] as? String == "com.knack.say-it-better")
        #expect(body["tier"] as? String == "text-fast")
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] == nil, "the app never names a model")
    }

    @Test func nonStreamingYieldsOneDelta() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"requestId":"r2","text":"Hello!","costUSD":0.0001,"balanceUSD":999,"usage":{"promptTokens":1,"completionTokens":2}}"#)])
        let provider = KnackCloudProvider(client: signedInClient(transport), transport: transport)
        let req = GenerateRequest(skillId: request.skillId, tier: .textFast, messages: request.messages, responseFormat: .jsonObject, stream: false)
        let events = try await collect(provider.generate(req))
        assertContract(events, text: "Hello!")
        #expect(events.count == 2)
        #expect((transport.bodies[0]["responseFormat"] as? [String: String]) == ["type": "json_object"])
    }

    @Test func mapsAPIErrorsToKnackErrors() async throws {
        for (status, code, expected) in [(402, "out_of_credit", KnackError.outOfCredit), (429, "daily_limit", .dailyLimit), (503, "model_unavailable", .modelUnavailable)] {
            let transport = MockTransport([.init(status: status, body: #"{"error":{"code":"\#(code)","message":"x"}}"#)])
            let provider = KnackCloudProvider(client: signedInClient(transport), transport: transport)
            await #expect(throws: expected) { _ = try await collect(provider.generate(request)) }
        }
    }

    @Test func midStreamErrorEventThrows() async throws {
        let transport = MockTransport([.init(status: 200, body: """
            event: delta
            data: {"text":"Could"}
            event: error
            data: {"error":{"code":"model_unavailable","message":"x"}}
            """)])
        let provider = KnackCloudProvider(client: signedInClient(transport), transport: transport)
        await #expect(throws: KnackError.modelUnavailable) { _ = try await collect(provider.generate(request)) }
    }

    @Test func streamWithoutDoneIsInvalid() async throws {
        let transport = MockTransport([.init(status: 200, body: "event: delta\ndata: {\"text\":\"half\"}\n")])
        let provider = KnackCloudProvider(client: signedInClient(transport), transport: transport)
        await #expect(throws: KnackError.invalidResponse) { _ = try await collect(provider.generate(request)) }
    }

    @Test func refreshesOnceOn401AndRetries() async throws {
        let transport = MockTransport([
            .init(status: 401, body: #"{"error":{"code":"unauthorized","message":"x"}}"#),
            .init(status: 200, body: tokenJSON("access-1", "refresh-1")),
            .init(status: 200, body: #"{"requestId":"r","text":"ok","costUSD":0,"balanceUSD":1,"usage":{}}"#),
        ])
        let provider = KnackCloudProvider(client: signedInClient(transport), transport: transport)
        let req = GenerateRequest(skillId: request.skillId, tier: .textFast, messages: request.messages, stream: false)
        _ = try await collect(provider.generate(req))
        #expect(transport.requests.map { $0.url!.path } == ["/v1/generate", "/v1/auth/refresh", "/v1/generate"])
        #expect(transport.bodies[1]["refreshToken"] as? String == "refresh-0")
        #expect(transport.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func notSignedInThrowsBeforeAnyRequest() async throws {
        let transport = MockTransport([])
        let client = KnackCloudClient(baseURL: base, store: InMemorySessionStore(), transport: transport)
        await #expect(throws: KnackError.notSignedIn) { _ = try await collect(KnackCloudProvider(client: client, transport: transport).generate(request)) }
        #expect(transport.requests.isEmpty)
    }
}

@Suite("Knack Cloud client")
struct KnackCloudClientTests {
    @Test func signInStoresTokensAndMeDecodes() async throws {
        let store = InMemorySessionStore()
        let transport = MockTransport([
            .init(status: 200, body: tokenJSON()),
            .init(status: 200, body: #"{"user":{"id":"u1"},"balanceUSD":1000,"month":{"runs":0,"spentUSD":0,"bySkill":[]},"limits":{"dailyCapUSD":10,"dailySpentUSD":0},"payments":{"enabled":false}}"#),
        ])
        let client = KnackCloudClient(baseURL: base, store: store, transport: transport)
        let result = try await client.signInWithApple(identityToken: "jwt")
        #expect(result.user == .init(id: "u1", isNew: true))
        #expect(store.load()?.accessToken == "access-1")
        #expect(transport.bodies[0]["identityToken"] as? String == "jwt")

        let account = try await client.me()
        #expect(account.balanceUSD == 1000)
        #expect(!account.isLow)
        #expect(!account.payments.enabled)
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    @Test func refreshesAnExpiringTokenBeforeUse() async throws {
        let transport = MockTransport([.init(status: 200, body: tokenJSON("fresh", "r2"))])
        let client = signedInClient(transport, expiresAt: Date().addingTimeInterval(30))
        #expect(try await client.accessToken() == "fresh")
        #expect(transport.requests.map { $0.url!.path } == ["/v1/auth/refresh"])
    }

    @Test func rejectedRefreshSignsOut() async throws {
        let store = InMemorySessionStore(StoredSession(accessToken: "a", refreshToken: "r", accessExpiresAt: .distantPast))
        let client = KnackCloudClient(baseURL: base, store: store, transport: MockTransport([.init(status: 401, body: "{}")]))
        await #expect(throws: KnackError.notSignedIn) { _ = try await client.accessToken() }
        #expect(store.load() == nil)
    }
}

#if DEBUG
@Suite("ModelProvider contract: DirectOpenRouterProvider")
struct DirectOpenRouterProviderTests {
    let tiers = TierMap(entries: [.textFast: .init(model: "vendor/fast", maxTokens: 100), .textSmart: .init(model: "vendor/smart", maxTokens: 200), .visionFast: .init(model: "vendor/eyes", maxTokens: 300)])

    @Test func streamsAndMapsTheTier() async throws {
        let transport = MockTransport([.init(status: 200, body: """
            : OPENROUTER PROCESSING

            data: {"id":"gen-1","choices":[{"delta":{"content":"Hi "}}]}

            data: {"id":"gen-1","choices":[{"delta":{"content":"there"}}]}

            data: {"id":"gen-1","choices":[{"delta":{}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"cost":0.00002}}

            data: [DONE]
            """)])
        let provider = DirectOpenRouterProvider(apiKey: { "sk-dev" }, tiers: tiers, transport: transport)
        let events = try await collect(provider.generate(request))
        assertContract(events, text: "Hi there")
        #expect(events.last == .done(GenerateSummary(requestId: "gen-1", model: "vendor/fast", costUSD: 0.00002, promptTokens: 3, completionTokens: 2)))
        #expect(transport.bodies[0]["model"] as? String == "vendor/fast")
        #expect(transport.bodies[0]["max_tokens"] as? Int == 100)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer sk-dev")
    }

    @Test func nonStreaming() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"id":"gen-2","choices":[{"message":{"content":"{\"items\":[]}"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}"#)])
        let provider = DirectOpenRouterProvider(apiKey: { "k" }, tiers: tiers, transport: transport)
        let req = GenerateRequest(skillId: "com.knack.fridge-chef", tier: .visionFast, messages: [.user("x")], responseFormat: .jsonObject, stream: false)
        let events = try await collect(provider.generate(req))
        assertContract(events, text: #"{"items":[]}"#)
        #expect(transport.bodies[0]["model"] as? String == "vendor/eyes")
        #expect((transport.bodies[0]["response_format"] as? [String: String]) == ["type": "json_object"])
    }

    @Test func httpErrorsBecomeKnackErrors() async throws {
        let provider = DirectOpenRouterProvider(apiKey: { "k" }, tiers: tiers, transport: MockTransport([.init(status: 429, body: "slow down")]))
        await #expect(throws: KnackError.rateLimited) { _ = try await collect(provider.generate(request)) }
    }
}
#endif

@Suite("ModelRouter usage log")
struct ModelRouterTests {
    @Test func logsEveryRunWithoutContent() async throws {
        let log = UsageLog(fileURL: nil)
        let router = ModelRouter(provider: ScriptedProvider(["secret text"]), usage: log)
        _ = try await collect(router.run(request))
        let records = await log.all()
        #expect(records.count == 1)
        #expect(records[0].skillId == "com.knack.say-it-better")
        #expect(records[0].status == .ok)
        #expect(records[0].costUSD == 0.001)
        #expect(!String(decoding: try JSONEncoder().encode(records), as: UTF8.self).contains("secret"))
        #expect(await log.runCounts(since: .distantPast) == ["com.knack.say-it-better": 1])
    }

    @Test func logsFailures() async throws {
        let log = UsageLog(fileURL: nil)
        let provider = ScriptedProvider([])
        provider.error = .outOfCredit
        let router = ModelRouter(provider: provider, usage: log)
        await #expect(throws: KnackError.outOfCredit) { _ = try await collect(router.run(request)) }
        #expect(await log.all().map(\.status) == [.error])
    }

    @Test func persistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("knack-usage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let router = ModelRouter(provider: ScriptedProvider(["a"]), usage: UsageLog(fileURL: url))
        _ = try await collect(router.run(request))
        #expect(await UsageLog(fileURL: url).all().count == 1)
    }
}

@Suite("SSE parser")
struct SSEParserTests {
    @Test func handlesEventsCommentsAndMissingBlankLines() {
        var p = SSEParser()
        let lines = [": comment", "event: delta", "data: {\"text\":\"a\"}", "event: done", "data: {}", "data: plain", "data:nospace\r"]
        let events = lines.compactMap { p.consume($0) }
        #expect(events == [.init(name: "delta", data: "{\"text\":\"a\"}"), .init(name: "done", data: "{}"), .init(name: "message", data: "plain"), .init(name: "message", data: "nospace")])
    }
}
