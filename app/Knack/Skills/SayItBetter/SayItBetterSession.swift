import AppKit
import KnackCore
import Observation

@MainActor
@Observable
final class SayItBetterSession {
    enum Phase: Equatable {
        case reading, noText, pickTone, writing, done, failed(String)
    }

    var phase: Phase = .reading
    var original = ""
    var tone: SayItBetter.Tone?
    var output = ""
    let canReplace: Bool
    private(set) var learnedCount = 0

    static let learnStyleKey = "sayItBetter.learnStyle"
    var learnsStyle: Bool { UserDefaults.standard.bool(forKey: Self.learnStyleKey) }

    let manifest: SkillManifest
    @ObservationIgnored private let context: SkillContext
    @ObservationIgnored private let styleSamples: StyleSampleStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(context: SkillContext, styleSamples: StyleSampleStore, canReplace: Bool) {
        self.context = context
        self.manifest = context.manifest
        self.styleSamples = styleSamples
        self.canReplace = canReplace
        Task { learnedCount = await styleSamples.count }
    }

    func readSelection() async {
        do {
            let text = try await context.selection().read() ?? ""
            original = text
            phase = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .noText : .pickTone
        } catch {
            phase = .failed(CharacterVoice.line(manifest, error))
        }
    }

    func rewrite(_ tone: SayItBetter.Tone) {
        self.tone = tone
        output = ""
        phase = .writing
        task?.cancel()
        task = Task {
            do {
                let samples = learnsStyle ? await styleSamples.recent() : []
                let stream = try context.model().stream(SayItBetter.messages(text: original, tone: tone, styleSamples: samples))
                var raw = ""
                for try await delta in stream {
                    raw += delta
                    output = raw
                }
                output = SayItBetter.clean(raw)
                phase = .done
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                phase = .failed(CharacterVoice.line(manifest, error))
            }
        }
    }

    func tryAgain() {
        if let tone { rewrite(tone) }
    }

    func replace() async {
        guard phase == .done, canReplace else { return }
        PanelPresenter.shared.hide()
        do {
            try await context.selection().replace(with: output)
            await remember()
            PanelPresenter.shared.close()
        } catch {
            phase = .failed(CharacterVoice.line(manifest, error))
            PanelPresenter.shared.show(width: 520) { SayItBetterPanel(session: self) }
            PanelPresenter.shared.focus()
        }
    }

    func copy() async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        await remember()
        PanelPresenter.shared.close()
    }

    func close() {
        task?.cancel()
        PanelPresenter.shared.close()
    }

    /// Opt-in: keep the user's own original as a style sample (on this Mac only).
    private func remember() async {
        guard learnsStyle, tone != .typos else { return }
        await styleSamples.add(original)
    }
}
