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
