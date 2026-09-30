import Foundation

/// Discover's catalog (SPEC §8): a bundled JSON file in Phase 1. Not-yet-built skills are "Coming soon".
struct Catalog: Decodable {
    struct Step: Decodable, Hashable {
        let title: String
        let detail: String
    }

    struct Entry: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let blurb: String
        let asset: String
        let color: String
        let tint: String
        var howItWorks: [Step]? = nil
        var goodToKnow: [String]? = nil
        var comingSoon: Bool? = nil

        var isComingSoon: Bool { comingSoon ?? false }
    }

    struct Blob: Decodable, Hashable {
        let name: String
        let color: String
    }

    let hero: String
    let startHere: [String]
    let entries: [Entry]
    let moreToTry: [Blob]

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    static func bundled() -> Catalog {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return Catalog(hero: "", startHere: [], entries: [], moreToTry: [])
        }
        return catalog
    }
}
