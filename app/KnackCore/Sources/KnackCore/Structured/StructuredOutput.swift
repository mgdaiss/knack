import Foundation

/// A `Codable` type the model returns as JSON. `validate()` rejects decodable-but-useless answers.
public protocol StructuredOutput: Decodable, Sendable {
    func validate() throws
}

public struct StructuredOutputError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

extension StructuredOutput {
    /// Decodes JSON (tolerating a ```json fence or text around the object) and validates it.
    public static func parse(_ raw: String) throws -> Self {
        let json = extractJSON(raw)
        let value: Self
        do {
            value = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
        } catch let DecodingError.keyNotFound(key, _) {
            throw StructuredOutputError("missing key \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw StructuredOutputError("wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw StructuredOutputError("not valid JSON")
        }
        try value.validate()
        return value
    }
}

func extractJSON(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let open = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return trimmed }
    let closeChar: Character = trimmed[open] == "{" ? "}" : "]"
    guard let close = trimmed.lastIndex(of: closeChar), close > open else { return trimmed }
    return String(trimmed[open...close])
}
