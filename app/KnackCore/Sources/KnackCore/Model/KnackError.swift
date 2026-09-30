import Foundation

/// Errors the app can show. Views turn these into a helper's own voice; raw HTTP never reaches the UI.
public enum KnackError: Error, Equatable, Sendable {
    case notSignedIn
    case unauthorized
    case outOfCredit
    case dailyLimit
    case rateLimited
    case modelUnavailable
    case unknownSkill
    case tierNotAllowed
    case badRequest
    case permissionDenied(Capability)
    case offline
    case invalidResponse
    case server

    /// Maps a Knack Cloud error `code` (see cloud/API.md).
    public init(apiCode: String) {
        switch apiCode {
        case "unauthorized": self = .unauthorized
        case "out_of_credit": self = .outOfCredit
        case "daily_limit": self = .dailyLimit
        case "rate_limited": self = .rateLimited
        case "model_unavailable": self = .modelUnavailable
        case "unknown_skill": self = .unknownSkill
        case "tier_not_allowed": self = .tierNotAllowed
        case "bad_request": self = .badRequest
        default: self = .server
        }
    }

    /// Default copy, written to be spoken by a helper ("Fridge Chef says…").
    public var friendlyMessage: String {
        switch self {
        case .notSignedIn, .unauthorized: "I need you to sign in again before I can help."
        case .outOfCredit: "I'm out of credit, so I can't help right now."
        case .dailyLimit: "We've done a lot today! Let's pick this up tomorrow."
        case .rateLimited: "I'm a little out of breath. Give me a minute and try again."
        case .modelUnavailable: "My brain is taking a quick break. Try again in a moment."
        case .unknownSkill, .tierNotAllowed, .badRequest: "Something about that didn't work. Try again?"
        case .permissionDenied: "I'm not allowed to do that."
        case .offline: "I can't reach the internet right now."
        case .invalidResponse: "I got muddled. Try again?"
        case .server: "Something went wrong on our side. Try again in a bit."
        }
    }
}

struct APIErrorBody: Decodable {
    struct Inner: Decodable { let code: String; let message: String? }
    let error: Inner
}

extension KnackError {
    static func from(status: Int, body: Data) -> KnackError {
        if let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: body) {
            return KnackError(apiCode: decoded.error.code)
        }
        switch status {
        case 401: return .unauthorized
        case 402: return .outOfCredit
        case 429: return .rateLimited
        case 503: return .modelUnavailable
        default: return .server
        }
    }
}
