import Foundation

/// A built-in question set. The JSON files in `Presets/` are copied verbatim from Ollaya
/// `crates/ollaya/src/presets/` at the pinned tag (the HTTP API does not serve them).
struct Preset: Identifiable, Hashable, Sendable {
    let id: String              // file name, as `ollaya run --preset` spells it
    let name: String            // shown in the Question set picker
    let hint: String            // shown as a placeholder in the empty editor
    let questions: Data         // the JSON object, sent to /api/decide byte for byte
    let questionIDs: [String]   // in file order: the order of the result rows

    static let all: [Preset] = [
        ("triage", "Support ticket", "Paste a customer support ticket…"),
        ("email", "Email", "Paste an email…"),
        ("guard", "Safety", "Paste a prompt sent to an AI assistant…"),
        ("moderation", "Moderation", "Paste a forum post or comment…"),
        ("router", "Routing", "Paste a request for a language model…"),
    ].map { Preset(id: $0.0, name: $0.1, hint: $0.2) }

    private init(id: String, name: String, hint: String) {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("\(id).json is missing from the app bundle")
        }
        self.id = id
        self.name = name
        self.hint = hint
        questions = data
        questionIDs = Self.topLevelKeys(of: data)
    }

    /// The keys of a JSON object in document order (JSONDecoder and JSONSerialization both lose it).
    static func topLevelKeys(of json: Data) -> [String] {
        OrderedJSON.members(of: json).map(\.key)
    }
}
