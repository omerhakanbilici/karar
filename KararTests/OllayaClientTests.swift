import XCTest
@testable import Karar

final class OllayaClientTests: XCTestCase {
    func testClassifiesOllaya() {
        XCTAssertEqual(OllayaClient.classify(status: 200, body: Data("Ollaya is running".utf8)), .ollaya)
    }

    func testClassifiesSomethingElseOnThePort() {
        XCTAssertEqual(OllayaClient.classify(status: 200, body: Data("Ollama is running".utf8)), .other)
        XCTAssertEqual(OllayaClient.classify(status: 404, body: Data()), .other)
    }

    func testDecodesVersion() throws {
        let v = try OllayaClient.decoder.decode(VersionResponse.self, from: Data(#"{"version": "0.3.2"}"#.utf8))
        XCTAssertEqual(v.version, "0.3.2")
    }

    func testDecodesTags() throws {
        let json = #"""
        {"models": [
          {"name": "laya:latest", "model": "laya:latest", "modified_at": "2026-09-24T08:12:40.551Z",
           "size": 11862, "digest": "5060b6e5",
           "details": {"parent_model": "", "format": "router", "family": "laya", "families": ["laya"],
                       "parameter_size": "", "quantization_level": ""}},
          {"name": "laya:en", "model": "laya:en", "modified_at": "2026-09-24T08:11:02.117Z",
           "size": 845897529, "digest": "e1b74e2b",
           "details": {"parent_model": "", "format": "onnx", "family": "laya", "families": ["laya"],
                       "parameter_size": "421M", "quantization_level": "F16"}}
        ]}
        """#
        let tags = try OllayaClient.decoder.decode(TagsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(tags.models.map(\.name), ["laya:latest", "laya:en"])
        XCTAssertEqual(tags.models[1].size, 845_897_529)
        XCTAssertEqual(tags.models[1].details.parameterSize, "421M")
        XCTAssertEqual(tags.models[0].details.format, "router")
    }

    func testCheckThrowsTheServersError() throws {
        let body = Data(#"""
        {"error": "questions.intent.choice.criteria: 140 options do not fit the option budget of laya:en",
         "code": "TOO_MANY_OPTIONS", "detail": []}
        """#.utf8)
        let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 422, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OllayaClient.check(response, body)) { error in
            XCTAssertEqual((error as? OllayaError)?.code, "TOO_MANY_OPTIONS")
        }
    }

    func testCheckFallsBackToStatusWhenBodyIsNotJSON() throws {
        let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OllayaClient.check(response, Data("oops".utf8))) { error in
            XCTAssertEqual((error as? OllayaError)?.error, "HTTP 500")
        }
    }
}
