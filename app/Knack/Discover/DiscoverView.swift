import KnackCore
import SwiftUI

/// Discover (SPEC §8, design/Main.dc.html): hero, "Start here", "More to try" blob pills.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Text("Meet your new helpers").font(Theme.Fonts.greeting).kerning(-0.5).fixedSize()
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.muted).accessibilityHidden(true)
                        TextField("Search helpers", text: $search).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Theme.Colors.surface, in: Capsule())
                    .themeShadow(Theme.Shadows.askBar)
                }
                if search.isEmpty {
                    if let hero = model.catalog.entry(model.catalog.hero) { HeroCard(entry: hero) }
                    startHere
                    moreToTry
                } else {
                    results
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 44 + 24)
            .padding(.bottom, 24)
        }
        .sheet(item: Binding(
            get: { model.detailSkillID.flatMap { model.catalog.entry($0) } },
            set: { model.detailSkillID = $0?.id }
        )) { entry in
            SkillDetailView(entry: entry).environment(model)
        }
    }

    private var startHere: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start here").font(Theme.Fonts.sectionTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(model.catalog.startHere.compactMap { model.catalog.entry($0) }) { entry in
                    EntryCard(entry: entry)
                }
            }
        }
    }

    private var moreToTry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("More to try").font(Theme.Fonts.sectionTitle)
            FlowLayout(spacing: 10) {
                ForEach(model.catalog.moreToTry, id: \.self) { blob in
                    HStack(spacing: 8) {
                        BlobBuddy(color: Color(hexString: blob.color) ?? Theme.Colors.sidebar, size: 28, label: blob.name)
                        Text(blob.name).font(Theme.Fonts.label)
                        Text("Soon").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
                    .frame(minHeight: 40)
                    .background(Theme.Colors.surface, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(blob.name), coming soon")
                }
            }
        }
    }

    private var results: some View {
        let q = search.lowercased()
        let matches = model.catalog.entries.filter { $0.name.lowercased().contains(q) || $0.blurb.lowercased().contains(q) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            ForEach(matches) { EntryCard(entry: $0) }
        }
    }
}

private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    let entry: Catalog.Entry

    var body: some View {
        let tint = Color(hexString: entry.tint) ?? Theme.Colors.surface
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("WORKS IN EVERY APP").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                HStack(spacing: 14) {
                    Image(entry.asset).resizable().frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                        .themeShadow(Theme.Shadows.tile)
                        .accessibilityLabel(entry.name)
                    Text(entry.name).font(Theme.Fonts.greeting)
                }
                Text(entry.blurb).font(Theme.Fonts.bodyBold).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    GetButton(entry: entry)
                    Button("See it work") { model.detailSkillID = entry.id }.buttonStyle(SoftPillButtonStyle())
                }
            }
            Spacer()
            // A static before/after, like the mockup.
            VStack(alignment: .leading, spacing: 10) {
                Text("still waiting on that invoice?? can you just send it today")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
                HStack(spacing: 6) {
                    Chip(title: "Firmer, still friendly", selected: true) {}
                    Chip(title: "Nicer", selected: false) {}
                }
                .allowsHitTesting(false)
                Text("Hi Dana! Could you send last month's invoice over today? Thanks!")
                    .font(Theme.Fonts.bodyBold)
            }
            .frame(width: 320, alignment: .leading)
            .card(radius: Theme.Radius.card)
        }
        .padding(28)
        .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }
}

private struct EntryCard: View {
    @Environment(AppModel.self) private var model
    let entry: Catalog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(entry.asset).resizable().frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile * 64 / Theme.Size.tile, style: .continuous))
                .themeShadow(Theme.Shadows.tile)
                .accessibilityLabel(entry.name)
            Text(entry.name).font(Theme.Fonts.cardTitle)
            Text(entry.blurb).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            GetButton(entry: entry)
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .card(radius: Theme.Radius.bigCard)
        .contentShape(Rectangle())
        .onTapGesture { model.detailSkillID = entry.id }
    }
}

/// "Get" → the install screen; "Open" once installed; "Coming soon" for skills not built yet.
struct GetButton: View {
    @Environment(AppModel.self) private var model
    let entry: Catalog.Entry

    var body: some View {
        if entry.isComingSoon || model.registry.manifest(id: entry.id) == nil {
            Text("Coming soon")
                .font(Theme.Fonts.button)
                .foregroundStyle(Theme.Colors.muted)
                .padding(.horizontal, 18)
                .frame(minHeight: Theme.Size.buttonHeight)
                .background(Theme.Colors.sidebar, in: Capsule())
        } else if model.registry.isInstalled(entry.id) {
            Button("Open") { model.open(entry.id) }.buttonStyle(SoftPillButtonStyle())
        } else {
            Button("Get") { model.detailSkillID = entry.id }.buttonStyle(PillButtonStyle())
        }
    }
}
