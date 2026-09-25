import XCTest

/// Smoke tests against the real app and Karar's own engine (spec §6). Local only, never in CI:
/// XCUITest drives the real mouse and keyboard (don't use the Mac meanwhile), needs Automation
/// mode, doesn't work while the screen is locked, and needs port 11435 free (quit Ollaya.app and
/// any `ollaya serve`). Tests that need a model read a store with laya:en from
/// KARAR_UITEST_MODELS, e.g. the one `KARAR_SMOKE_MODELS=<dir> scripts/smoke.sh` fills:
///
///     TEST_RUNNER_KARAR_UITEST_MODELS=<dir> xcodebuild -project Karar.xcodeproj \
///       -scheme KararUITests -destination 'platform=macOS' -derivedDataPath build test
///
/// Never ~/.ollaya. Window screenshots (light and dark) are attached to the results.
@MainActor
final class KararUITests: XCTestCase {
    private var app: XCUIApplication?
    private var squatter: Process?

    private static let ticket = "Hi, I was charged twice for my subscription this month. Please refund "
        + "the second payment. If this is not fixed by Friday I will cancel my account."

    private struct SetupError: Error, CustomStringConvertible { let description: String }

    // No `continueAfterFailure = false`: with it, a failed assert runs the async tearDown from
    // inside this @MainActor test and deadlocks the runner. A test that can't go on throws instead.
    override func setUp() async throws {
        if let answer = await Self.portAnswer() {
            throw SetupError(description: "Port 11435 answers (\(answer.prefix(40))). "
                + "Quit Ollaya.app and any ollaya serve, then run the UI tests again.")
        }
    }

    override func tearDown() async throws {
        if let app { try await quit(app) }
        if let squatter {
            squatter.terminate()
            squatter.waitUntilExit()
        }
        // Karar's engine stops on quit; the next test must find the port free again.
        for _ in 0..<50 where await Self.portAnswer() != nil { try await Task.sleep(for: .milliseconds(200)) }
    }

    // MARK: Tests

    func testLaunchShowsTheMainWindow() async throws {
        let app = launch(models: try Self.models())
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 30))
    }

    func testTypingBringsAnswerRows() async throws {
        let app = launch(models: try Self.models())
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.click()
        editor.typeText(Self.ticket)
        XCTAssertTrue(app.staticTexts["answer"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertEqual(app.staticTexts.matching(identifier: "answer").count, 5, "one row per triage question")
        attach(app, "typing-light")
    }

    func testCommandReturnPinsTheAnswers() async throws {
        let app = launch(models: try Self.models(), text: Self.ticket)
        XCTAssertTrue(app.staticTexts["answer"].firstMatch.waitForExistence(timeout: 60))
        let pin = app.buttons["pin"]
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: pin)
        await fulfillment(of: [enabled], timeout: 30)
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.buttons["pinnedResult"].waitForExistence(timeout: 5))
    }

    func testAPortHeldByAnotherProgramShowsTheBanner() async throws {
        // Anything that answers HTTP but isn't Ollaya. Perl, not python3: the runner is sandboxed and
        // /usr/bin/python3 is an xcrun shim, which refuses to run there.
        let squatter = Process()
        squatter.executableURL = URL(filePath: "/usr/bin/perl")
        squatter.arguments = ["-MIO::Socket::INET", "-e", #"""
            my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:11435", Listen => 5, ReuseAddr => 1) or die;
            while (my $c = $s->accept) { sysread $c, my $r, 4096; print $c "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nbusy"; close $c }
            """#]
        squatter.standardOutput = FileHandle.nullDevice
        squatter.standardError = FileHandle.nullDevice
        try squatter.run()
        self.squatter = squatter
        for _ in 0..<50 where await Self.portAnswer() == nil { try await Task.sleep(for: .milliseconds(100)) }
        let answer = await Self.portAnswer()
        _ = try XCTUnwrap(answer, "the stand-in server did not start")

        let app = launch(models: try Self.emptyStore().path)
        let title = app.staticTexts["bannerTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.value as? String, "Port 11435 is in use by another program")   // macOS: text is the value
        attach(app, "port-in-use-light")
    }

    func testAnEmptyStoreOpensOnboarding() async throws {
        let app = launch(models: try Self.emptyStore().path)
        XCTAssertTrue(app.staticTexts["welcome"].waitForExistence(timeout: 30))
        attach(app, "onboarding-light")
    }

    func testWindowScreenshotsInLightAndDark() async throws {
        let models = try Self.models()
        for appearance in ["light", "dark"] {
            let app = launch(models: models, appearance: appearance, text: Self.ticket)
            XCTAssertTrue(app.staticTexts["answer"].firstMatch.waitForExistence(timeout: 60))
            attach(app, "main-\(appearance)")
            try await quit(app)
            self.app = nil
            for _ in 0..<50 where await Self.portAnswer() != nil { try await Task.sleep(for: .milliseconds(200)) }
        }
    }

    // MARK: Helpers

    private func launch(models: String, appearance: String = "light", text: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OLLAYA_MODELS"] = models    // reaches Karar's own ollaya serve
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-KararAppearance", appearance, "-advanced", "NO"]
        if let text { app.launchArguments += ["-KararText", text] }
        app.launch()
        self.app = app
        return app
    }

    /// ⌘Q, not `terminate()`: Karar has to run `applicationWillTerminate` to stop its ollaya.
    private func quit(_ app: XCUIApplication) async throws {
        guard app.state != .notRunning else { return }
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Karar did not quit")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private static func models() throws -> String {
        guard let dir = ProcessInfo.processInfo.environment["KARAR_UITEST_MODELS"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_KARAR_UITEST_MODELS to a store with laya:en (see this file's header).")
        }
        return dir
    }

    private static func emptyStore() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "karar-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// What answers on 127.0.0.1:11435 right now; nil when nothing does.
    private static func portAnswer() async -> String? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/")!)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
