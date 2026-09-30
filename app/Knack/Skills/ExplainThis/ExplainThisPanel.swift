import KnackCore
import SwiftUI

struct ExplainThisPanel: View {
    @Bindable var session: ExplainThisSession

    var body: some View {
        PanelChrome(manifest: session.manifest, onClose: session.close) {
            switch session.phase {
            case .reading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your selection…").foregroundStyle(Theme.Colors.muted)
                }
            case .noText:
                Text("Select something confusing in any app, then press \(HotkeyService.display(for: session.manifest.id) ?? "⌥E").")
                    .foregroundStyle(Theme.Colors.muted)
            case .failed(let message):
                Text(message).font(Theme.Fonts.bodyBold)
            case .explaining, .done:
                explanation
            }
        }
    }

    private var explanation: some View {
        let sections = session.sections
        let tint = Color(hexString: session.manifest.character.tint) ?? Theme.Colors.bg
        return VStack(alignment: .leading, spacing: 14) {
            Text(sections.explanation.isEmpty ? " " : sections.explanation)
                .font(Theme.Fonts.nunito(16, .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let meaning = sections.meaning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What this means for you").font(Theme.Fonts.bodyBold)
                    Text(LocalizedStringKey(meaning)).font(Theme.Fonts.body).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
            }
            if session.phase == .explaining {
                ProgressView().controlSize(.small)
            } else {
                followUp
            }
            Text("Only the selected text is sent to the AI.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    @ViewBuilder
    private var followUp: some View {
        if session.askedFollowUp {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.question).font(Theme.Fonts.bodyBold)
                Text(session.answer.isEmpty ? " " : session.answer).textSelection(.enabled)
                if session.answering { ProgressView().controlSize(.small) }
            }
        } else {
            HStack(spacing: 8) {
                TextField("Still unsure? Ask one follow-up question", text: $session.question)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Theme.Colors.bg, in: Capsule())
                    .onSubmit(session.ask)
                Button("Ask", action: session.ask)
                    .buttonStyle(PillButtonStyle())
                    .disabled(session.question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
