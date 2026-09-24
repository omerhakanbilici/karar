import Foundation

/// A model Karar offers to download (spec §1: the registry has no list endpoint, so Karar ships
/// `Catalog.json`). `size` is the manifest total at the pinned Ollaya version, shown as "~" until
/// the download reports real sizes.
struct CatalogEntry: Decodable, Identifiable, Hashable, Sendable {
    let name: String          // as `ollaya pull` takes it
    let summary: String
    let languages: String
    let license: String
    let size: Int64
    let recommended: Bool
    let includes: [String]    // a router's targets, in route order; a pull downloads them too

    var id: String { name }

    /// The name `/api/tags` reports (docs/api.md §3): the tag is always shown.
    var canonicalName: String { name.contains(":") ? name : name + ":latest" }

    static let all: [CatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CatalogEntry].self, from: data) else {
            fatalError("Catalog.json is missing from the app bundle or invalid")
        }
        return entries
    }()

    static func named(_ name: String) -> CatalogEntry? {
        all.first { $0.name == name }
    }
}
