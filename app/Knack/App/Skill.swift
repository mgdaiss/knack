import KnackCore
import SwiftUI

/// A first-party skill (SPEC §3.3). Skills reach services only through `SkillContext`.
@MainActor
protocol Skill {
    /// Mirrors the skill's bundled `skill.json`.
    static var manifest: SkillManifest { get }
    /// The applet window, for skills with a `window` trigger.
    func makeMainView(context: SkillContext) -> AnyView
    /// For hotkey skills.
    func handleHotkey(context: SkillContext) async
    /// From the ⌘K bar, with the input pre-filled.
    func handleRoute(_ route: AskRoute, context: SkillContext) async
}

extension Skill {
    var id: String { Self.manifest.id }
    func makeMainView(context: SkillContext) -> AnyView { AnyView(EmptyView()) }
    func handleHotkey(context: SkillContext) async {}
    func handleRoute(_ route: AskRoute, context: SkillContext) async {}
}

extension SkillManifest {
    /// Loads a bundled manifest by folder name, e.g. `bundled("FridgeChef")`.
    static func bundled(_ folder: String) -> SkillManifest {
        guard let url = Bundle.main.url(forResource: "skill", withExtension: "json", subdirectory: "Skills/\(folder)"),
              let data = try? Data(contentsOf: url),
              let manifest = try? SkillManifest.load(from: data) else {
            fatalError("Missing or invalid bundled manifest for \(folder)")
        }
        return manifest
    }
}
