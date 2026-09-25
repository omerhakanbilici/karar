import Foundation

// Wire types from Ollaya docs/api.md (pinned tag). Only the fields Karar reads.

struct VersionResponse: Decodable, Sendable {
    let version: String
}

struct TagsResponse: Decodable, Sendable {
    let models: [ModelInfo]
}

struct ModelInfo: Decodable, Hashable, Sendable {
    let name: String
    let size: Int64
    let details: Details

    struct Details: Decodable, Hashable, Sendable {
        let format: String
        let family: String
        let parameterSize: String
    }
}

struct OllayaError: Error, Decodable, Sendable, LocalizedError {
    let error: String
    let code: String?
    var detail: [Issue]? = nil   // validation issues (docs/api.md §4.4), for 422s

    var errorDescription: String? { error }

    /// One validation problem. `loc` is the path to the bad value: `"body"`, then keys and indexes;
    /// inside a question its type follows its id (`["body", "questions", "urgency", "score", "criteria"]`).
    struct Issue: Decodable, Hashable, Sendable {
        let loc: [Loc]
        let msg: String

        /// The question the issue is about, if any.
        var questionID: String? {
            guard loc.count > 2, loc[0] == .key("body"), loc[1] == .key("questions"), case .key(let id) = loc[2] else {
                return nil
            }
            return id
        }
    }

    enum Loc: Decodable, Hashable, Sendable {
        case key(String)
        case index(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
            } else {
                self = .key(try container.decode(String.self))
            }
        }
    }
}

/// `POST /api/decide` response (docs/api.md §7.3). Decode with a plain `JSONDecoder()`:
/// `.convertFromSnakeCase` would also rewrite the caller's question ids in `answers`
/// (`is_urgent` → `isUrgent`).
struct DecideResponse: Decodable, Sendable {
    let model: String            // the model that answered (a router's target)
    let answers: [String: Answer]
    let totalDuration: Int64     // nanoseconds
    var evalDuration: Int64?
    var usage: Usage?
    var routing: Routing?        // only for a router
    var stateTruncated: Bool?
    /// The body as the server sent it, for the inspector. Set by `OllayaClient.decide`.
    var json = Data()

    /// `inputTokens` counts the text once per question, with that question's instructions and
    /// options, summed over the questions; a truncated text counts as cut (measured, Phase 4).
    struct Usage: Decodable, Hashable, Sendable {
        let inputTokens: Int
        enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
    }

    struct Routing: Decodable, Hashable, Sendable {
        let route: String        // `english`, `multilingual`
        let reason: String       // in words; informative only
    }

    enum CodingKeys: String, CodingKey {
        case model, answers, usage, routing
        case totalDuration = "total_duration"
        case evalDuration = "eval_duration"
        case stateTruncated = "state_truncated"
    }
}

/// One answer; which fields are set depends on `type` (docs/api.md §5.4). `probabilities` is keyed
/// by label (choice) or level `"0"`… (score); a Swift dictionary, so its order is not the criteria's.
struct Answer: Decodable, Hashable, Sendable {
    let type: String             // "choice", "score" or "noul"
    let choice: String?
    let score: Double?
    let noul: Double?
    let confidence: Double?
    let probabilities: [String: Double]?
}

/// One line of the `POST /api/pull` stream (docs/api.md §7.6). Layer lines carry `digest`,
/// `total` and `completed`; the others only `status`.
struct PullProgress: Decodable, Equatable, Sendable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
