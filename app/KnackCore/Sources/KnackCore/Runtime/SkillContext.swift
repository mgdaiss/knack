import Foundation

/// The only way a skill reaches runtime services. Each accessor checks the skill's manifest and
/// throws `KnackError.permissionDenied` for anything it didn't declare. Enforced here, not by convention.
public struct SkillContext: Sendable {
    public let manifest: SkillManifest
    private let services: RuntimeServices

    public init(manifest: SkillManifest, services: RuntimeServices) {
        self.manifest = manifest
        self.services = services
    }

    private func require(_ capability: Capability) throws {
        guard manifest.permissionSet.contains(capability) else { throw KnackError.permissionDenied(capability) }
    }

    public func model() throws -> SkillModelClient {
        guard manifest.permissionSet.contains(.modelText) || manifest.permissionSet.contains(.modelVision) else {
            throw KnackError.permissionDenied(.modelText)
        }
        return SkillModelClient(manifest: manifest, router: services.router)
    }

    public func selection() throws -> ScopedSelection {
        guard manifest.permissionSet.contains(.selectionRead) || manifest.permissionSet.contains(.selectionReplace) else {
            throw KnackError.permissionDenied(.selectionRead)
        }
        guard let service = services.selection else { throw KnackError.permissionDenied(.selectionRead) }
        return ScopedSelection(service: service, permissions: manifest.permissionSet)
    }

    public func imageInput() throws -> any ImageInputService {
        try require(.imageInput)
        guard let service = services.imageInput else { throw KnackError.permissionDenied(.imageInput) }
        return service
    }

    public func notifications() throws -> any NotificationService {
        try require(.notifications)
        guard let service = services.notifications else { throw KnackError.permissionDenied(.notifications) }
        return service
    }
}

/// Selection access split by read vs replace permission.
public struct ScopedSelection: Sendable {
    let service: any SelectionService
    let permissions: Set<Capability>

    public func read() async throws -> String? {
        guard permissions.contains(.selectionRead) else { throw KnackError.permissionDenied(.selectionRead) }
        return try await service.readSelection()
    }

    public func replace(with text: String) async throws {
        guard permissions.contains(.selectionReplace) else { throw KnackError.permissionDenied(.selectionReplace) }
        try await service.replaceSelection(with: text)
    }
}

/// Model access bound to one skill: checks tier permissions and fills in the skill ID.
public struct SkillModelClient: Sendable {
    public let manifest: SkillManifest
    let router: ModelRouter

    public var defaultTier: ModelTier { manifest.model?.tier ?? .textFast }

    private func request(_ messages: [ChatMessage], tier: ModelTier?, format: ResponseFormat?, stream: Bool) throws -> GenerateRequest {
        let tier = tier ?? defaultTier
        guard tier.isPermitted(by: manifest.permissionSet) else {
            throw KnackError.permissionDenied(tier.acceptsImages ? .modelVision : .modelText)
        }
        if messages.contains(where: \.hasImages) && !tier.acceptsImages {
            throw KnackError.permissionDenied(.modelVision)
        }
        return GenerateRequest(skillId: manifest.id, tier: tier, messages: messages, responseFormat: format, stream: stream)
    }

    /// Streams text deltas.
    public func stream(_ messages: [ChatMessage], tier: ModelTier? = nil) throws -> AsyncThrowingStream<String, Error> {
        let upstream = router.run(try request(messages, tier: tier, format: nil, stream: true))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in upstream {
                        if case .delta(let text) = event { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns the whole response.
    public func complete(_ messages: [ChatMessage], tier: ModelTier? = nil, format: ResponseFormat? = nil) async throws -> String {
        var text = ""
        for try await event in router.run(try request(messages, tier: tier, format: format, stream: false)) {
            if case .delta(let t) = event { text += t }
        }
        return text
    }

    /// Requests JSON, decodes it into `T`, validates it, and retries once with the error on failure.
    public func decode<T: StructuredOutput>(_ type: T.Type, _ messages: [ChatMessage], tier: ModelTier? = nil) async throws -> T {
        let first = try await complete(messages, tier: tier, format: .jsonObject)
        do {
            return try T.parse(first)
        } catch {
            let retry = messages + [
                .assistant(first),
                .user("That wasn't valid: \(error). Reply again with only JSON matching the requested shape."),
            ]
            let second = try await complete(retry, tier: tier, format: .jsonObject)
            do { return try T.parse(second) } catch { throw KnackError.invalidResponse }
        }
    }
}
