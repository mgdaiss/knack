import Foundation

/// Routes skill requests to the active `ModelProvider` by abstract tier and logs usage for every run.
/// Skills don't use this directly; they get a `SkillModelClient` from their `SkillContext`.
public final class ModelRouter: Sendable {
    public let provider: any ModelProvider
    public let usage: UsageLog
    private let clock: @Sendable () -> Date

    public init(provider: any ModelProvider, usage: UsageLog, clock: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.usage = usage
        self.clock = clock
    }

    public func run(_ request: GenerateRequest) -> AsyncThrowingStream<GenerateEvent, Error> {
        let upstream = provider.generate(request)
        let usage = self.usage
        let clock = self.clock
        return AsyncThrowingStream { continuation in
            let task = Task {
                let started = clock()
                var summary: GenerateSummary?
                var failure: Error?
                do {
                    for try await event in upstream {
                        if case .done(let s) = event { summary = s }
                        continuation.yield(event)
                    }
                } catch {
                    failure = error
                }
                // Decide the status before finishing: finishing the stream cancels this task.
                let status: UsageRecord.Status =
                    Task.isCancelled || failure is CancellationError ? .cancelled : failure == nil ? .ok : .error
                // Log before finishing, so a caller that just finished reading sees the record.
                await usage.append(UsageRecord(
                    id: UUID(), skillId: request.skillId, tier: request.tier, date: started, status: status,
                    latencyMs: Int(clock().timeIntervalSince(started) * 1000),
                    costUSD: summary?.costUSD, promptTokens: summary?.promptTokens, completionTokens: summary?.completionTokens))
                if let failure { continuation.finish(throwing: failure) } else { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
