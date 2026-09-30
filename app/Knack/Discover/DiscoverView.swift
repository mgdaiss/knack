import KnackCore
import SwiftUI

/// M0 Discover: every bundled helper with install state and what it can touch.
/// The full design (hero, "Start here", blob pills, catalog JSON) lands in M5.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Meet more")
                    .font(Theme.Fonts.greeting)
                    .kerning(-0.5)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(model.registry.manifests) { manifest in
                        DiscoverCard(manifest: manifest)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 44 + 24)
            .padding(.bottom, 24)
        }
    }
}

private struct DiscoverCard: View {
    @Environment(AppModel.self) private var model
    let manifest: SkillManifest

    var body: some View {
        let installed = model.registry.isInstalled(manifest.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CharacterTile(manifest: manifest, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.name).font(Theme.Fonts.cardTitle)
                    Text(manifest.tagline)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(manifest.permissions, id: \.self) { capability in
                    Label(PermissionCatalog.canSentence(capability), systemImage: "checkmark.circle.fill")
                        .font(Theme.Fonts.label)
                }
                ForEach(manifest.never, id: \.self) { capability in
                    Label(PermissionCatalog.neverSentence(capability), systemImage: "xmark.circle")
                        .font(Theme.Fonts.label)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            HStack {
                if let cost = manifest.model?.maxCostPerRunUSD {
                    Text("Up to \(Money.format(cost)) per use, on us")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                if installed {
                    Button("Remove") { model.registry.uninstall(manifest.id) }
                        .buttonStyle(SoftPillButtonStyle())
                } else {
                    Button("Allow & install") { model.registry.install(manifest.id) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: Theme.Radius.bigCard)
    }
}
