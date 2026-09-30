import Foundation

/// `GET /v1/me`.
public struct Account: Codable, Equatable, Sendable {
    public struct User: Codable, Equatable, Sendable { public let id: String }
    public struct SkillUsage: Codable, Equatable, Sendable {
        public let skillId: String
        public let runs: Int
        public let spentUSD: Double
    }
    public struct Month: Codable, Equatable, Sendable {
        public let runs: Int
        public let spentUSD: Double
        public let bySkill: [SkillUsage]
    }
    public struct Limits: Codable, Equatable, Sendable {
        public let dailyCapUSD: Double
        public let dailySpentUSD: Double
    }
    public struct Payments: Codable, Equatable, Sendable {
        public let enabled: Bool
    }

    public let user: User
    public let balanceUSD: Double
    public let month: Month
    public let limits: Limits
    public let payments: Payments

    /// SPEC §3.2: show the "running low" card under $1.
    public var isLow: Bool { balanceUSD < 1 }
}

public struct SignInResult: Codable, Equatable, Sendable {
    public struct User: Codable, Equatable, Sendable {
        public let id: String
        public let isNew: Bool
    }
    public let user: User
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}
