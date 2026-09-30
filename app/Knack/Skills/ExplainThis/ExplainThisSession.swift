import KnackCore
import Observation

@MainActor
@Observable
final class ExplainThisSession {
    enum Phase: Equatable { case reading, noText, explaining, done, failed(String) }

    var phase: Phase = .reading
    var response = ""
    var question = ""
    var answer = ""
    var answering = false
    var askedFollowUp = false

    let manifest: SkillManifest
    @ObservationIgnored private var text = ""
    @ObservationIgnored private let context: SkillContext
    @ObservationIgnored private var task: Task<Void, Never>?

    init(context: SkillContext) {
        self.context = context
        self.manifest = context.manifest
    }

    var sections: ExplainThis.Sections { ExplainThis.sections(response) }

    func readSelectionAndExplain() async {
        do {
            let selected = try await context.selection().read() ?? ""
            if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                phase = .noText
            } else {
                explain(selected)
            }
        } catch {
            phase = .failed(CharacterVoice.line(manifest, error))
        }
    }

    func explain(_ text: String) {
        self.text = text
        response = ""
        phase = .explaining
        task?.cancel()
        task = Task {
            do {
                for try await delta in try context.model().stream(ExplainThis.messages(text: text)) {
                    response += delta
                }
                phase = .done
            } catch {
                if Task.isCancelled { return }
                phase = .failed(CharacterVoice.line(manifest, error))
            }
        }
    }

    /// One clarifying question per explanation.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .done, !q.isEmpty, !askedFollowUp else { return }
        askedFollowUp = true
        answering = true
        task = Task {
            defer { answering = false }
            do {
                for try await delta in try context.model().stream(ExplainThis.followUp(text: text, explanation: response, question: q)) {
                    answer += delta
                }
            } catch {
                if !Task.isCancelled { answer = CharacterVoice.line(manifest, error) }
            }
        }
    }

    func close() {
        task?.cancel()
        PanelPresenter.shared.close()
    }
}
