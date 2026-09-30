import Foundation
import Testing
@testable import KnackCore

final class FakeSelection: SelectionService, @unchecked Sendable {
    var text: String? = "hello"
    var replaced: String?
    func readSelection() async throws -> String? { text }
    func replaceSelection(with text: String) async throws { replaced = text }
}

struct FakeImages: ImageInputService {
    func pickImage() async throws -> PickedImage? { PickedImage(data: Data([1, 2, 3]), mimeType: "image/jpeg") }
    func importImage(data: Data) async throws -> PickedImage { PickedImage(data: data, mimeType: "image/jpeg") }
}

@Suite("SkillContext enforces manifest permissions")
struct SkillContextTests {
    let router = ModelRouter(provider: ScriptedProvider(["ok", "ok", "ok"]), usage: UsageLog(fileURL: nil))

    func services() -> RuntimeServices {
        RuntimeServices(router: router, selection: FakeSelection(), imageInput: FakeImages())
    }

    @Test func fridgeChefCannotReadTheSelection() throws {
        let ctx = SkillContext(manifest: manifest(permissions: [.imageInput, .modelVision], tier: .visionFast), services: services())
        #expect(throws: KnackError.permissionDenied(.selectionRead)) { try ctx.selection() }
        #expect(throws: Never.self) { try ctx.imageInput() }
        #expect(throws: KnackError.permissionDenied(.notifications)) { try ctx.notifications() }
    }

    @Test func explainThisCanReadButNotReplace() async throws {
        let ctx = SkillContext(manifest: manifest(permissions: [.selectionRead, .modelText]), services: services())
        let selection = try ctx.selection()
        #expect(try await selection.read() == "hello")
        await #expect(throws: KnackError.permissionDenied(.selectionReplace)) { try await selection.replace(with: "x") }
        #expect(throws: KnackError.permissionDenied(.imageInput)) { try ctx.imageInput() }
    }

    @Test func noModelPermissionMeansNoModel() {
        let ctx = SkillContext(manifest: manifest(permissions: [.notifications], tier: nil), services: services())
        #expect(throws: KnackError.permissionDenied(.modelText)) { try ctx.model() }
    }

    @Test func textSkillsCannotUseVisionOrSendImages() async throws {
        let model = try SkillContext(manifest: manifest(permissions: [.modelText]), services: services()).model()
        await #expect(throws: KnackError.permissionDenied(.modelVision)) {
            _ = try await model.complete([.user("hi")], tier: .visionFast)
        }
        await #expect(throws: KnackError.permissionDenied(.modelVision)) {
            _ = try await model.complete([.user([.text("look"), .imageURL("data:image/png;base64,AA")])])
        }
        #expect(try await model.complete([.user("hi")]) == "ok")
    }

    @Test func requestsCarryTheSkillIdAndDefaultTier() async throws {
        let provider = ScriptedProvider(["done"])
        let router = ModelRouter(provider: provider, usage: UsageLog(fileURL: nil))
        let m = manifest(id: "com.knack.say-it-better", permissions: [.modelText], tier: .textSmart)
        let model = try SkillContext(manifest: m, services: RuntimeServices(router: router)).model()
        var text = ""
        for try await delta in try model.stream([.user("hi")]) { text += delta }
        #expect(text == "done")
        #expect(provider.requests.first?.skillId == "com.knack.say-it-better")
        #expect(provider.requests.first?.tier == .textSmart)
        #expect(provider.requests.first?.stream == true)
    }
}
