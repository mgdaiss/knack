import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Account and session management for Knack Cloud. Owns the session tokens (via `SessionStore`)
/// and refreshes them when they expire. Never logs tokens or request content.
public final class KnackCloudClient: @unchecked Sendable {
    public let baseURL: URL
    private let store: any SessionStore
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var refreshTask: Task<StoredSession, Error>?
    private var _lastKnownBalanceUSD: Double?

    public init(baseURL: URL, store: any SessionStore, transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.baseURL = baseURL
        self.store = store
        self.transport = transport
        self.now = now
    }

    public var isSignedIn: Bool { store.load() != nil }

    /// Most recent balance seen from `/v1/me` or a `generate` call.
    public var lastKnownBalanceUSD: Double? { lock.withLock { _lastKnownBalanceUSD } }

    func noteBalance(_ usd: Double?) {
        guard let usd else { return }
        lock.withLock { _lastKnownBalanceUSD = usd }
    }

    // MARK: Sign-in

    public func signInWithApple(identityToken: String) async throws -> SignInResult {
        try await signIn(path: "/v1/auth/apple", body: ["identityToken": identityToken])
    }

    /// Staging only (server must have `ALLOW_DEV_AUTH=true`).
    public func devSignIn(deviceId: String) async throws -> SignInResult {
        try await signIn(path: "/v1/auth/dev", body: ["deviceId": deviceId])
    }

    public func signOut() {
        lock.withLock { refreshTask?.cancel(); refreshTask = nil; _lastKnownBalanceUSD = nil }
        store.clear()
    }

    private func signIn(path: String, body: [String: String]) async throws -> SignInResult {
        let (data, status) = try await transport.data(for: request("POST", path, body: try JSONEncoder.api.encode(body), token: nil))
        guard (200..<300).contains(status) else { throw KnackError.from(status: status, body: data) }
        let tokens = try KnackCloudProvider.decode(TokenResponse.self, data)
        store.save(session(from: tokens))
        return try KnackCloudProvider.decode(SignInResult.self, data)
    }

    // MARK: Account

    public func me() async throws -> Account {
        let (data, _) = try await KnackCloudProvider.withRefresh(self) { token in
            let (data, status) = try await transport.data(for: request("GET", "/v1/me", body: nil, token: token))
            guard status == 401 || (200..<300).contains(status) else { throw KnackError.from(status: status, body: data) }
            return (status, (data, status))
        }
        let account = try KnackCloudProvider.decode(Account.self, data)
        noteBalance(account.balanceUSD)
        return account
    }

    // MARK: Tokens

    /// A valid access token, refreshing if it's about to expire (or if forced after a 401).
    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = store.load() else { throw KnackError.notSignedIn }
        if !forceRefresh && current.accessExpiresAt.timeIntervalSince(now()) > 60 {
            return current.accessToken
        }
        return try await refresh(from: current).accessToken
    }

    /// Coalesces concurrent refreshes: refresh tokens rotate, so only one may be in flight.
    private func refresh(from current: StoredSession) async throws -> StoredSession {
        let task: Task<StoredSession, Error> = lock.withLock {
            if let existing = refreshTask { return existing }
            let t = Task { [transport, store] in
                let body = try JSONEncoder.api.encode(["refreshToken": current.refreshToken])
                let (data, status) = try await transport.data(for: self.request("POST", "/v1/auth/refresh", body: body, token: nil))
                if status == 401 {
                    store.clear()
                    throw KnackError.notSignedIn
                }
                guard (200..<300).contains(status) else { throw KnackError.from(status: status, body: data) }
                let session = self.session(from: try KnackCloudProvider.decode(TokenResponse.self, data))
                store.save(session)
                return session
            }
            refreshTask = t
            return t
        }
        defer { lock.withLock { if refreshTask == task { refreshTask = nil } } }
        return try await task.value
    }

    private func session(from tokens: TokenResponse) -> StoredSession {
        StoredSession(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
                      accessExpiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)))
    }

    func request(_ method: String, _ path: String, body: Data?, token: String?) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.httpBody = body
        r.timeoutInterval = 60
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }
}
