import KnackCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    Text(greeting)
                        .font(Theme.Fonts.greeting)
                        .kerning(-0.5)
                        .fixedSize()
                    AskBar()
                }
                if let account = model.account, account.isLow { LowCreditCard() }
                if let error = model.accountError, model.account == nil {
                    Text(error.friendlyMessage).font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
                }
                HelpersGrid()
                HStack(alignment: .top, spacing: 16) {
                    NeedsYouCard()
                    TonightCard()
                    ThisWeekCard()
                }
                SomeoneNewCard()
            }
            .padding(.horizontal, 36)
            .padding(.top, 44 + 24)
            .padding(.bottom, 24)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return model.givenName.map { "\(part), \($0)" } ?? part
    }
}

// MARK: ⌘K

/// "Ask anything": routes a sentence to the right helper with the input pre-filled. It doesn't answer freely.
struct AskBar: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var note: String?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(Theme.Colors.indigo).accessibilityHidden(true)
                TextField("Ask anything, or open a skill: \u{201C}what's for dinner?\u{201D}", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.body)
                    .focused($focused)
                    .onSubmit(submit)
                    .accessibilityLabel("Ask or open a skill")
                if working { ProgressView().controlSize(.small) }
                Button { focused = true } label: { KeyCap(text: "⌘ K") }
                    .buttonStyle(.plain)
                    .keyboardShortcut("k", modifiers: .command)
                    .accessibilityLabel("Focus the ask bar")
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 52)
            .background(Theme.Colors.surface, in: Capsule())
            .themeShadow(Theme.Shadows.askBar)
            if let note {
                Text(note).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted).padding(.leading, 18)
            }
        }
    }

    private func submit() {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !working else { return }
        working = true
        note = nil
        Task {
            defer { working = false }
            switch await model.ask(sentence) {
            case .routed(let name):
                note = "Handed to \(name)."
                text = ""
            case .noMatch:
                note = "None of your helpers do that yet. Someone new might, in Discover."
            }
        }
    }
}

// MARK: Helpers

private struct HelpersGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your helpers").font(Theme.Fonts.sectionTitle)
                Spacer()
                Button("Edit") { model.section = .settings }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.button)
                    .foregroundStyle(Theme.Colors.indigoPressed)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)], alignment: .leading, spacing: 18) {
                ForEach(model.registry.active) { manifest in
                    Button { model.open(manifest.id) } label: { HelperLauncher(manifest: manifest) }
                        .buttonStyle(.plain)
                }
                Button { model.section = .discover } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.Colors.muted)
                            .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                            .background(Theme.Colors.sidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                        Text("Meet more").font(Theme.Fonts.label)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HelperLauncher: View {
    let manifest: SkillManifest

    var body: some View {
        VStack(spacing: 8) {
            CharacterTile(manifest: manifest)
            Text(manifest.name).font(Theme.Fonts.label).multilineTextAlignment(.center).lineLimit(2)
            if let hotkey = HotkeyService.display(for: manifest.id) { KeyCap(text: hotkey) }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(manifest.name)")
    }
}

// MARK: Dashboard

private struct DashboardCard<Content: View>: View {
    let title: String
    var badge: Int? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title).font(Theme.Fonts.cardTitle)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.onAccent)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Theme.Colors.danger, in: Capsule())
                }
            }
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .card()
    }
}

/// Phase 1: nothing publishes "needs you" cards yet (Form Filler, Paperwork arrive in Phase 2).
private struct NeedsYouCard: View {
    var body: some View {
        DashboardCard(title: "Needs you") {
            Text("All clear. Nothing needs you right now.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.muted)
        }
    }
}

private struct TonightCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashboardCard(title: "Tonight") {
            if let chef = model.registry.active.first(where: { $0.id == "com.knack.fridge-chef" }) {
                let tint = Color(hexString: chef.character.tint) ?? Theme.Colors.bg
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        CharacterGlyph(manifest: chef)
                        Text("Fridge Chef says…").font(Theme.Fonts.label).foregroundStyle(Theme.Colors.muted)
                    }
                    Text("What's for dinner? Show me your fridge and I'll find three ideas.")
                        .font(Theme.Fonts.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Let's cook") { model.open(chef.id) }
                        .buttonStyle(PillButtonStyle(fill: Color(hexString: chef.character.color) ?? Theme.Colors.coral,
                                                     pressedFill: (Color(hexString: chef.character.color) ?? Theme.Colors.coral).opacity(0.85)))
                }
                .padding(14)
                .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
            } else {
                Text("Nothing planned for tonight.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted)
            }
        }
    }
}

private struct ThisWeekCard: View {
    @Environment(AppModel.self) private var model

    private struct Stat: Identifiable {
        let id: String
        let label: String
    }

    private let stats = [
        Stat(id: "com.knack.say-it-better", label: "messages polished"),
        Stat(id: "com.knack.explain-this", label: "things explained"),
        Stat(id: "com.knack.fridge-chef", label: "dinner ideas"),
    ]

    var body: some View {
        DashboardCard(title: "This week") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.weekCount(stat.id))").font(Theme.Fonts.bigNumber)
                        Text(stat.label).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct SomeoneNewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let entry = model.catalog.entries.first(where: { !$0.isComingSoon && !model.registry.isInstalled($0.id) })
            ?? model.catalog.entries.first(where: \.isComingSoon) {
            HStack(spacing: 14) {
                Image(entry.asset)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
                    .accessibilityLabel(entry.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Someone new to meet").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                    Text("\(entry.name): \(entry.blurb)").font(Theme.Fonts.bodyBold)
                }
                Spacer()
                Button("Say hi") {
                    model.detailSkillID = entry.id
                    model.section = .discover
                }
                .buttonStyle(PillButtonStyle())
            }
            .card()
        }
    }
}

private struct LowCreditCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.Colors.coral).accessibilityHidden(true)
            Text("Running low on credit. Your helpers may need a break soon.").font(Theme.Fonts.bodyBold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

enum Shortcut {
    /// `option+space` → `⌥ Space`
    static func display(_ spec: String) -> String {
        spec.split(separator: "+").map { part -> String in
            switch part.lowercased() {
            case "option", "alt": "⌥"
            case "command", "cmd": "⌘"
            case "control", "ctrl": "⌃"
            case "shift": "⇧"
            case "space": "Space"
            default: part.uppercased()
            }
        }.joined(separator: " ")
    }
}
