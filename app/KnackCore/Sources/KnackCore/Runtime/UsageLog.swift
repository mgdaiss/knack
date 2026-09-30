import Foundation

/// One model run. Metadata only: never the prompt or the response.
public struct UsageRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case ok, error, cancelled }

    public let id: UUID
    public let skillId: String
    public let tier: ModelTier
    public let date: Date
    public var status: Status
    public var latencyMs: Int
    public var costUSD: Double?
    public var promptTokens: Int?
    public var completionTokens: Int?
}

/// Local, per-run usage log (Application Support/Knack/usage.json). Powers "This week" and usage by helper.
public actor UsageLog {
    private let fileURL: URL?
    private var records: [UsageRecord]
    private let maxRecords = 5_000

    /// `fileURL == nil` keeps the log in memory (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.iso.decode([UsageRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    public func append(_ record: UsageRecord) {
        records.append(record)
        if records.count > maxRecords { records.removeFirst(records.count - maxRecords) }
        persist()
    }

    public func all() -> [UsageRecord] { records }

    public func records(since date: Date) -> [UsageRecord] {
        records.filter { $0.date >= date }
    }

    /// Successful runs per skill since `date`.
    public func runCounts(since date: Date) -> [String: Int] {
        records(since: date).filter { $0.status == .ok }.reduce(into: [:]) { $0[$1.skillId, default: 0] += 1 }
    }

    public func totalCostUSD(since date: Date) -> Double {
        records(since: date).compactMap(\.costUSD).reduce(0, +)
    }

    public func clear() {
        records = []
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.iso.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // Losing usage stats is not worth surfacing to the user.
        }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
