import XCTest
@testable import Karar

@MainActor
final class FakeOllaya {
    var calls: [(model: String, state: String, questions: Data)] = []
    var delay: Duration = .zero
    var failure: Error?
    var installed = ["laya:en", "laya:multilingual"]
    var tagsDelays: [Duration] = []    // one per call, in call order; missing = no delay
    var pulls: [String: AsyncThrowingStream<PullProgress, Error>.Continuation] = [:]
    var deleted: [String] = []
    var deleteFailure: Error?

    /// Answers every triage question; the response's `model` echoes the state so tests can tell
    /// which request produced the visible result.
    func decide(_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse {
        calls.append((model, state, questions))
        try await Task.sleep(for: delay)   // throws CancellationError when cancelled, like URLSession
        if let failure { throw failure }
        let yes = Answer(type: "noul", choice: nil, score: nil, noul: 0.9, confidence: nil, probabilities: nil)
        return DecideResponse(model: state, answers: ["churn_risk": yes, "is_urgent": yes], totalDuration: 1)
    }

    func tags() async throws -> [ModelInfo] {
        let snapshot = installed
        let delay = tagsDelays.isEmpty ? .zero : tagsDelays.removeFirst()
        try await Task.sleep(for: delay)
        return snapshot.map { ModelInfo(name: $0, size: 1, details: .init(format: "onnx", family: "laya", parameterSize: "")) }
    }

    func version() async throws -> String { "0.3.2" }

    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: PullProgress.self, throwing: Error.self)
        pulls[model] = continuation
        return stream
    }

    func delete(_ model: String) async throws {
        if let deleteFailure { throw deleteFailure }
        deleted.append(model)
        installed.removeAll { $0 == model }
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private func makeApp(_ fake: FakeOllaya) -> AppModel {
        let daemon = Daemon(probe: { .none }, launch: { _ in {} })
        let app = AppModel(daemon: daemon, decide: fake.decide, tags: fake.tags, version: fake.version,
                           pull: fake.pull, delete: fake.delete, debounce: .milliseconds(50))
        app.model = "laya:en"
        return app
    }

    private func line(_ status: String, _ digest: String? = nil, _ total: Int64? = nil, _ completed: Int64? = nil) -> PullProgress {
        PullProgress(status: status, digest: digest, total: total, completed: completed)
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

    func testTheNewestRefreshWins() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        fake.tagsDelays = [.milliseconds(300), .zero]
        let slow = Task { await app.refreshModels() }          // sees the old list, answers last
        try? await Task.sleep(for: .milliseconds(50))
        fake.installed = ["laya:multilingual"]
        await app.refreshModels()
        await slow.value
        XCTAssertEqual(app.models.map(\.name), ["laya:multilingual"])
    }

    func testModelsAreNotLoadedUntilTheFirstRefresh() async {
        let fake = FakeOllaya()
        fake.installed = []
        let app = makeApp(fake)
        XCTAssertFalse(app.modelsLoaded)
        XCTAssertFalse(app.isOnboarding)
        await app.connect()
        XCTAssertTrue(app.modelsLoaded)
        XCTAssertTrue(app.isOnboarding, "no model installed: onboarding")
        XCTAssertEqual(app.engineVersion, "0.3.2")
    }

    func testADownloadFoldsProgressAndRefreshesOnSuccess() async throws {
        let fake = FakeOllaya()
        fake.installed = []
        let app = makeApp(fake)
        await app.connect()
        let entry = try XCTUnwrap(CatalogEntry.named("laya:multilingual"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        let pull = try XCTUnwrap(fake.pulls[entry.name])
        pull.yield(line("pulling manifest"))
        pull.yield(line("pulling w", "sha256:w", 1000, 250))
        await waitUntil { app.downloads[entry.name]?.parts.first?.completed == 250 }
        fake.installed = ["laya:multilingual"]
        pull.yield(line("success"))
        pull.finish()
        await waitUntil { app.isInstalled(entry) }
        XCTAssertEqual(app.downloads[entry.name]?.isFinished, true)
        XCTAssertTrue(app.isOnboarding, "stays until Get started")
    }

    func testAFailedDownloadShowsTheErrorAndRetryStartsAgain() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        let entry = try XCTUnwrap(CatalogEntry.named("nli"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        fake.pulls[entry.name]?.finish(throwing: OllayaError(error: "The download was interrupted.", code: nil))
        await waitUntil { app.downloads[entry.name]?.error != nil }
        XCTAssertEqual(app.downloads[entry.name]?.error, "The download was interrupted.")
        fake.pulls[entry.name] = nil
        app.download(entry)                                   // Retry
        XCTAssertNotNil(app.downloads[entry.name])
        XCTAssertNil(app.downloads[entry.name]?.error)
        await waitUntil { fake.pulls[entry.name] != nil }
    }

    func testCancellingADownloadForgetsIt() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        let entry = try XCTUnwrap(CatalogEntry.named("gliclass"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        app.cancelDownload(entry)
        await waitUntil { app.downloads[entry.name] == nil }
        fake.pulls[entry.name] = nil
        app.download(entry)                                   // A new download can start after a cancel
        await waitUntil { fake.pulls[entry.name] != nil }
    }

    func testCancellingAnEndedDownloadForgetsIt() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        let entry = try XCTUnwrap(CatalogEntry.named("gliclass"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        fake.pulls[entry.name]?.finish(throwing: OllayaError(error: "The download was interrupted.", code: nil))
        await waitUntil { app.downloads[entry.name]?.error != nil }
        app.cancelDownload(entry)
        XCTAssertNil(app.downloads[entry.name])
    }

    func testDeleteRemovesTheModelAndMovesTheSelection() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        await app.refreshModels()
        await app.delete("laya:en")
        XCTAssertEqual(fake.deleted, ["laya:en"])
        XCTAssertEqual(app.models.map(\.name), ["laya:multilingual"])
        XCTAssertEqual(app.model, "laya:multilingual")
        XCTAssertNil(app.deleteError)
    }

    func testDeleteDropsAFinishedDownloadOfTheDeletedModel() async throws {
        let fake = FakeOllaya()
        fake.installed = []
        let app = makeApp(fake)
        await app.connect()
        let entry = try XCTUnwrap(CatalogEntry.named("laya:multilingual"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        fake.installed = ["laya:multilingual"]
        fake.pulls[entry.name]?.yield(line("success"))
        fake.pulls[entry.name]?.finish()
        await waitUntil { app.isInstalled(entry) }
        await app.delete(entry.name)
        XCTAssertNil(app.downloads[entry.name], "a finished download of the deleted model is stale")
    }

    func testDeleteErrorsAreShown() async {
        let fake = FakeOllaya()
        fake.deleteFailure = OllayaError(error: "laya:en is being pulled", code: "OPERATION_IN_PROGRESS")
        let app = makeApp(fake)
        await app.delete("laya:en")
        XCTAssertEqual(app.deleteError, "laya:en is being pulled")
    }

    func testGetStartedShowsASampleTicketWithTheNewModel() async throws {
        let fake = FakeOllaya()
        fake.installed = []
        let app = makeApp(fake)
        await app.connect()
        fake.installed = ["laya:en", "laya:latest", "laya:multilingual"]
        await app.refreshModels()
        app.preset = Preset.all[2]
        app.getStarted(with: try XCTUnwrap(CatalogEntry.named("laya")))
        XCTAssertFalse(app.isOnboarding)
        XCTAssertEqual(app.model, "laya:latest")
        XCTAssertEqual(app.preset.id, "triage")
        XCTAssertEqual(app.text, AppModel.sampleTicket)
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(fake.calls.last?.state, AppModel.sampleTicket)
    }
}
