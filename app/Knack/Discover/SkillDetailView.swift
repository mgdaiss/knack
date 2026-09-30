import KnackCore
import SwiftUI

/// Skill detail / install (SPEC §8.3, design/Skill-Detail.dc.html restyled to direction E):
/// tagline, how it works, what it can and will never touch, AI cost, then "Allow & install".
struct SkillDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: Catalog.Entry

    private var manifest: SkillManifest? { model.registry.manifest(id: entry.id) }

    var body: some View {
        let tint = Color(hexString: entry.tint) ?? Theme.Colors.bg
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 18) {
                    Image(entry.asset).resizable().frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .themeShadow(Theme.Shadows.tile)
                        .accessibilityLabel(entry.name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.name).font(Theme.Fonts.greeting)
                        Text(entry.blurb).font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
                        Text("By Knack · Runs on your Mac").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                    }
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(SoftPillButtonStyle()).keyboardShortcut(.cancelAction)
                }

                if let steps = entry.howItWorks, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it works").font(Theme.Fonts.sectionTitle)
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(Theme.Fonts.bodyBold)
                                    .frame(width: 30, height: 30)
                                    .background(tint, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title).font(Theme.Fonts.bodyBold)
                                    Text(step.detail).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted)
                                }
                            }
                        }
                    }
                }

                if let notes = entry.goodToKnow, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Good to know").font(Theme.Fonts.cardTitle)
                        ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(Theme.Fonts.body) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                if let manifest {
                    permissionCard(manifest)
                } else {
                    Text("\(entry.name) is coming soon. We'll let you know when it's ready to meet.")
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            .padding(32)
        }
        .frame(width: 640, height: 720)
        .background(Theme.Colors.bg)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Colors.ink)
    }

    private func permissionCard(_ manifest: SkillManifest) -> some View {
        let installed = model.registry.isInstalled(manifest.id)
        return VStack(alignment: .leading, spacing: 14) {
            Text(installed ? "What it can do" : "Before you install").font(Theme.Fonts.cardTitle)
            Text("This helper will be able to:").font(Theme.Fonts.bodyBold)
            ForEach(manifest.permissions, id: \.self) { c in
                Label(PermissionCatalog.canSentence(c), systemImage: "checkmark.circle.fill").font(Theme.Fonts.body)
            }
            Text("It will never:").font(Theme.Fonts.bodyBold).padding(.top, 4)
            ForEach(manifest.never, id: \.self) { c in
                Label(PermissionCatalog.neverSentence(c), systemImage: "xmark.circle").font(Theme.Fonts.body)
            }
            if let cost = manifest.model?.maxCostPerRunUSD {
                Text("AI cost: at most \(Money.format(cost)) per use, from your Knack credit (on us for now). Runs on a fast, low-cost model.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .padding(.top, 4)
            }
            HStack {
                Spacer()
                if installed {
                    Button("Remove") { model.registry.uninstall(manifest.id) }.buttonStyle(SoftPillButtonStyle())
                    Button("Open") { dismiss(); model.open(manifest.id) }.buttonStyle(PillButtonStyle())
                } else {
                    Button("Allow & install") { model.registry.install(manifest.id); model.registry.setEnabled(manifest.id, true) }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
