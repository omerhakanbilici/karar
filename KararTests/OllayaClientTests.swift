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

    func testDecodesDecideResponseFromTheAPIDoc() throws {
        // docs/api.md §7.3, first DecideResponse example (router), verbatim.
        let json = #"""
        {
          "model": "laya:en",
          "answers": {
            "department": {
              "type": "choice",
              "choice": "billing",
              "confidence": 0.7781,
              "probabilities": {"billing": 0.8521, "technical": 0.0611, "account": 0.0868}
            },
            "urgency": {
              "type": "score",
              "score": 1.1982,
              "confidence": 0.3418,
              "legend": {"0": "Can wait", "1": "Needs attention this week", "2": "Needs attention today"},
              "probabilities": {"0": 0.1203, "1": 0.5612, "2": 0.3185}
            },
            "refund": {"type": "noul", "noul": 0.9127}
          },
          "usage": {"input_tokens": 118, "output_tokens": 0},
          "routing": {
            "router": "laya:latest",
            "model": "laya:en",
            "route": "english",
            "reason": "English Latin text"
          },
          "state_truncated": false,
          "done_reason": "decide",
          "created_at": "2026-09-24T09:30:12.418Z",
          "total_duration": 18734512,
          "load_duration": 0,
          "eval_duration": 16302117
        }
        """#
        let r = try JSONDecoder().decode(DecideResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.model, "laya:en")
        XCTAssertEqual(r.totalDuration, 18_734_512)
        XCTAssertEqual(r.answers["department"]?.choice, "billing")
        XCTAssertEqual(r.answers["department"]?.confidence, 0.7781)
        XCTAssertEqual(r.answers["urgency"]?.score, 1.1982)
        XCTAssertEqual(r.answers["urgency"]?.probabilities?.count, 3)
        XCTAssertEqual(r.usage?.inputTokens, 118)
        XCTAssertEqual(r.routing?.route, "english")
        XCTAssertEqual(r.routing?.reason, "English Latin text")
        XCTAssertEqual(r.stateTruncated, false)
        XCTAssertEqual(r.evalDuration, 16_302_117)
        XCTAssertEqual(r.answers["refund"]?.type, "noul")
        XCTAssertEqual(r.answers["refund"]?.noul, 0.9127)
        XCTAssertNil(r.answers["refund"]?.confidence)
    }

    func testDecideKeepsSnakeCaseQuestionIDs() throws {
        let json = #"{"model": "laya:en", "answers": {"is_urgent": {"type": "noul", "noul": 0.2}}, "total_duration": 1}"#
        let r = try JSONDecoder().decode(DecideResponse.self, from: Data(json.utf8))
        XCTAssertEqual(Array(r.answers.keys), ["is_urgent"])
    }

    func testDecideBodySplicesQuestionsVerbatim() throws {
        let questions = Data(#"{"b": {"type": "noul"}, "a": {"type": "noul"}}"#.utf8)
        let body = try OllayaClient.decideBody(model: "laya", state: "Hi \"you\"", questions: questions)
        XCTAssertNotNil(body.range(of: Data(#","questions":{"b": {"type": "noul"}, "a": {"type": "noul"}}}"#.utf8)),
                        String(decoding: body, as: UTF8.self))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "laya")
        XCTAssertEqual(object["state"] as? String, "Hi \"you\"")
        XCTAssertEqual(object["keep_alive"] as? String, "30m")
    }

    func testStateIsTextUnlessItIsAJSONObjectOrArray() throws {
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("  {\"a\": 1}\n"), as: UTF8.self), #"{"a": 1}"#)
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("[1, 2]"), as: UTF8.self), "[1, 2]")
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("{not json"), as: UTF8.self), #""{not json""#)
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("hello\n\n"), as: UTF8.self), #""hello""#)
    }

    private func lines(_ text: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            for line in text.split(separator: "\n") { continuation.yield(String(line)) }
            continuation.finish()
        }
    }

    func testReadsThePullStreamFromTheAPIDoc() async throws {
        // docs/api.md §7.6 example (v0.3.2), first four and last three lines.
        let ndjson = #"""
        {"status":"pulling manifest"}
        {"status":"pulling 2409643934fa","digest":"sha256:2409643934fa5fa03f823921d7cb76a413143606f826946316d5ce4f5e2d15d5","total":318,"completed":318}
        {"status":"pulling 8d32a80bb199","digest":"sha256:8d32a80bb199bcd4ff10abc28d651fe576fb59f86b24039402e49be9e01578c2","total":841114235,"completed":0}
        {"status":"pulling 8d32a80bb199","digest":"sha256:8d32a80bb199bcd4ff10abc28d651fe576fb59f86b24039402e49be9e01578c2","total":841114235,"completed":420557117}
        {"status":"verifying sha256 digest"}
        {"status":"writing manifest"}
        {"status":"success"}
        """#
        var seen: [PullProgress] = []
        try await OllayaClient.readPull(lines(ndjson)) { seen.append($0) }
        XCTAssertEqual(seen.count, 7)
        XCTAssertEqual(seen[0], PullProgress(status: "pulling manifest", digest: nil, total: nil, completed: nil))
        XCTAssertEqual(seen[3].total, 841_114_235)
        XCTAssertEqual(seen[3].completed, 420_557_117)
        XCTAssertEqual(seen.last?.status, "success")
    }

    func testAnErrorLineInThePullStreamThrowsIt() async {
        // docs/api.md §4.3 example.
        let ndjson = #"""
        {"status":"pulling manifest"}
        {"error":"blob sha256:8d32 does not match its digest; the download was discarded","code":"DIGEST_MISMATCH"}
        """#
        var seen = 0
        do {
            try await OllayaClient.readPull(lines(ndjson)) { _ in seen += 1 }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? OllayaError)?.code, "DIGEST_MISMATCH")
            XCTAssertEqual(seen, 1)
        }
    }

    func testAPullStreamWithoutSuccessIsAFailure() async {
        let ndjson = #"{"status":"pulling manifest"}"#
        do {
            try await OllayaClient.readPull(lines(ndjson)) { _ in }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The download was interrupted.")
        }
    }

    func testDeletingAModelThatIsAlreadyGoneSucceeds() throws {
        let url = URL(string: "http://x")!
        let gone = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try OllayaClient.checkDelete(gone, Data(#"{"error":"model \"x:latest\" not found, try pulling it first","code":"MODEL_NOT_FOUND"}"#.utf8)))
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try OllayaClient.checkDelete(ok, Data()))
        let busy = HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OllayaClient.checkDelete(busy, Data(#"{"error":"laya:en is being pulled","code":"OPERATION_IN_PROGRESS"}"#.utf8))) {
            XCTAssertEqual(($0 as? OllayaError)?.code, "OPERATION_IN_PROGRESS")
        }
    }

    func testDecodesATruncatedResponseWithoutARouter() throws {
        let json = #"""
        {"model": "laya:en", "answers": {}, "usage": {"input_tokens": 512, "output_tokens": 0},
         "routing": null, "state_truncated": true, "total_duration": 1, "eval_duration": 1}
        """#
        let r = try JSONDecoder().decode(DecideResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.usage?.inputTokens, 512)
        XCTAssertEqual(r.stateTruncated, true)
        XCTAssertNil(r.routing)
    }

    func testAValidationErrorNamesItsQuestions() throws {
        // Recorded from the pinned engine (docs/api.md §4.4), plus a state issue.
        let body = Data(#"""
        {"error":"state: Field required; questions.q.score.criteria: List should have at least 2 items after validation, not 1; questions.a b.choice.criteria: Dictionary should have at least 2 items after validation, not 0","code":"INVALID_REQUEST","detail":[{"loc":["body","state"],"msg":"Field required","type":"missing"},{"loc":["body","questions","q","score","criteria"],"msg":"List should have at least 2 items after validation, not 1","type":"too_short","ctx":{"field_type":"List","min_length":2,"actual_length":1}},{"loc":["body","questions","a b","choice","criteria"],"msg":"Dictionary should have at least 2 items after validation, not 0","type":"too_short","ctx":{"field_type":"Dictionary","min_length":2,"actual_length":0}}]}
        """#.utf8)
        let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 422, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OllayaClient.check(response, body)) { error in
            let detail = (error as? OllayaError)?.detail ?? []
            XCTAssertEqual(detail.map(\.questionID), [nil, "q", "a b"])
            XCTAssertEqual(detail[1].msg, "List should have at least 2 items after validation, not 1")
            XCTAssertEqual(detail[1].loc, [.key("body"), .key("questions"), .key("q"), .key("score"), .key("criteria")])
        }
    }

    func testAnIndexInALocIsAnInt() throws {
        let issue = try JSONDecoder().decode(OllayaError.Issue.self, from: Data(#"{"loc": ["body", "questions", "1", 0], "msg": "x"}"#.utf8))
        XCTAssertEqual(issue.loc, [.key("body"), .key("questions"), .key("1"), .index(0)])
        XCTAssertEqual(issue.questionID, "1")
    }

    func testCurlQuotesTheBodyForTheShell() throws {
        let body = try OllayaClient.decideBody(model: "laya", state: "It's \"late\"\nand $HOME `x`", questions: Data(#"{"q": {"type": "noul"}}"#.utf8))
        let command = OllayaClient.local.curl(body: body)
        XCTAssertTrue(command.hasPrefix("curl http://127.0.0.1:11435/api/decide -d '"), command)
        // A shell function named curl prints the -d argument, so this checks what a shell really passes.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "curl() { printf %s \"$3\"; }; " + command]
        let out = Pipe()
        shell.standardOutput = out
        try shell.run()
        shell.waitUntilExit()
        XCTAssertEqual(out.fileHandleForReading.readDataToEndOfFile(), body)
    }
}
