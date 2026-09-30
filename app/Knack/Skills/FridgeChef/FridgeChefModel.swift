import AppKit
import KnackCore
import Observation

@MainActor
@Observable
final class FridgeChefModel {
    enum Phase: Equatable { case start, looking, items, cooking, recipes, failed(String) }

    var phase: Phase = .start
    var photo: PickedImage?
    var items: [DetectedItem] = []
    var pantry: Set<String> = ["rice", "pasta", "beans"]
    var extraPantry = ""
    var filters = FridgeChef.Filters()
    var recipes: [Recipe] = []
    var cooking: Recipe?

    let manifest: SkillManifest
    @ObservationIgnored let context: SkillContext
    @ObservationIgnored private var task: Task<Void, Never>?

    init(context: SkillContext) {
        self.context = context
        self.manifest = context.manifest
    }

    var photoImage: NSImage? { photo.flatMap { NSImage(data: $0.data) } }

    var pantryList: [String] {
        let extras = extraPantry.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return pantry.sorted() + extras
    }

    // MARK: Photo in

    func choosePhoto() {
        Task {
            do {
                guard let picked = try await context.imageInput().pickImage() else { return }
                use(picked)
            } catch {
                phase = .failed(CharacterVoice.line(manifest, error))
            }
        }
    }

    /// From drag-and-drop or Continuity Camera.
    func importPhoto(_ data: Data) {
        Task {
            do {
                use(try await context.imageInput().importImage(data: data))
            } catch {
                phase = .failed(CharacterVoice.line(manifest, error))
            }
        }
    }

    private func use(_ picked: PickedImage) {
        photo = picked
        detect()
    }

    // MARK: Vision → items

    func detect() {
        guard let photo else { return }
        phase = .looking
        task?.cancel()
        task = Task {
            do {
                let found = try await context.model().decode(DetectedItems.self, FridgeChef.detectMessages(photo: photo))
                items = found.items
                phase = .items
                if !items.isEmpty { suggest() }
            } catch {
                if !Task.isCancelled { phase = .failed(CharacterVoice.line(manifest, error)) }
            }
        }
    }

    func remove(_ item: DetectedItem) {
        items.removeAll { $0 == item }
    }

    func rename(_ item: DetectedItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let i = items.firstIndex(of: item) else { return }
        if trimmed.isEmpty { items.remove(at: i) } else { items[i].name = trimmed }
    }

    func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { return }
        items.append(DetectedItem(name: trimmed))
    }

    // MARK: Text → recipes

    func suggest() {
        guard !items.isEmpty else { return }
        phase = .cooking
        task?.cancel()
        let items = self.items, pantry = pantryList, filters = self.filters
        task = Task {
            do {
                let set = try await context.model().decode(RecipeSet.self, FridgeChef.recipeMessages(items: items, pantry: pantry, filters: filters))
                recipes = set.recipes
                phase = .recipes
            } catch {
                if !Task.isCancelled { phase = .failed(CharacterVoice.line(manifest, error)) }
            }
        }
    }

    func missing(for recipe: Recipe) -> [String] {
        FridgeChef.missing(for: recipe, items: items, pantry: pantryList)
    }

    func startOver() {
        task?.cancel()
        photo = nil
        items = []
        recipes = []
        phase = .start
    }

    /// Cook-mode timers finishing while the window is in the background.
    func timerFinished(step: String) {
        NSSound.beep()
        Task { try? await context.notifications().notify(title: "Fridge Chef says…", body: "Time's up! \(step)") }
    }
}
