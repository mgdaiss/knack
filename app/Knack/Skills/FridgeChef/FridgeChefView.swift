import KnackCore
import SwiftUI
import UniformTypeIdentifiers

struct FridgeChefView: View {
    @Bindable var model: FridgeChefModel
    @State private var dropTargeted = false
    @State private var newItem = ""

    private var tint: Color { Color(hexString: model.manifest.character.tint) ?? Theme.Colors.bg }
    private var accent: Color { Color(hexString: model.manifest.character.color) ?? Theme.Colors.coral }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            fridgeColumn.frame(width: 340)
            recipesColumn
        }
        .padding(28)
        .frame(minWidth: 980, minHeight: 680, alignment: .topLeading)
        .background(Theme.Colors.bg.ignoresSafeArea())
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Colors.ink)
        .tint(accent)
        .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .importsItemProviders([.image]) { providers in handleDrop(providers) }
        .sheet(item: $model.cooking) { recipe in
            CookModeView(recipe: recipe, accent: accent, onTimerDone: model.timerFinished) { model.cooking = nil }
        }
        .navigationTitle("Fridge Chef")
    }

    // MARK: Left: photo + items

    private var fridgeColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CharacterTile(manifest: model.manifest, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fridge Chef").font(Theme.Fonts.sectionTitle)
                    Text(model.manifest.tagline).font(Theme.Fonts.label).foregroundStyle(Theme.Colors.muted)
                }
            }
            photoCard
            if !model.items.isEmpty || model.phase == .items || model.phase == .recipes || model.phase == .cooking {
                itemsCard
            }
            pantryCard
        }
    }

    private var photoCard: some View {
        VStack(spacing: 12) {
            if let image = model.photoImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous))
                    .accessibilityLabel("Your fridge photo")
                HStack {
                    Button("New photo", action: model.choosePhoto).buttonStyle(SoftPillButtonStyle())
                    Button("Start over", action: model.startOver).buttonStyle(SoftPillButtonStyle())
                }
            } else {
                Image(systemName: "camera")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Drop a photo of your fridge here").font(Theme.Fonts.bodyBold)
                Button("Choose a photo", action: model.choosePhoto).buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
                Text("Or take one with your iPhone: File ▸ Import from iPhone")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(dropTargeted ? tint : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .themeShadow(Theme.Shadows.card)
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.phase == .looking {
                HStack { ProgressView().controlSize(.small); Text("Having a look…") }
            } else {
                Text("Found \(model.items.count) things.").font(Theme.Fonts.bodyBold)
                Text("Tap one to fix a mistake.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
                FlowLayout(spacing: 8) {
                    ForEach(model.items, id: \.self) { item in
                        ItemChip(item: item, tint: tint,
                                 onRename: { model.rename(item, to: $0) },
                                 onRemove: { model.remove(item) })
                    }
                }
                HStack {
                    TextField("+ Add what's missing", text: $newItem)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Theme.Colors.bg, in: Capsule())
                        .onSubmit { model.add(newItem); newItem = "" }
                    Button("Ideas", action: model.suggest).buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
                        .disabled(model.items.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var pantryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pantry").font(Theme.Fonts.bodyBold)
            FlowLayout(spacing: 6) {
                ForEach(FridgeChef.pantryStaples, id: \.self) { staple in
                    Chip(title: staple, selected: model.pantry.contains(staple), tint: accent) {
                        if model.pantry.contains(staple) { model.pantry.remove(staple) } else { model.pantry.insert(staple) }
                    }
                }
            }
            TextField("Anything else? (comma separated)", text: $model.extraPantry)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.Colors.bg, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Right: filters + recipes

    private var recipesColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Three dinners you can make tonight").font(Theme.Fonts.greeting).kerning(-0.5)
            filterBar
            switch model.phase {
            case .start:
                emptyState("Show me your fridge and I'll find three dinners you can make tonight.")
            case .looking, .items:
                emptyState(model.items.isEmpty && model.phase == .items
                           ? "I couldn't spot any food. Try another photo, or add items by hand."
                           : "Checking what you've got…")
            case .cooking:
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Thinking up dinners…").font(Theme.Fonts.bodyBold) }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fridge Chef says: \(message)").font(Theme.Fonts.bodyBold)
                    Button("Try again") { model.items.isEmpty ? model.detect() : model.suggest() }
                        .buttonStyle(SoftPillButtonStyle())
                }
            case .recipes:
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(model.recipes) { recipe in
                            RecipeCard(recipe: recipe, missing: model.missing(for: recipe), tint: tint, accent: accent) {
                                model.cooking = recipe
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Chip(title: "Under 30 min", selected: model.filters.under30, tint: accent) { model.filters.under30.toggle(); refilter() }
            Chip(title: "Kid friendly", selected: model.filters.kidFriendly, tint: accent) { model.filters.kidFriendly.toggle(); refilter() }
            Chip(title: "Vegetarian", selected: model.filters.vegetarian, tint: accent) { model.filters.vegetarian.toggle(); refilter() }
            Chip(title: "Use it up first", selected: model.filters.useItUpFirst, tint: accent) { model.filters.useItUpFirst.toggle(); refilter() }
            Stepper(value: $model.filters.serves, in: 1...12) {
                Text("Serves \(model.filters.serves)").font(Theme.Fonts.label)
            }
            .onChange(of: model.filters.serves) { refilter() }
        }
    }

    private func refilter() {
        if model.phase == .recipes || model.phase == .items { model.suggest() }
    }

    private func emptyState(_ text: String) -> some View {
        HStack(spacing: 14) {
            CharacterGlyph(manifest: model.manifest, size: 48)
            Text(text).font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.bigCard, style: .continuous))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage, let tiff = image.tiffRepresentation else { return }
            Task { @MainActor in model.importPhoto(tiff) }
        }
        return true
    }
}

private struct ItemChip: View {
    let item: DetectedItem
    let tint: Color
    let onRename: (String) -> Void
    let onRemove: () -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Button {
            draft = item.name
            editing = true
        } label: {
            HStack(spacing: 4) {
                Text(item.quantity.map { "\(item.name) × \($0)" } ?? item.name)
                if item.useSoon == true { Image(systemName: "clock").accessibilityLabel("use soon") }
            }
            .font(Theme.Fonts.label)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $draft).onSubmit { onRename(draft); editing = false }
                HStack {
                    Button("Save") { onRename(draft); editing = false }.keyboardShortcut(.defaultAction)
                    Button("Remove", role: .destructive) { onRemove(); editing = false }
                }
            }
            .padding(14)
            .frame(width: 220)
        }
    }
}

private struct RecipeCard: View {
    let recipe: Recipe
    let missing: [String]
    let tint: Color
    let accent: Color
    let onCook: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Dish photos are Phase 2: a character-illustrated placeholder for now.
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.stat, style: .continuous).fill(tint)
                Image("fridge-chef-glyph").resizable().frame(width: 56, height: 56).accessibilityHidden(true)
            }
            .frame(width: 120, height: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(Theme.Fonts.cardTitle)
                Text("\(recipe.minutes) min · uses \(recipe.usesUp.count) things you have")
                    .font(Theme.Fonts.label).foregroundStyle(Theme.Colors.muted)
                Text(recipe.summary).font(Theme.Fonts.body)
                Text(missing.isEmpty ? "Nothing to buy" : "Missing: \(missing.joined(separator: ", "))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(missing.isEmpty ? accent : Theme.Colors.muted)
            }
            Spacer()
            Button("Cook this", action: onCook).buttonStyle(PillButtonStyle(fill: accent, pressedFill: accent.opacity(0.85)))
        }
        .card(radius: Theme.Radius.bigCard)
    }
}
