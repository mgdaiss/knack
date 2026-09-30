import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The network seam for providers and the cloud client, so tests can script responses.
public protocol HTTPTransport: Sendable {
    /// Sends a request and returns the full response body.
    func data(for request: URLRequest) async throws -> (Data, Int)
    /// Sends a request and returns its status and body as a stream of lines (for SSE).
    /// Non-2xx bodies are still delivered as lines.
    func lines(for request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            throw error.code == .cancelled ? CancellationError() as Error : KnackError.offline
        }
    }

    public func lines(for request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>) {
        #if canImport(Darwin)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError {
            throw error.code == .cancelled ? CancellationError() as Error : KnackError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (status, stream)
        #else
        // Linux: no streaming bytes API; buffer the whole body. Only used by CI builds.
        let (data, status) = try await self.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
        return (status, AsyncThrowingStream { c in
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) { c.yield(String(line)) }
            c.finish()
        })
        #endif
    }
}
