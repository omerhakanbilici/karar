import XCTest
@testable import Karar

@MainActor
final class FakeOllaya {
    var calls: [(model: String, state: String, questions: Data)] = []
    var delay: Duration = .zero
    var failure: Error?
    var installed = ["laya:en", "laya:multilingual"]

    /// Answers every triage question; the response's `model` echoes the state so tests can tell
    /// which request produced the visible result.
    func decide(_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse {
        calls.append((model, state, questions))
        try await Task.sleep(for: delay)   // throws CancellationError when cancelled, like URLSession
        if let failure { throw failure }
        let yes = Answer(type: "noul", choice: nil, score: nil, noul: 0.9, confidence: nil, legend: nil)
        return DecideResponse(model: state, answers: ["churn_risk": yes, "is_urgent": yes], totalDuration: 1)
    }

    func tags() async throws -> [ModelInfo] {
        installed.map { ModelInfo(name: $0, size: 1, details: .init(format: "onnx", family: "laya", parameterSize: "")) }
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private func makeApp(_ fake: FakeOllaya) -> AppModel {
        let daemon = Daemon(probe: { .none }, launch: { _ in {} })
        let app = AppModel(daemon: daemon, decide: fake.decide, tags: fake.tags, debounce: .milliseconds(50))
        app.model = "laya:en"
        return app
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    func testATypingBurstSendsOneRequestWithTheLastText() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "a"
        app.text = "ab"
        app.text = "abc"
        XCTAssertTrue(app.isUpdating)
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(fake.calls.map(\.state), ["abc"])
        XCTAssertEqual(fake.calls.first?.model, "laya:en")
        XCTAssertEqual(app.result?.model, "abc")
    }

    func testAnEditDuringARequestCancelsIt() async {
        let fake = FakeOllaya()
        fake.delay = .milliseconds(300)
        let app = makeApp(fake)
        app.text = "first"
        await waitUntil { fake.calls.count == 1 }
        app.text = "second"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(fake.calls.map(\.state), ["first", "second"])
        XCTAssertEqual(app.result?.model, "second")
    }

    func testSwitchingModelReruns() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        app.model = "laya:multilingual"
        XCTAssertNotNil(app.result, "old rows stay while the new model answers")
        await waitUntil { fake.calls.count == 2 && !app.isUpdating }
        XCTAssertEqual(fake.calls.map(\.model), ["laya:en", "laya:multilingual"])
    }

    func testSwitchingQuestionSetRerunsWithItsQuestions() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        app.preset = Preset.all[1]
        XCTAssertNil(app.result, "rows of the old question set are cleared at once")
        await waitUntil { fake.calls.count == 2 && !app.isUpdating }
        XCTAssertEqual(fake.calls.last?.questions, Preset.all[1].questions)
    }

    func testBlankTextSendsNothing() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "  \n"
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertFalse(app.isUpdating)
    }

    func testErrorsAreShown() async {
        let fake = FakeOllaya()
        fake.failure = OllayaError(error: "model \"laya:xl\" not found, try pulling it first", code: "MODEL_NOT_FOUND")
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.error, "model \"laya:xl\" not found, try pulling it first")
        XCTAssertNil(app.result)
    }

    func testRowsFollowTheQuestionSetOrder() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.rows.map(\.id), ["is_urgent", "churn_risk"])
    }

    func testRefreshModelsKeepsOrReplacesTheSelection() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.model = nil
        await app.refreshModels()
        XCTAssertEqual(app.models.map(\.name), ["laya:en", "laya:multilingual"])
        XCTAssertEqual(app.model, "laya:en")
        app.model = "laya:multilingual"
        await app.refreshModels()
        XCTAssertEqual(app.model, "laya:multilingual")
        fake.installed = ["laya:en"]
        await app.refreshModels()
        XCTAssertEqual(app.model, "laya:en")
    }
}
