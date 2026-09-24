import Foundation

/// A built-in question set. The JSON files in `Presets/` are copied verbatim from Ollaya
/// `crates/ollaya/src/presets/` at the pinned tag (the HTTP API does not serve them).
struct Preset: Identifiable, Hashable, Sendable {
    let id: String              // file name, as `ollaya run --preset` spells it
    let name: String            // shown in the Question set picker
    let questions: Data         // the JSON object, sent to /api/decide byte for byte
    let questionIDs: [String]   // in file order: the order of the result rows

    static let all: [Preset] = [
        ("triage", "Support ticket"), ("email", "Email"), ("guard", "Safety"),
        ("moderation", "Moderation"), ("router", "Routing"),
    ].map { Preset(id: $0.0, name: $0.1) }

    private init(id: String, name: String) {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("\(id).json is missing from the app bundle")
        }
        self.id = id
        self.name = name
        questions = data
        questionIDs = Self.topLevelKeys(of: data)
    }

    /// The keys of a JSON object in document order. JSONDecoder and JSONSerialization both
    /// lose key order. Assumes valid JSON.
    static func topLevelKeys(of json: Data) -> [String] {
        let bytes = [UInt8](json)
        var keys: [String] = []
        var depth = 0
        var pending: Range<Int>?   // a string at depth 1; a key if a ':' follows
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                let start = i
                i += 1
                while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
                    i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
                }
                pending = depth == 1 ? start..<min(i + 1, bytes.count) : nil
            case UInt8(ascii: ":"):
                if let range = pending,
                   let key = try? JSONDecoder().decode(String.self, from: Data(bytes[range])) {
                    keys.append(key)
                }
                pending = nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                pending = nil
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                pending = nil
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                break
            default:
                pending = nil
            }
            i += 1
        }
        return keys
    }
}
