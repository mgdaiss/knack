import KnackCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(Theme.Fonts.greeting)
                    .kerning(-0.5)
                AccountSection()
                UsageSection()
                HelpersSection()
                HotkeysSection()
                PrivacySection()
                #if DEBUG
                DeveloperSection()
                #endif
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 44 + 24)
            .padding(.bottom, 24)
        }
        .task { await model.refreshAccount() }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Theme.Fonts.cardTitle)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard(title: "Account & credit") {
            if let account = model.account {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Money.format(account.balanceUSD)).font(Theme.Fonts.bigNumber)
                    Text("of credit, on us").font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
                }
                Text("Knack covers the AI for now. No card, no top-ups.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
                HStack(spacing: 12) {
                    Stat(label: "This month", value: Money.format(account.month.spentUSD))
                    Stat(label: "Today", value: "\(Money.format(account.limits.dailySpentUSD)) of \(Money.format(account.limits.dailyCapUSD))")
                    Stat(label: "Runs this month", value: "\(account.month.runs)")
                }
            } else if let error = model.accountError {
                Text(error.friendlyMessage).font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
            } else {
                ProgressView().controlSize(.small)
            }
            HStack {
                Button("Refresh") { Task { await model.refreshAccount() } }
                    .buttonStyle(SoftPillButtonStyle())
                Spacer()
                Button("Sign out") { model.signOut() }
                    .buttonStyle(SoftPillButtonStyle())
            }
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
            Text(value).font(Theme.Fonts.bodyBold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct UsageSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard(title: "Usage by helper") {
            let rows = model.account?.month.bySkill ?? []
            if rows.isEmpty {
                Text("No helper has used any AI this month.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                ForEach(rows, id: \.skillId) { row in
                    HStack(spacing: 12) {
                        if let manifest = model.registry.manifest(id: row.skillId) {
                            CharacterGlyph(manifest: manifest)
                            Text(manifest.name).font(Theme.Fonts.bodyBold)
                        } else {
                            Text(row.skillId).font(Theme.Fonts.bodyBold)
                        }
                        Spacer()
                        Text("\(row.runs) runs · \(Money.format(row.spentUSD))")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

private struct HelpersSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard(title: "Helpers") {
            ForEach(model.registry.installed) { manifest in
                Toggle(isOn: Binding(
                    get: { model.registry.isEnabled(manifest.id) },
                    set: { model.registry.setEnabled(manifest.id, $0) }
                )) {
                    HStack(spacing: 12) {
                        CharacterGlyph(manifest: manifest)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manifest.name).font(Theme.Fonts.bodyBold)
                            if let hotkey = manifest.hotkey {
                                Text(Shortcut.display(hotkey)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                            }
                        }
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}

private struct HotkeysSection: View {
    @State private var accessibility = AccessibilityPermission.isGranted

    var body: some View {
        SectionCard(title: "Shortcuts") {
            HotkeyRow(title: "Say It Better", asset: "say-it-better", name: .sayItBetter)
            HotkeyRow(title: "Explain This", asset: "explain-this", name: .explainThis)
            HStack {
                Label(accessibility ? "Accessibility is on" : "Accessibility is off, so shortcuts can't see your selection",
                      systemImage: accessibility ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(Theme.Fonts.label)
                Spacer()
                if !accessibility {
                    Button("Turn on") {
                        AccessibilityPermission.requestPrompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(SoftPillButtonStyle())
                }
            }
        }
        .task {
            await AccessibilityPermission.waitUntilGranted()
            accessibility = true
        }
    }
}

private struct PrivacySection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SayItBetterSession.learnStyleKey) private var learnStyle = false
    @State private var sampleCount = 0

    var body: some View {
        SectionCard(title: "Privacy") {
            Text("Knack never stores what you write or the photos you share. Your helpers' history stays on this Mac.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.muted)
            Toggle(isOn: $learnStyle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Say It Better: sound like me").font(Theme.Fonts.bodyBold)
                    Text("Keeps up to \(StyleSampleStore.maxSamples) of your own messages on this Mac as style examples. \(sampleCount) saved.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Button("Clear style samples") {
                    Task { await model.clearStyleSamples(); sampleCount = 0 }
                }
                .buttonStyle(SoftPillButtonStyle())
                Button("Clear history") { Task { await model.clearHistory() } }
                    .buttonStyle(SoftPillButtonStyle())
            }
        }
        .task { sampleCount = await model.styleSamples.count }
    }
}

#if DEBUG
/// DEBUG only: switch to a direct OpenRouter key and smoke-test streaming through `ModelRouter`.
private struct DeveloperSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = DeveloperKeyStore.key ?? ""
    @State private var output = ""
    @State private var status = ""
    @State private var running = false

    var body: some View {
        @Bindable var model = model
        SectionCard(title: "Developer (debug builds only)") {
            Text("Cloud: \(AppConfig.cloudURL.absoluteString)")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.muted)
            Toggle("Use my OpenRouter key instead of Knack Cloud", isOn: $model.useDirectProvider)
                .toggleStyle(.switch)
            HStack {
                SecureField("sk-or-…", text: $key).textFieldStyle(.roundedBorder)
                Button("Save key") { DeveloperKeyStore.set(key) }
                    .buttonStyle(SoftPillButtonStyle())
            }
            Button(running ? "Running…" : "Test the model (Say It Better, text-fast)") { Task { await runTest() } }
                .buttonStyle(PillButtonStyle())
                .disabled(running)
            if !status.isEmpty {
                Text(status).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
            }
            if !output.isEmpty {
                Text(output)
                    .font(Theme.Fonts.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
            }
        }
    }

    private func runTest() async {
        guard let manifest = model.registry.manifest(id: "com.knack.say-it-better") else { return }
        running = true
        output = ""
        status = ""
        defer { running = false }
        let started = Date()
        var firstToken: TimeInterval?
        do {
            let stream = try model.context(for: manifest).model().stream([
                .system("Rewrite the user's text in the requested tone. Reply with only the rewrite."),
                .user("Tone: Nicer\n\nsend me the file already"),
            ])
            for try await delta in stream {
                if firstToken == nil { firstToken = Date().timeIntervalSince(started) }
                output += delta
            }
            let total = Date().timeIntervalSince(started)
            status = String(format: "First text after %.2fs, done in %.2fs.", firstToken ?? total, total)
            await model.refreshUsage()
            await model.refreshAccount()
        } catch let error as KnackError {
            status = "Say It Better says: \(error.friendlyMessage)"
        } catch {
            status = "Say It Better says: \(KnackError.server.friendlyMessage)"
        }
    }
}
#endif
