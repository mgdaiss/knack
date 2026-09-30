import Foundation
import Testing
@testable import KnackCore

@Suite("Tier mapping")
struct TierTests {
    @Test func shippedTierMapCoversEveryTier() throws {
        let map = try TierMap.load(from: Data(contentsOf: Repo.modelTiers))
        for tier in ModelTier.allCases {
            let entry = try map.entry(for: tier)
            #expect(entry.model.contains("/"), "OpenRouter IDs are vendor/model")
            #expect(entry.maxTokens > 0)
        }
    }

    @Test func appAndCloudTierMapsAgree() throws {
        let app = try TierMap.load(from: Data(contentsOf: Repo.modelTiers))
        let cloudURL = Repo.appDir.deletingLastPathComponent().appendingPathComponent("cloud/config/tiers.json")
        let cloud = try JSONSerialization.jsonObject(with: Data(contentsOf: cloudURL)) as! [String: [String: Any]]
        for tier in ModelTier.allCases {
            let model = try app.entry(for: tier).model
            #expect(cloud[tier.rawValue]?["model"] as? String == model, "\(tier)")
        }
    }

    @Test func missingTierIsAnError() {
        let map = TierMap(entries: [.textFast: .init(model: "a/b", maxTokens: 10)])
        #expect(throws: TierMap.MapError.missingTier(.visionFast)) { try map.entry(for: .visionFast) }
        #expect(throws: TierMap.MapError.missingTier(.textSmart)) {
            try TierMap.load(from: Data(#"{"text-fast":{"model":"a/b","maxTokens":1}}"#.utf8))
        }
    }

    @Test func tierPermissions() {
        #expect(ModelTier.textFast.isPermitted(by: [.modelText]))
        #expect(ModelTier.textFast.isPermitted(by: [.modelVision]))
        #expect(!ModelTier.visionFast.isPermitted(by: [.modelText]))
        #expect(ModelTier.visionFast.isPermitted(by: [.modelVision]))
        #expect(!ModelTier.textSmart.isPermitted(by: [.selectionRead]))
    }
}
