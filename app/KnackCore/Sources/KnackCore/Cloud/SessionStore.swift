import Foundation

/// Knack session tokens. The app stores these in the Keychain and nowhere else.
public struct StoredSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var accessExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
    }
}

public protocol SessionStore: Sendable {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

/// For tests and previews.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: StoredSession?

    public init(_ session: StoredSession? = nil) { self.session = session }

    public func load() -> StoredSession? { lock.withLock { session } }
    public func save(_ session: StoredSession) { lock.withLock { self.session = session } }
    public func clear() { lock.withLock { session = nil } }
}
