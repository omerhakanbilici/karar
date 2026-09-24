import Foundation

/// One question as an advanced-mode card edits it (spec §3.2; schema in docs/api.md §5.2). Read
/// from a question set's JSON and written back in the same order.
struct Question: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case choice, score, noul
    }

    /// A row under the question. choice: a label and its description; score: a level's
    /// description in `text`, level 0 first; noul: always two, `true` and `false`.
    struct Option: Identifiable, Hashable, Sendable {
        var id = UUID()
        var label = ""
        var text = ""
    }

    var id = UUID()              // the card's identity; survives edits of `key`
    var key: String              // the question id in the request, e.g. `is_urgent`
    var kind: Kind
    var instructions = ""
    var options: [Option]

    init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
        options = Self.template(kind)
    }

    static func template(_ kind: Kind) -> [Option] {
        switch kind {
        case .choice: [Option(label: "option_1"), Option(label: "option_2")]
        case .score: [Option(text: "low"), Option(text: "medium"), Option(text: "high")]
        case .noul: [Option(label: "true"), Option(label: "false")]
        }
    }

    /// A new type starts from that type's template.
    mutating func change(to kind: Kind) {
        guard kind != self.kind else { return }
        self.kind = kind
        options = Self.template(kind)
    }

    /// The questions of a question-set JSON object, in document order. Descriptions that are
    /// `null` become "". ponytail: a description that is a JSON object or array also becomes ""
    /// (no bundled preset has one, and the cards only edit text); keep its JSON text if that changes.
    static func parse(_ json: Data) -> [Question] {
        OrderedJSON.members(of: json).compactMap { key, value in
            let field = fields(of: value)
            guard let kind = field["type"].flatMap(string).flatMap(Kind.init(rawValue:)) else { return nil }
            var question = Question(key: key, kind: kind)
            question.instructions = field["instructions"].flatMap(string) ?? ""
            guard let criteria = field["criteria"] else { return question }
            let isArray = criteria.first { !(" \n\r\t".utf8.contains($0)) } == UInt8(ascii: "[")
            switch kind {
            case .choice where isArray:
                question.options = ((try? JSONDecoder().decode([String].self, from: criteria)) ?? []).map { Option(label: $0) }
            case .choice:
                question.options = OrderedJSON.members(of: criteria).map { Option(label: $0.key, text: string($0.value) ?? "") }
            case .score:
                question.options = ((try? JSONDecoder().decode([String?].self, from: criteria)) ?? []).map { Option(text: $0 ?? "") }
            case .noul:
                let texts = fields(of: criteria)
                question.options = [Option(label: "true", text: texts["true"].flatMap(string) ?? ""),
                                    Option(label: "false", text: texts["false"].flatMap(string) ?? "")]
            }
            return question
        }
    }

    /// The request's `questions` object, in card order. Empty instructions are left out (the model
    /// then reads the id, docs/api.md §5.2); an empty choice description is `null`, an empty noul
    /// description is left out.
    static func json(_ questions: [Question]) -> Data {
        object(questions.map { ($0.key, $0.json) })
    }

    /// Ids used by more than one question: such a set cannot be sent as a JSON object.
    static func duplicateKeys(_ questions: [Question]) -> Set<String> {
        Set(Dictionary(grouping: questions, by: \.key).filter { $0.value.count > 1 }.keys)
    }

    private var json: Data {
        var fields = [("type", Self.encode(kind.rawValue))]
        if !instructions.isEmpty { fields.append(("instructions", Self.encode(instructions))) }
        switch kind {
        case .choice:
            fields.append(("criteria", Self.object(options.map { ($0.label, $0.text.isEmpty ? Data("null".utf8) : Self.encode($0.text)) })))
        case .score:
            fields.append(("criteria", Data("[".utf8) + Data(options.map { Self.encode($0.text) }.joined(separator: Data(",".utf8))) + Data("]".utf8)))
        case .noul:
            let described = options.filter { !$0.text.isEmpty }
            if !described.isEmpty {
                fields.append(("criteria", Self.object(described.map { ($0.label, Self.encode($0.text)) })))
            }
        }
        return Self.object(fields)
    }

    private static func object(_ members: [(String, Data)]) -> Data {
        Data("{".utf8) + Data(members.map { encode($0.0) + Data(":".utf8) + $0.1 }.joined(separator: Data(",".utf8))) + Data("}".utf8)
    }

    private static func encode(_ string: String) -> Data {
        (try? JSONEncoder().encode(string)) ?? Data(#""""#.utf8)
    }

    private static func string(_ json: Data) -> String? {
        try? JSONDecoder().decode(String.self, from: json)
    }

    private static func fields(of json: Data) -> [String: Data] {
        Dictionary(OrderedJSON.members(of: json).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Answer {
    /// The value as the engine returned it, for the advanced cards (spec §3.2: raw value and
    /// confidence). noul has no confidence (docs/api.md §5.4).
    var rawText: String {
        switch type {
        case "noul": String(format: "%.2f", noul ?? 0)
        case "score": String(format: "%.2f · confidence %.2f", score ?? 0, confidence ?? 0)
        default: "\(choice ?? type) · " + String(format: "confidence %.2f", confidence ?? 0)
        }
    }
}
