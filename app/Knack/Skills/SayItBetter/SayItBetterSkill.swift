import KnackCore
import SwiftUI

/// ⌥Space: rewrite the selected text in a tone, then Replace, Copy or Try again (SPEC §5.1).
struct SayItBetterSkill: Skill {
    static let manifest = SkillManifest.bundled("SayItBetter")

    let styleSamples: StyleSampleStore

    func handleHotkey(context: SkillContext) async {
        let session = SayItBetterSession(context: context, styleSamples: styleSamples, canReplace: true)
        present(session)
        await session.readSelection()
        PanelPresenter.shared.focus()
    }

    func handleRoute(_ route: AskRoute, context: SkillContext) async {
        // From ⌘K there's no selection to replace, so the result is copied instead.
        let session = SayItBetterSession(context: context, styleSamples: styleSamples, canReplace: false)
        session.original = route.input
        session.phase = route.input.isEmpty ? .noText : .pickTone
        present(session)
        PanelPresenter.shared.focus()
        if let tone = route.tone, !route.input.isEmpty { session.rewrite(tone) }
    }

    private func present(_ session: SayItBetterSession) {
        PanelPresenter.shared.show(width: 520) {
            SayItBetterPanel(session: session)
        }
    }
}
