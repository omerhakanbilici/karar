import XCTest
@testable import Karar

@MainActor
final class FakeEngine {
    var comesUp = true
    var up = false
    var launches = 0
    var terminations = 0
    private var onExit: (@Sendable (Int32) -> Void)?

    func probe() async -> Liveness { up ? .ollaya : .none }

    func launch(_ onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void {
        launches += 1
        up = comesUp
        self.onExit = onExit
        return { [self] in
            terminations += 1
            up = false
        }
    }

    func crash(status: Int32 = 1) {
        up = false
        onExit?(status)
    }
}

@MainActor
final class DaemonTests: XCTestCase {
    private func makeDaemon(_ engine: FakeEngine, probe: Daemon.Probe? = nil,
                            timeout: Duration = .seconds(2)) -> Daemon {
        Daemon(probe: probe ?? { await engine.probe() }, launch: engine.launch, readyTimeout: timeout)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    func testAdoptsARunningOllaya() async {
        let engine = FakeEngine()
        let daemon = makeDaemon(engine, probe: { .ollaya })
        await daemon.start()
        XCTAssertEqual(daemon.state, .running(owned: false))
        XCTAssertEqual(engine.launches, 0)
        daemon.stop()
        XCTAssertEqual(engine.terminations, 0, "an adopted daemon is never stopped")
    }

    func testReportsWhenAnotherProgramHasThePort() async {
        let daemon = makeDaemon(FakeEngine(), probe: { .other })
        await daemon.start()
        XCTAssertEqual(daemon.state, .failed("Port 11435 is in use by another program."))
    }

    func testStartsTheBundledEngine() async {
        let engine = FakeEngine()
        let daemon = makeDaemon(engine)
        await daemon.start()
        XCTAssertEqual(daemon.state, .running(owned: true))
        XCTAssertEqual(engine.launches, 1)
    }

    func testTimesOutAndTerminatesWhenTheEngineNeverAnswers() async {
        let engine = FakeEngine()
        engine.comesUp = false
        let daemon = makeDaemon(engine, timeout: .milliseconds(300))
        await daemon.start()
        guard case .failed(let message) = daemon.state else { return XCTFail("\(daemon.state)") }
        XCTAssertTrue(message.hasPrefix("Ollaya did not start within"), message)
        XCTAssertEqual(engine.terminations, 1)
    }

    func testRestartsOnceThenGivesUp() async {
        let engine = FakeEngine()
        let daemon = makeDaemon(engine)
        await daemon.start()

        engine.crash()
        await waitUntil { engine.launches == 2 && daemon.state == .running(owned: true) }

        engine.crash(status: 9)
        await waitUntil { daemon.state == .failed("Ollaya stopped unexpectedly (exit code 9).") }
        XCTAssertEqual(engine.launches, 2)
    }

    func testStopTerminatesAndIgnoresTheExit() async {
        let engine = FakeEngine()
        let daemon = makeDaemon(engine)
        await daemon.start()
        daemon.stop()
        XCTAssertEqual(engine.terminations, 1)
        engine.crash(status: 0)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(engine.launches, 1, "no restart after stop()")
    }

    func testConcurrentStartsLaunchOnlyOnce() async {
        let engine = FakeEngine()
        let daemon = makeDaemon(engine)
        async let a: () = daemon.start()
        async let b: () = daemon.start()
        _ = await (a, b)
        XCTAssertEqual(engine.launches, 1)
        XCTAssertEqual(daemon.state, .running(owned: true))

        await daemon.start()
        XCTAssertEqual(engine.launches, 1, "start() while already running owned must not relaunch")
        XCTAssertEqual(daemon.state, .running(owned: true))
    }

    func testRetryAfterFailureStartsAgain() async {
        let engine = FakeEngine()
        engine.comesUp = false
        let daemon = makeDaemon(engine, timeout: .milliseconds(200))
        await daemon.start()
        engine.comesUp = true
        await daemon.start()
        XCTAssertEqual(daemon.state, .running(owned: true))
    }
}
