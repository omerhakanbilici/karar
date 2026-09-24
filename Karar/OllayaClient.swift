import Foundation

enum Liveness: Equatable, Sendable {
    case ollaya   // an Ollaya daemon answers
    case other    // something else answers on the port
    case none     // nothing listens
}

struct OllayaClient: Sendable {
    static let local = OllayaClient(base: URL(string: "http://127.0.0.1:11435")!)

    let base: URL

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func liveness() async -> Liveness {
        var request = URLRequest(url: base)
        request.timeoutInterval = 1
        do {
            let (data, response) = try await Self.session.data(for: request)
            return Self.classify(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return .none
        } catch {
            return .other
        }
    }

    static func classify(status: Int, body: Data) -> Liveness {
        status == 200 && String(decoding: body, as: UTF8.self).hasPrefix("Ollaya is running") ? .ollaya : .other
    }

    func version() async throws -> String {
        try await get("api/version", as: VersionResponse.self).version
    }

    func tags() async throws -> [ModelInfo] {
        try await get("api/tags", as: TagsResponse.self).models
    }

    func decide(model: String, state: String, questions: Data) async throws -> DecideResponse {
        var request = URLRequest(url: base.appending(path: "api/decide"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.decideBody(model: model, state: state, questions: questions)
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(DecideResponse.self, from: data)
    }

    /// The questions are spliced in as raw bytes so their key order (question order, criteria
    /// order) reaches the server unchanged; encoding them as Swift dictionaries would reorder them.
    static func decideBody(model: String, state: String, questions: Data) throws -> Data {
        Data(#"{"model":"#.utf8) + (try JSONEncoder().encode(model))
            + Data(#","state":"#.utf8) + (try stateJSON(state))
            + Data(#","questions":"#.utf8) + questions + Data("}".utf8)
    }

    /// As `ollaya run` does: a JSON object or array is sent as JSON, anything else as the text
    /// itself without trailing newlines.
    static func stateJSON(_ text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" || trimmed.first == "[",
           let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
           object is [Any] || object is [String: Any] {
            return Data(trimmed.utf8)
        }
        var text = text
        while text.last?.isNewline == true { text.removeLast() }
        return try JSONEncoder().encode(text)
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await Self.session.data(from: base.appending(path: path))
        try Self.check(response, data)
        return try Self.decoder.decode(T.self, from: data)
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw (try? decoder.decode(OllayaError.self, from: data)) ?? OllayaError(error: "HTTP \(status)", code: nil)
        }
    }
}
