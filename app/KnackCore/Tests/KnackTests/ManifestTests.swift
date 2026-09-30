import Foundation
import Testing
@testable import KnackCore

@Suite("Manifest parsing")
@MainActor
struct ManifestTests {
    @Test func parsesTheSpecExample() throws {
        let json = """
        {
          "id": "com.knack.fridge-chef",
          "name": "Fridge Chef",
          "tagline": "Snap your fridge. Three dinners you can make tonight.",
          "character": { "asset": "fridge-chef", "color": "#E06A4E", "tint": "#FBE0D8" },
          "category": "home",
          "permissions": ["image.input", "model.vision", "notifications"],
          "never": ["files.read", "email.read", "network.other"],
          "triggers": [{ "type": "window" }, { "type": "route", "examples": ["what's for dinner", "what can I cook"] }],
          "model": { "tier": "vision-fast", "maxCostPerRunUSD": 0.02 },
          "version": "1.0.0"
        }
        """
        let m = try SkillManifest.load(from: Data(json.utf8))
        #expect(m.id == "com.knack.fridge-chef")
        #expect(m.permissions == [.imageInput, .modelVision, .notifications])
        #expect(m.never.map(\.rawValue) == ["files.read", "email.read", "network.other"])
        #expect(m.model == .init(tier: .visionFast, maxCostPerRunUSD: 0.02))
        #expect(m.routeExamples == ["what's for dinner", "what can I cook"])
        #expect(m.character.tint == "#FBE0D8")
    }

    @Test func everyBundledManifestLoads() throws {
        let registry = try loadRegistry()
        #expect(registry.loadErrors.isEmpty, "\(registry.loadErrors)")
        #expect(Set(registry.manifests.map(\.id)) == ["com.knack.say-it-better", "com.knack.explain-this", "com.knack.fridge-chef"])
    }

    @Test func bundledHotkeysMatchTheSpec() throws {
        let registry = try loadRegistry()
        #expect(registry.manifest(id: "com.knack.say-it-better")?.hotkey == "option+space")
        #expect(registry.manifest(id: "com.knack.explain-this")?.hotkey == "option+e")
    }

    @Test func rejectsUnknownCapabilities() {
        #expect(throws: SkillManifest.ValidationError.unknownCapability("camera.spy")) {
            try manifest(permissions: [.modelText, "camera.spy"]).validate()
        }
        #expect(throws: SkillManifest.ValidationError.unknownCapability("mystery")) {
            try manifest(never: ["mystery"]).validate()
        }
    }

    @Test func rejectsNonGrantableAndContradictoryPermissions() {
        #expect(throws: SkillManifest.ValidationError.notGrantable("files.read")) {
            try manifest(permissions: [.modelText, "files.read"]).validate()
        }
        #expect(throws: SkillManifest.ValidationError.grantedAndNever("model.text")) {
            try manifest(permissions: [.modelText], never: [.modelText]).validate()
        }
    }

    @Test func rejectsAModelTierWithoutPermission() {
        #expect(throws: SkillManifest.ValidationError.modelWithoutPermission(.visionFast)) {
            try manifest(permissions: [.modelText], tier: .visionFast).validate()
        }
        #expect(throws: SkillManifest.ValidationError.modelWithoutPermission(.textFast)) {
            try manifest(permissions: [.imageInput], tier: .textFast).validate()
        }
    }

    @Test func rejectsBadIDsAndColors() {
        #expect(throws: SkillManifest.ValidationError.badID("fridge")) {
            try SkillManifest.load(from: Data(##"{"id":"fridge","name":"F","tagline":"t","character":{"asset":"a","color":"#000000","tint":"#FFFFFF"},"category":"c","permissions":[],"never":[],"triggers":[],"version":"1"}"##.utf8))
        }
        #expect(throws: SkillManifest.ValidationError.badColor("red")) {
            try SkillManifest.load(from: Data(##"{"id":"com.a.b","name":"F","tagline":"t","character":{"asset":"a","color":"red","tint":"#FFFFFF"},"category":"c","permissions":[],"never":[],"triggers":[],"version":"1"}"##.utf8))
        }
    }

    @Test func everyCatalogEntryHasSentences() {
        for (capability, entry) in PermissionCatalog.entries {
            #expect(!entry.can.isEmpty && !entry.never.isEmpty, "\(capability.rawValue)")
        }
    }

    private func loadRegistry() throws -> SkillRegistry {
        let registry = SkillRegistry(store: InMemoryInstallStateStore())
        registry.load(from: Repo.skillsDir)
        return registry
    }
}

@Suite("Skill registry")
@MainActor
struct RegistryTests {
    @Test func firstLaunchInstallsEverythingAndRemembersChanges() {
        let store = InMemoryInstallStateStore()
        let registry = SkillRegistry(store: store)
        registry.register([manifest(id: "com.knack.a"), manifest(id: "com.knack.b")])
        #expect(registry.installedIDs == ["com.knack.a", "com.knack.b"])

        registry.uninstall("com.knack.a")
        registry.setEnabled("com.knack.b", false)
        #expect(registry.active.isEmpty)

        let reloaded = SkillRegistry(store: store)
        reloaded.register([manifest(id: "com.knack.a"), manifest(id: "com.knack.b")])
        #expect(reloaded.installedIDs == ["com.knack.b"])
        #expect(!reloaded.isEnabled("com.knack.b"))
    }
}
