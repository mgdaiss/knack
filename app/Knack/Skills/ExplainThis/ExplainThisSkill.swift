import KnackCore
import SwiftUI

/// ⌥E: a plain-English explanation of the selection, "What this means for you", and one follow-up (SPEC §5.2).
struct ExplainThisSkill: Skill {
    static let manifest = SkillManifest.bundled("ExplainThis")

    func handleHotkey(context: SkillContext) async {
        let session = ExplainThisSession(context: context)
        present(session)
        await session.readSelectionAndExplain()
        PanelPresenter.shared.focus()
    }

    func handleRoute(_ route: AskRoute, context: SkillContext) async {
        let session = ExplainThisSession(context: context)
        present(session)
        PanelPresenter.shared.focus()
        if route.input.isEmpty {
            session.phase = .noText
        } else {
            session.explain(route.input)
        }
    }

    private func present(_ session: ExplainThisSession) {
        PanelPresenter.shared.show(width: 520) { ExplainThisPanel(session: session) }
    }
}
