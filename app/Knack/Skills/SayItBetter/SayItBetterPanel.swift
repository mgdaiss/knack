import KnackCore
import SwiftUI

struct SayItBetterPanel: View {
    @Bindable var session: SayItBetterSession

    var body: some View {
        PanelChrome(manifest: session.manifest, onClose: session.close) {
            switch session.phase {
            case .reading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your selection…").foregroundStyle(Theme.Colors.muted)
                }
            case .noText:
                Text("Select some text in any app, then press \(HotkeyService.display(for: session.manifest.id) ?? "⌥Space").")
                    .foregroundStyle(Theme.Colors.muted)
            case .failed(let message):
                Text(message).font(Theme.Fonts.bodyBold)
                if session.tone != nil {
                    Button("Try again", action: session.tryAgain).buttonStyle(SoftPillButtonStyle())
                }
            case .pickTone, .writing, .done:
                tones
                if session.phase != .pickTone { result }
            }
            footer
        }
    }

    private var tones: some View {
        FlowLayout(spacing: 8) {
            ForEach(SayItBetter.Tone.allCases) { tone in
                Chip(title: tone.label, selected: session.tone == tone) { session.rewrite(tone) }
            }
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.output.isEmpty ? " " : session.output)
                .font(Theme.Fonts.nunito(16, .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.Colors.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if session.phase == .writing { ProgressView().controlSize(.small).padding(10) }
                }
            HStack(spacing: 8) {
                if session.canReplace {
                    Button("Replace") { Task { await session.replace() } }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button("Copy") { Task { await session.copy() } }
                        .buttonStyle(SoftPillButtonStyle())
                } else {
                    Button("Copy") { Task { await session.copy() } }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                Button("Try again", action: session.tryAgain)
                    .buttonStyle(SoftPillButtonStyle())
                Spacer()
                if session.canReplace { KeyCap(text: "↵ to replace") }
            }
            .disabled(session.phase != .done)
        }
    }

    private var footer: some View {
        Group {
            if session.learnsStyle && session.learnedCount > 0 {
                Text("Sounds like you: learned from \(session.learnedCount) messages you've sent. Only the selected text is sent to the AI.")
            } else {
                Text("Only the selected text is sent to the AI.")
            }
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Colors.muted)
    }
}
