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
