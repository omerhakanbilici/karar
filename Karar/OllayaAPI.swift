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

    var errorDescription: String? { error }
}

/// `POST /api/decide` response. Decode with a plain `JSONDecoder()`: `.convertFromSnakeCase`
/// would also rewrite the caller's question ids in `answers` (`is_urgent` → `isUrgent`).
struct DecideResponse: Decodable, Sendable {
    let model: String            // the model that answered (a router's target)
    let answers: [String: Answer]
    let totalDuration: Int64     // nanoseconds

    enum CodingKeys: String, CodingKey {
        case model, answers
        case totalDuration = "total_duration"
    }
}

/// One answer; which fields are set depends on `type` (docs/api.md §5.4).
struct Answer: Decodable, Hashable, Sendable {
    let type: String             // "choice", "score" or "noul"
    let choice: String?
    let score: Double?
    let noul: Double?
    let confidence: Double?
    let legend: [String: String]?
}

/// One line of the `POST /api/pull` stream (docs/api.md §7.6). Layer lines carry `digest`,
/// `total` and `completed`; the others only `status`.
struct PullProgress: Decodable, Equatable, Sendable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
