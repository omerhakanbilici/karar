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
    var tagsFailure: Error?
    var versionDelay: Duration = .zero
    var loads: [String] = []

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
        if let tagsFailure { throw tagsFailure }
        return snapshot.map { ModelInfo(name: $0, size: 1, details: .init(format: "onnx", family: "laya", parameterSize: "")) }
    }

    func version() async throws -> String {
        try await Task.sleep(for: versionDelay)
        return "0.3.2"
    }

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

    func load(_ model: String) async throws { loads.append(model) }
}

@MainActor
final class AppModelTests: XCTestCase {
    private func makeApp(_ fake: FakeOllaya) -> AppModel {
        let daemon = Daemon(probe: { .none }, launch: { _ in {} })
        let app = AppModel(daemon: daemon, decide: fake.decide, tags: fake.tags, version: fake.version,
                           pull: fake.pull, delete: fake.delete, load: fake.load, debounce: .milliseconds(50))
        app.model = "laya:en"
        return app
    }

    private func line(_ status: String, _ digest: String? = nil, _ total: Int64? = nil, _ completed: Int64? = nil) -> PullProgress {
        PullProgress(status: status, digest: digest, total: total, completed: completed)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        // 10 s: generous for shared CI runners; returns as soon as the condition holds.
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
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

    func testPickingAModelPreloadsIt() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.model = "laya:multilingual"
        await waitUntil { fake.loads.last == "laya:multilingual" }
        fake.loads = []
        await app.connect()                                    // after an engine restart
        await waitUntil { fake.loads == ["laya:multilingual"] }
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
        fake.failure = OllayaError(error: "HTTP 500", code: nil)
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.error, "HTTP 500")
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
        XCTAssertNil(app.model, "deleted outside Karar: no silent switch to another model (spec §5)")
        XCTAssertEqual(app.missingModel, "laya:multilingual")
        fake.installed = ["laya:en", "laya:multilingual"]
        await app.refreshModels()
        XCTAssertEqual(app.model, "laya:multilingual", "it came back: selected again")
        XCTAssertNil(app.missingModel)
    }

    func testAFailedRefreshShowsTheErrorAndKeepsTheModels() async {
        let fake = FakeOllaya()
        fake.tagsFailure = OllayaError(error: "HTTP 500", code: nil)
        let app = makeApp(fake)
        await app.refreshModels()
        XCTAssertFalse(app.modelsLoaded)
        XCTAssertEqual(app.modelsError, "HTTP 500", "no silent spinner forever")
        fake.tagsFailure = nil
        await app.refreshModels()
        XCTAssertTrue(app.modelsLoaded)
        XCTAssertNil(app.modelsError)
        fake.tagsFailure = OllayaError(error: "HTTP 500", code: nil)
        await app.refreshModels()
        XCTAssertEqual(app.models.map(\.name), ["laya:en", "laya:multilingual"], "the list on screen stays")
        XCTAssertEqual(app.modelsError, "HTTP 500")
    }

    func testAnOlderRefreshAnsweringLastIsDropped() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        fake.tagsDelays = [.milliseconds(300), .zero]
        fake.tagsFailure = nil
        let slow = Task { await app.refreshModels() }          // older call, answers last
        await waitUntil { fake.tagsDelays.count == 1 }         // the older call took its 300 ms delay
        fake.tagsFailure = OllayaError(error: "HTTP 500", code: nil)
        await app.refreshModels()                              // newest call fails first
        fake.tagsFailure = nil
        await slow.value
        XCTAssertEqual(app.modelsError, "HTTP 500", "the newest answer stays on screen")
    }

    func testAModelNotFoundAnswerRefreshesTheModels() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        fake.installed = ["laya:multilingual"]
        fake.failure = OllayaError(error: "model \"laya:en\" not found, try pulling it first", code: "MODEL_NOT_FOUND")
        app.text = "Hello"
        await waitUntil { app.model == nil }
        XCTAssertEqual(app.missingModel, "laya:en")
        XCTAssertNil(app.error, "the note replaces the engine's message")
        XCTAssertFalse(app.isUpdating)
    }

    /// A router's *target* can be missing while the router itself stays installed (docs/api.md §3,
    /// §7.7: deleting a target keeps the router). The refresh then still lists the selected router,
    /// so the missing-model note doesn't apply: show the engine's own message instead.
    func testARoutersMissingTargetShowsTheEnginesMessage() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        fake.failure = OllayaError(
            error: "model \"laya:en\" not found, try pulling it first (routed from \"laya:latest\")",
            code: "MODEL_NOT_FOUND")
        app.text = "Hello"
        await waitUntil { !app.isUpdating }
        XCTAssertTrue(fake.installed.contains("laya:en"), "the router itself is still installed")
        XCTAssertEqual(app.error, "model \"laya:en\" not found, try pulling it first (routed from \"laya:latest\")")
        XCTAssertEqual(app.model, "laya:en")
    }

    func testDeletingTheSelectedModelInKararPicksTheNextOne() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        await app.refreshModels()
        await app.delete("laya:en")
        XCTAssertEqual(app.model, "laya:multilingual")
        XCTAssertNil(app.missingModel, "deleted on purpose, not missing")
    }

    func testModelsFromTheCommandLineEndOnboarding() async {
        let fake = FakeOllaya()
        fake.installed = []
        let app = makeApp(fake)
        app.model = nil
        await app.connect()
        XCTAssertTrue(app.isOnboarding)
        fake.installed = ["laya:en"]                           // `ollaya pull laya:en` in Terminal
        await app.refreshModels()
        XCTAssertFalse(app.isOnboarding)
        XCTAssertEqual(app.model, "laya:en")
    }

    func testConnectAsksAgainSoAnOldErrorGoesAway() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        await app.refreshModels()
        fake.failure = URLError(.networkConnectionLost)
        app.text = "Hello"
        await waitUntil { app.error != nil }
        fake.failure = nil                                     // the engine restarted
        await app.connect()
        await waitUntil { app.result != nil }
        XCTAssertNil(app.error)
    }

    func testAModelThatComesBackDuringAReconnectIsAskedOnce() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "Hello"
        await waitUntil { app.result != nil }
        fake.installed = ["laya:multilingual"]
        await app.refreshModels()
        XCTAssertNil(app.model)
        XCTAssertEqual(app.missingModel, "laya:en")
        fake.installed = ["laya:en", "laya:multilingual"]
        fake.versionDelay = .milliseconds(300)
        let before = fake.calls.count
        await app.connect()
        await waitUntil { !app.isUpdating }
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fake.calls.count, before + 1, "the refresh's own re-selection already re-ran; connect() must not ask again")
    }

    func testTheNewestRefreshWins() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        fake.tagsDelays = [.milliseconds(300), .zero]
        let slow = Task { await app.refreshModels() }          // sees the old list, answers last
        await waitUntil { fake.tagsDelays.count == 1 }         // the older call took its 300 ms delay
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

    func testPullErrorsAreWordedByCode() {
        func message(_ code: String?, _ text: String = "raw") -> String {
            AppModel.pullMessage(OllayaError(error: text, code: code))
        }
        XCTAssertEqual(message("REGISTRY_ERROR", "No space left on device (os error 28)"),
                       "Could not download the model: No space left on device (os error 28)")
        XCTAssertEqual(message("DIGEST_MISMATCH"), "A downloaded file was damaged and has been discarded.")
        XCTAssertEqual(message("STORAGE_ERROR", "No space left on device"), "Could not save the model: No space left on device")
        XCTAssertEqual(message("MODEL_NOT_FOUND"), "This model is not in the registry.")
        XCTAssertEqual(message(nil, "The download was interrupted."), "The download was interrupted.")
        XCTAssertEqual(message("SOMETHING_NEW", "engine words"), "engine words", "unknown codes fall back to the message")
        XCTAssertEqual(AppModel.pullMessage(URLError(.networkConnectionLost)), "Lost the connection to Ollaya.")
        XCTAssertEqual(AppModel.pullMessage(URLError(.timedOut)),
                       "The download stopped making progress. Check your connection and free disk space.")
    }

    func testAFailedDownloadUsesTheWording() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        let entry = try XCTUnwrap(CatalogEntry.named("nli"))
        app.download(entry)
        await waitUntil { fake.pulls[entry.name] != nil }
        fake.pulls[entry.name]?.finish(throwing: OllayaError(error: "x", code: "DIGEST_MISMATCH"))
        await waitUntil { app.downloads[entry.name]?.error != nil }
        XCTAssertEqual(app.downloads[entry.name]?.error, "A downloaded file was damaged and has been discarded.")
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

    func testEditingAQuestionSwitchesToMyQuestionsAndSendsThem() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertFalse(app.isCustom)
        app.questions[1].instructions = "Is it urgent?"
        XCTAssertTrue(app.isCustom)
        await waitUntil { fake.calls.count == 2 && !app.isUpdating }
        let sent = Question.parse(fake.calls[1].questions)
        XCTAssertEqual(sent.map(\.key), Preset.all[0].questionIDs)
        XCTAssertEqual(sent[1].instructions, "Is it urgent?")
    }

    func testAPresetKeepsMyQuestionsForLater() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.questions.removeLast()
        XCTAssertTrue(app.isCustom)
        app.preset = Preset.all[0]                       // the same preset, as shipped
        XCTAssertFalse(app.isCustom)
        XCTAssertEqual(app.questions.map(\.key), Preset.all[0].questionIDs)
        app.useMyQuestions()
        XCTAssertTrue(app.isCustom)
        XCTAssertEqual(app.questions.count, 4)
    }

    func testMyQuestionsStartFromTheQuestionsOnScreen() {
        let app = makeApp(FakeOllaya())
        app.preset = Preset.all[1]
        app.useMyQuestions()
        XCTAssertTrue(app.isCustom)
        XCTAssertEqual(app.questions.map(\.key), Preset.all[1].questionIDs)
    }

    func testAddQuestionPicksAFreeID() {
        let app = makeApp(FakeOllaya())
        app.addQuestion()
        app.addQuestion()
        XCTAssertEqual(app.questions.suffix(2).map(\.key), ["question_6", "question_7"])
        XCTAssertEqual(app.questions.last?.kind, .noul)
        XCTAssertTrue(app.isCustom)
    }

    func testValidationErrorsMarkTheirQuestion() async {
        let fake = FakeOllaya()
        let msg = "List should have at least 2 items after validation, not 1"
        fake.failure = OllayaError(error: "questions.frustration.score.criteria: \(msg)", code: "INVALID_REQUEST",
                                   detail: [.init(loc: [.key("body"), .key("questions"), .key("frustration"), .key("score"), .key("criteria")], msg: msg)])
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.questionErrors, ["frustration": msg])
        XCTAssertNil(app.error, "every issue is on a card")
        fake.failure = nil
        app.text = "hello!"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.questionErrors, [:])
    }

    func testAnIssueOutsideTheQuestionsIsShownAboveTheAnswers() async {
        let fake = FakeOllaya()
        fake.failure = OllayaError(error: "state: too long", code: "INPUT_TOO_LONG",
                                   detail: [.init(loc: [.key("body"), .key("state")], msg: "65,537 tokens is more than 65,536")])
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(app.error, "65,537 tokens is more than 65,536")
        XCTAssertEqual(app.questionErrors, [:])
    }

    func testDuplicateIDsAreMarkedAndNotSent() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        await waitUntil { !app.isUpdating }
        app.questions[1].key = "intent"
        XCTAssertEqual(app.questionErrors, ["intent": "Another question has the same id."])
        XCTAssertNil(app.result)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fake.calls.count, 1)
    }

    func testRequestBodyCarriesTheQuestionsInUse() throws {
        let app = makeApp(FakeOllaya())
        XCTAssertNil(app.requestBody, "no text yet")
        app.text = "hi"
        app.questions.removeLast()
        let body = try XCTUnwrap(app.requestBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "laya:en")
        XCTAssertEqual(object["state"] as? String, "hi")
        XCTAssertEqual((object["questions"] as? [String: Any])?.count, 4)
    }

    func testAPinRestoresItsInput() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        await app.refreshModels()
        app.model = "laya:en"
        app.text = "first\nsecond line"
        await waitUntil { !app.isUpdating }
        app.pin()
        let pin = try XCTUnwrap(app.pins.first)
        XCTAssertEqual(pin.title, "first")
        XCTAssertEqual(pin.setName, "Support ticket")
        XCTAssertEqual(pin.rows.map(\.id), ["is_urgent", "churn_risk"])

        app.model = "laya:multilingual"
        app.preset = Preset.all[1]
        app.text = "other"
        app.restore(pin)
        XCTAssertEqual(app.model, "laya:en")
        XCTAssertEqual(app.preset.id, "triage")
        XCTAssertFalse(app.isCustom)
        XCTAssertEqual(app.text, "first\nsecond line")
        await waitUntil { !app.isUpdating }
        XCTAssertEqual(fake.calls.last?.state, "first\nsecond line")

        app.unpin(pin)
        XCTAssertTrue(app.pins.isEmpty)
    }

    func testAPinOfMyQuestionsRestoresThem() async throws {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.text = "hello"
        app.questions.removeLast()
        await waitUntil { !app.isUpdating }
        app.pin()
        let pin = try XCTUnwrap(app.pins.first)
        XCTAssertEqual(pin.setName, "My questions")
        app.preset = Preset.all[1]
        app.restore(pin)
        XCTAssertNil(app.result)
        XCTAssertTrue(app.isCustom)
        XCTAssertEqual(app.questions.count, 4)
    }

    func testNothingToPinWithoutAnAnswer() {
        let app = makeApp(FakeOllaya())
        app.pin()
        XCTAssertTrue(app.pins.isEmpty)
    }
}
