import KnackCore
import SwiftUI

/// The first-party skills this build ships, and how the app reaches them.
@MainActor
final class SkillHost {
    private let skills: [String: any Skill]

    init(styleSamples: StyleSampleStore) {
        let all: [any Skill] = [
            SayItBetterSkill(styleSamples: styleSamples),
            ExplainThisSkill(),
            FridgeChefSkill(),
        ]
        skills = Dictionary(uniqueKeysWithValues: all.map { (type(of: $0).manifest.id, $0) })
    }

    func skill(_ id: String) -> (any Skill)? { skills[id] }

    /// Skills with a `window` trigger open in their own window; the rest run in a floating panel.
    func hasWindow(_ manifest: SkillManifest) -> Bool {
        manifest.triggers.contains { $0.type == .window }
    }
}

/// Window content for `knack://open/<id>` and "Open" buttons.
struct SkillWindow: View {
    @Environment(AppModel.self) private var model
    let skillID: String

    var body: some View {
        if let manifest = model.registry.manifest(id: skillID), model.registry.isEnabled(skillID),
           let skill = model.skillHost.skill(skillID) {
            skill.makeMainView(context: model.context(for: manifest))
                .navigationTitle(manifest.name)
        } else {
            Text("That helper isn't installed.")
                .font(Theme.Fonts.bodyBold)
                .foregroundStyle(Theme.Colors.muted)
                .frame(width: 420, height: 200)
                .background(Theme.Colors.bg)
        }
    }
}
