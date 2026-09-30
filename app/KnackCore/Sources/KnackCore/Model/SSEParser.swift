import Foundation

/// Minimal Server-Sent Events line parser.
///
/// Dispatches on each `data:` line using the most recent `event:` name, because
/// `URLSession.AsyncBytes.lines` drops the blank lines that normally end an event.
/// Both Knack Cloud and OpenRouter send single-line `data:` payloads.
public struct SSEParser: Sendable {
    public struct Event: Equatable, Sendable {
        public let name: String
        public let data: String
    }

    private var pendingName: String?

    public init() {}

    public mutating func consume(_ line: String) -> Event? {
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
        if line.isEmpty { pendingName = nil; return nil }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            pendingName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            var payload = line.dropFirst(5)
            if payload.first == " " { payload = payload.dropFirst() }
            let event = Event(name: pendingName ?? "message", data: String(payload))
            pendingName = nil
            return event
        }
        return nil
    }
}
