import Foundation

/// One simple-mode result line (spec §3.2): the question and the answer in words, and how sure
/// the model is (0…1, drawn as a bar and a percentage).
struct ResultRow: Identifiable, Equatable {
    let id: String
    let label: String
    let answer: String
    let sureness: Double

    init(id: String, answer a: Answer) {
        self.id = id
        label = Self.humanize(id)
        switch a.type {
        case "noul":
            let p = a.noul ?? 0
            answer = p >= 0.5 ? "Yes" : "No"
            sureness = max(p, 1 - p)
        case "score":
            let top = max((a.legend?.count ?? 2) - 1, 1)
            answer = String(format: "%.1f / %d", a.score ?? 0, top)
            sureness = a.confidence ?? 0
        default:   // "choice", and any type a newer Ollaya adds
            answer = Self.humanize(a.choice ?? a.type)
            sureness = a.confidence ?? 0
        }
    }

    /// `refund_requested` → "Refund requested".
    static func humanize(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
