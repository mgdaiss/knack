import KnackCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let account = model.account, account.isLow {
                    LowCreditCard()
                }
                if let error = model.accountError, model.account == nil {
                    Text(error.friendlyMessage)
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.muted)
                }
                helpers
                ThisWeekCard()
            }
            .padding(.horizontal, 36)
            .padding(.top, 44 + 24)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        HStack(spacing: 20) {
            Text(greeting)
                .font(Theme.Fonts.greeting)
                .kerning(-0.5)
                .fixedSize()
            AskBar()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let name = model.givenName { return "\(part), \(name)" }
        return part
    }

    private var helpers: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your helpers").font(Theme.Fonts.sectionTitle)
                Spacer()
                Button("Meet more") { model.section = .discover }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.button)
                    .foregroundStyle(Theme.Colors.indigoPressed)
            }
            if model.registry.active.isEmpty {
                Text("No helpers yet. Someone new to meet is waiting in Discover.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 8)], alignment: .leading, spacing: 18) {
                    ForEach(model.registry.active) { manifest in
                        HelperLauncher(manifest: manifest)
                    }
                }
            }
        }
    }
}

/// ⌘K bar. Routing to skills arrives with M5; for now it's the visual placeholder from the design.
private struct AskBar: View {
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .foregroundStyle(Theme.Colors.indigo)
                .accessibilityHidden(true)
            TextField("Ask anything, or open a skill: \u{201C}what's for dinner?\u{201D}", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .disabled(true)
                .accessibilityLabel("Ask or open a skill")
            KeyCap(text: "⌘ K")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(Theme.Colors.surface, in: Capsule())
        .themeShadow(Theme.Shadows.askBar)
        .help("Routing to your helpers is coming soon.")
    }
}

private struct HelperLauncher: View {
    let manifest: SkillManifest

    var body: some View {
        VStack(spacing: 8) {
            CharacterTile(manifest: manifest)
            Text(manifest.name)
                .font(Theme.Fonts.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let hotkey = manifest.hotkey {
                KeyCap(text: Shortcut.display(hotkey))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ThisWeekCard: View {
    @Environment(AppModel.self) private var model

    private struct Row: Identifiable {
        let manifest: SkillManifest
        let count: Int
        var id: String { manifest.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(Theme.Fonts.cardTitle)
            let rows = model.registry.installed.compactMap { m in model.weekCounts[m.id].map { Row(manifest: m, count: $0) } }
            if rows.isEmpty {
                Text("Nothing yet. Your helpers are ready when you are.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        CharacterGlyph(manifest: row.manifest)
                        Text(row.manifest.name).font(Theme.Fonts.bodyBold)
                        Spacer()
                        Text(row.count == 1 ? "1 time" : "\(row.count) times")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct LowCreditCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.Colors.coral)
                .accessibilityHidden(true)
            Text("Running low on credit. Your helpers may need a break soon.")
                .font(Theme.Fonts.bodyBold)
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
