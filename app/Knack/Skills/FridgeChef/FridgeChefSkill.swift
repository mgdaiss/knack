import KnackCore
import SwiftUI

/// Photo in, three dinner ideas out, then step-by-step cook mode (SPEC §5.3).
struct FridgeChefSkill: Skill {
    static let manifest = SkillManifest.bundled("FridgeChef")

    func makeMainView(context: SkillContext) -> AnyView {
        AnyView(FridgeChefView(model: FridgeChefModel(context: context)))
    }
}
