import Foundation

/// A backend that turns a `GenerateRequest` into text.
///
/// Contract (tested for every implementation):
/// - yields zero or more `.delta` events, then exactly one `.done`, then finishes;
/// - a non-streaming request yields a single `.delta` with the whole text, then `.done`;
/// - failures finish the stream by throwing a `KnackError`;
/// - cancelling the consuming task stops the underlying request.
public protocol ModelProvider: Sendable {
    func generate(_ request: GenerateRequest) -> AsyncThrowingStream<GenerateEvent, Error>
}

extension ModelProvider {
    /// Runs `body` in a task tied to the returned stream's lifetime.
    func makeStream(_ body: @escaping @Sendable (AsyncThrowingStream<GenerateEvent, Error>.Continuation) async throws -> Void) -> AsyncThrowingStream<GenerateEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await body(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}
