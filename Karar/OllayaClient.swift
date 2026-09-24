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

    /// `POST /api/pull` as a stream of progress lines. Cancelling the consumer closes the
    /// connection; the daemon then stops the pull and keeps what it has (docs/api.md §10), so the
    /// next pull of the same name resumes.
    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let request: URLRequest = {
            var request = URLRequest(url: base.appending(path: "api/pull"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["model": model])
            return request
        }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    // Errors before the stream starts are ordinary HTTP errors (docs/api.md §7.6).
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try Self.check(response, body)
                    }
                    try await Self.readPull(bytes.lines) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads pull lines until `success`. An error line (docs/api.md §4.3) is thrown; a stream
    /// that ends without `success` was cut off and is a failure.
    static func readPull<Lines: AsyncSequence>(_ lines: Lines, onProgress: (PullProgress) -> Void) async throws
    where Lines.Element == String {
        for try await line in lines where !line.isEmpty {
            let data = Data(line.utf8)
            if let error = try? decoder.decode(OllayaError.self, from: data) { throw error }
            let progress = try decoder.decode(PullProgress.self, from: data)
            onProgress(progress)
            if progress.status == "success" { return }
        }
        throw OllayaError(error: "The download was interrupted.", code: nil)
    }

    func delete(model: String) async throws {
        var request = URLRequest(url: base.appending(path: "api/delete"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": model])
        let (data, response) = try await Self.session.data(for: request)
        try Self.checkDelete(response, data)
    }

    /// A `404 MODEL_NOT_FOUND` means the model is already gone, which is what was asked
    /// (docs/api.md §7.7).
    static func checkDelete(_ response: URLResponse, _ data: Data) throws {
        do {
            try check(response, data)
        } catch let error as OllayaError where error.code == "MODEL_NOT_FOUND" {
            return
        }
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
