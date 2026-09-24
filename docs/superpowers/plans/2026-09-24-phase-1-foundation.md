# Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A buildable Karar.app that embeds the pinned Ollaya binary, starts or adopts the
Ollaya daemon, stops only the one it started, and shows engine status and installed models.

**Architecture:** XcodeGen `project.yml` → `Karar.xcodeproj` (committed). A post-compile script
copies `vendor/ollaya/bin/ollaya` into `Contents/MacOS/`. `OllayaClient` is a small `Sendable`
struct over `URLSession`. `Daemon` is a `@MainActor @Observable` class whose process launch and
liveness probe are injected closures, so its decision logic is unit-tested without a real process.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, XcodeGen 2.46 (dev tool only), Xcode 27.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. Apple silicon only.
- No third-party Swift dependencies.
- Bundle ID `io.github.omerhakanbilici.karar`. `ENABLE_HARDENED_RUNTIME = YES`. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`).
- Ollaya pinned to `v0.3.2`, asset `ollaya-darwin-arm64.tgz`, sha256
  `959aabbddde2c8c59b585933047a12a70ca7df20d503aa7ae171a38c2b29876e`.
- Ollaya default address `http://127.0.0.1:11435`. Liveness: `GET /` → `200` body `Ollaya is running`.
- Only system semantic colours. UI text in English.
- `project.yml` is the source of truth; never hand-edit `project.pbxproj`.
- `vendor/` and `build/` are gitignored (already in `.gitignore`).

Test command used throughout (from repo root):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

---

### Task 1: Project scaffold with embedded Ollaya

**Files:**
- Create: `project.yml`
- Create: `scripts/fetch-ollaya.sh`
- Create: `Karar/KararApp.swift`
- Create: `KararTests/SmokeTests.swift`
- Create: `LICENSE`, `NOTICE`
- Generated + committed: `Karar.xcodeproj/`

**Interfaces:**
- Produces: targets `Karar` (app) and `KararTests` (unit tests, `@testable import Karar`);
  `vendor/ollaya/bin/ollaya`; the built app contains `Contents/MacOS/ollaya` and
  `Contents/Resources/Ollaya/{LICENSE,THIRD_PARTY_NOTICES,onnxruntime-ThirdPartyNotices.txt}`.

- [ ] **Step 1: Write `scripts/fetch-ollaya.sh`**

```sh
#!/bin/sh
# Downloads the pinned Ollaya release into vendor/ollaya and verifies its checksum.
set -eu
OLLAYA_VERSION=v0.3.2
OLLAYA_SHA256=959aabbddde2c8c59b585933047a12a70ca7df20d503aa7ae171a38c2b29876e

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/vendor/ollaya"
if [ -f "$dest/VERSION" ] && [ "$(cat "$dest/VERSION")" = "$OLLAYA_VERSION" ]; then
  echo "Ollaya $OLLAYA_VERSION already in vendor/ollaya"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/ollaya.tgz" \
  "https://github.com/ollaya-dev/ollaya/releases/download/$OLLAYA_VERSION/ollaya-darwin-arm64.tgz"
echo "$OLLAYA_SHA256  $tmp/ollaya.tgz" | shasum -a 256 -c -
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/ollaya.tgz" -C "$dest"
echo "$OLLAYA_VERSION" > "$dest/VERSION"
echo "Ollaya $OLLAYA_VERSION ready in vendor/ollaya"
```

Run: `chmod +x scripts/fetch-ollaya.sh && scripts/fetch-ollaya.sh && vendor/ollaya/bin/ollaya --version`
Expected: `…: OK`, `Ollaya v0.3.2 ready in vendor/ollaya`, and a line containing `0.3.2`.

- [ ] **Step 2: Write `project.yml`** (validated in a spike on 2026-09-24)

```yaml
name: Karar
options:
  bundleIdPrefix: io.github.omerhakanbilici
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "6.0"
    ARCHS: arm64
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: YES
targets:
  Karar:
    type: application
    platform: macOS
    sources:
      - path: Karar
        type: syncedFolder
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.omerhakanbilici.karar
        GENERATE_INFOPLIST_FILE: YES
        ENABLE_USER_SCRIPT_SANDBOXING: NO
        INFOPLIST_KEY_CFBundleDisplayName: Karar
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.developer-tools
        INFOPLIST_KEY_NSHumanReadableCopyright: "Karar is Apache-2.0. Includes Ollaya (Apache-2.0)."
    postCompileScripts:
      - name: Embed Ollaya
        basedOnDependencyAnalysis: false
        script: |
          set -euo pipefail
          src="$SRCROOT/vendor/ollaya"
          [ -x "$src/bin/ollaya" ] || { echo "error: run scripts/fetch-ollaya.sh first"; exit 1; }
          install -m 755 "$src/bin/ollaya" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/ollaya"
          mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Ollaya"
          cp "$src/share/doc/ollaya/"* "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Ollaya/"
  KararTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: KararTests
        type: syncedFolder
    dependencies:
      - target: Karar
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 3: Write the minimal app and a smoke test**

`Karar/KararApp.swift`:

```swift
import SwiftUI

@main
struct KararApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Karar")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

`KararTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Karar

final class SmokeTests: XCTestCase {
    func testOllayaIsEmbedded() throws {
        // Tests run inside the app (TEST_HOST), so Bundle.main is Karar.app.
        let ollaya = try XCTUnwrap(Bundle.main.url(forAuxiliaryExecutable: "ollaya"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: ollaya.path), ollaya.path)
    }
}
```

- [ ] **Step 4: Generate the project and run the tests**

Run: `xcodegen generate && <test command>`
Expected: `Executed 1 test, with 0 failures` and `** TEST SUCCEEDED **`.
The test bundle is hosted in the app (`Karar.app/Contents/PlugIns/KararTests.xctest`, XcodeGen
sets `TEST_HOST`), which is why `Bundle.main` finds `ollaya`.

- [ ] **Step 5: Add LICENSE and NOTICE**

Run: `cp vendor/ollaya/share/doc/ollaya/LICENSE LICENSE && head -3 LICENSE`
Expected: `Apache License` / `Version 2.0, January 2004` (the standard, unmodified Apache-2.0 text).

`NOTICE`:

```text
Karar — a Mac app for Ollaya
Copyright 2026 Ömer Hakan Bilici

Licensed under the Apache License, Version 2.0 (see LICENSE).

This product bundles Ollaya (https://github.com/ollaya-dev/ollaya),
licensed under the Apache License, Version 2.0. Ollaya's own licence and
third-party notices ship inside the app at Contents/Resources/Ollaya/.

Karar is not affiliated with or endorsed by the Ollaya project.
```

- [ ] **Step 6: Verify Release signing**

Run:
```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '
codesign -dv build/Build/Products/Release/Karar.app 2>&1 | grep flags
codesign --verify --strict build/Build/Products/Release/Karar.app && echo VERIFIED
```
Expected: `** BUILD SUCCEEDED **`, `flags=0x10002(adhoc,runtime)`, `VERIFIED`.

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/fetch-ollaya.sh
git add project.yml Karar.xcodeproj scripts/fetch-ollaya.sh Karar KararTests LICENSE NOTICE
git commit -m "Scaffold Karar app with embedded Ollaya v0.3.2"
```

---

### Task 2: OllayaClient — liveness, version, tags

**Files:**
- Create: `Karar/OllayaAPI.swift` (Codable types)
- Create: `Karar/OllayaClient.swift`
- Test: `KararTests/OllayaClientTests.swift`

**Interfaces:**
- Produces:
  - `enum Liveness: Equatable, Sendable { case ollaya, other, none }`
  - `struct OllayaClient: Sendable` with `static let local`, `let base: URL`,
    `func liveness() async -> Liveness`, `func version() async throws -> String`,
    `func tags() async throws -> [ModelInfo]`,
    `static func classify(status: Int, body: Data) -> Liveness`,
    `static func check(_ response: URLResponse, _ data: Data) throws`,
    `static let decoder: JSONDecoder` (snake_case → camelCase).
  - `struct ModelInfo: Decodable, Hashable, Sendable { name: String; size: Int64; details: Details }`,
    `ModelInfo.Details { format: String; family: String; parameterSize: String }`
  - `struct OllayaError: Error, Decodable, Sendable, LocalizedError { error: String; code: String? }`

- [ ] **Step 1: Write the failing tests**

`KararTests/OllayaClientTests.swift` (fixtures are the examples from Ollaya `docs/api.md` §4.1, §7.2, §7.4):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `<test command>`
Expected: build fails with `cannot find 'OllayaClient' in scope`.

- [ ] **Step 3: Implement**

`Karar/OllayaAPI.swift`:

```swift
import Foundation

// Wire types from Ollaya docs/api.md (pinned tag). Only the fields Karar reads.

struct VersionResponse: Decodable, Sendable {
    let version: String
}

struct TagsResponse: Decodable, Sendable {
    let models: [ModelInfo]
}

struct ModelInfo: Decodable, Hashable, Sendable {
    let name: String
    let size: Int64
    let details: Details

    struct Details: Decodable, Hashable, Sendable {
        let format: String
        let family: String
        let parameterSize: String
    }
}

struct OllayaError: Error, Decodable, Sendable, LocalizedError {
    let error: String
    let code: String?

    var errorDescription: String? { error }
}
```

`Karar/OllayaClient.swift`:

```swift
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
```

If Swift 6 reports `static property 'decoder' is not concurrency-safe`, declare it
`nonisolated(unsafe) static let decoder` (it is never mutated after creation).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `<test command>`
Expected: `Executed 7 tests, with 0 failures` (6 new + the smoke test).

- [ ] **Step 5: Check against a real daemon**

Run:
```sh
(OLLAYA_HOST=127.0.0.1:11499 OLLAYA_MODELS=$(mktemp -d) vendor/ollaya/bin/ollaya serve >/dev/null 2>&1 & echo $! > /tmp/karar-ollaya.pid)
sleep 1; curl -s localhost:11499/; echo; curl -s localhost:11499/api/tags; echo
kill $(cat /tmp/karar-ollaya.pid)
```
Expected: `Ollaya is running` and `{"models":[]}`, the shapes the tests assume.

- [ ] **Step 6: Commit**

```bash
git add Karar/OllayaAPI.swift Karar/OllayaClient.swift KararTests/OllayaClientTests.swift
git commit -m "Add OllayaClient: liveness, version, tags"
```

---

### Task 3: Daemon — adopt, start, restart once, stop

**Files:**
- Create: `Karar/Daemon.swift`
- Test: `KararTests/DaemonTests.swift`

**Interfaces:**
- Consumes: `Liveness`, `OllayaClient.local.liveness()` (Task 2).
- Produces:
  - `@MainActor @Observable final class Daemon`
  - `enum Daemon.State: Equatable { case starting, running(owned: Bool), failed(String) }`
  - `typealias Daemon.Probe = @MainActor () async -> Liveness`
  - `typealias Daemon.Launch = @MainActor (_ onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void`
    (launches the process, returns a closure that terminates it and waits)
  - `init(probe: @escaping Probe, launch: @escaping Launch, readyTimeout: Duration = .seconds(10))`
  - `private(set) var state: State`, `func start() async`, `func stop()`
  - `static func bundledLaunch(onExit:) throws -> @MainActor () -> Void` (production launcher, main-actor isolated like the class)

Behaviour (spec §4):
- `start()`: probe. `.ollaya` → `.running(owned: false)` (adopted, never stopped).
  `.other` → `.failed("Port 11435 is in use by another program.")`.
  `.none` → launch, poll the probe every 100 ms until `.ollaya` → `.running(owned: true)`;
  after `readyTimeout` terminate it and `.failed("Ollaya did not start within 10 seconds.")`.
- Owned process exits while `.running` → relaunch once; a second exit, or an exit during
  startup → `.failed("Ollaya stopped unexpectedly (exit code N).")`.
- `stop()`: terminate the owned process; its exit afterwards is ignored.

- [ ] **Step 1: Write the failing tests**

`KararTests/DaemonTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `<test command>`
Expected: build fails with `cannot find 'Daemon' in scope`.

- [ ] **Step 3: Implement**

`Karar/Daemon.swift`:

```swift
import Foundation
import Observation

/// Owns the connection to the Ollaya daemon: adopts one that is already running,
/// or starts the bundled binary and stops it again on quit.
@MainActor @Observable
final class Daemon {
    enum State: Equatable {
        case starting
        case running(owned: Bool)
        case failed(String)
    }

    typealias Probe = @MainActor () async -> Liveness
    typealias Launch = @MainActor (_ onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void

    private(set) var state: State = .starting

    private let probe: Probe
    private let launch: Launch
    private let readyTimeout: Duration
    private var terminate: (@MainActor () -> Void)?
    private var restarts = 0

    init(probe: @escaping Probe, launch: @escaping Launch, readyTimeout: Duration = .seconds(10)) {
        self.probe = probe
        self.launch = launch
        self.readyTimeout = readyTimeout
    }

    func start() async {
        restarts = 0
        state = .starting
        switch await probe() {
        case .ollaya: state = .running(owned: false)
        case .other: state = .failed("Port 11435 is in use by another program.")
        case .none: await launchAndWait()
        }
    }

    func stop() {
        let terminate = self.terminate
        self.terminate = nil   // cleared first so the exit it causes is ignored
        terminate?()
    }

    private func launchAndWait() async {
        state = .starting
        do {
            terminate = try launch { [weak self] status in
                Task { @MainActor in self?.processExited(status) }
            }
        } catch {
            state = .failed("Could not start Ollaya: \(error.localizedDescription)")
            return
        }
        let deadline = ContinuousClock.now + readyTimeout
        while ContinuousClock.now < deadline {
            if terminate == nil { return }   // exited during startup; processExited set the state
            if await probe() == .ollaya {
                state = .running(owned: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        stop()
        state = .failed("Ollaya did not start within \(Int(readyTimeout.components.seconds)) seconds.")
    }

    private func processExited(_ status: Int32) {
        guard terminate != nil else { return }   // stopped on purpose
        terminate = nil
        if case .running = state, restarts == 0 {
            restarts += 1
            Task { await launchAndWait() }
        } else {
            state = .failed("Ollaya stopped unexpectedly (exit code \(status)).")
        }
    }
}

extension Daemon {
    /// Starts `Contents/MacOS/ollaya serve`, logging to ~/Library/Logs/Karar/ollaya.log.
    // ponytail: if Karar crashes the daemon is orphaned; the next launch adopts it and never stops it.
    static func bundledLaunch(onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ollaya") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/Karar")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appending(path: "ollaya.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)   // fresh log per launch
        let log = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
        return {
            process.terminate()
            process.waitUntilExit()
        }
    }
}
```

Note for the timeout message: with the default 10 s it reads "within 10 seconds"; the test only
checks the prefix because the test timeout is 300 ms.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `<test command>`
Expected: `Executed 14 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Karar/Daemon.swift KararTests/DaemonTests.swift
git commit -m "Add Daemon: adopt, start, restart once, stop"
```

---

### Task 4: Status window wired to the real daemon

**Files:**
- Modify: `Karar/KararApp.swift`
- Create: `Karar/StatusView.swift`

**Interfaces:**
- Consumes: `Daemon`, `Daemon.bundledLaunch`, `OllayaClient.local` (`liveness`, `version`, `tags`), `ModelInfo`.
- Produces: nothing later phases call; Phase 2 replaces `StatusView` with the main window.

- [ ] **Step 1: Write `Karar/StatusView.swift`**

```swift
import SwiftUI

/// Phase 1 window: engine status and installed models.
struct StatusView: View {
    let daemon: Daemon
    @State private var version = ""
    @State private var models: [ModelInfo] = []

    var body: some View {
        Group {
            switch daemon.state {
            case .starting:
                ProgressView("Starting Ollaya…")
            case .running(let owned):
                List {
                    Section {
                        LabeledContent("Engine", value: "Ollaya \(version)")
                        LabeledContent("Mode", value: owned ? "Started by Karar" : "Already running")
                    }
                    Section("Installed models") {
                        if models.isEmpty {
                            Text("No models yet. Run `ollaya pull laya` in Terminal.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(models, id: \.name) { model in
                            LabeledContent(model.name, value: model.details.parameterSize)
                        }
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Ollaya is not running", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await daemon.start() } }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task(id: daemon.state) {
            guard case .running = daemon.state else { return }
            version = (try? await OllayaClient.local.version()) ?? ""
            models = (try? await OllayaClient.local.tags()) ?? []
        }
    }
}
```

- [ ] **Step 2: Replace `Karar/KararApp.swift`**

```swift
import SwiftUI

@main
struct KararApp: App {
    @State private var daemon = Daemon(
        probe: { await OllayaClient.local.liveness() },
        launch: Daemon.bundledLaunch
    )

    var body: some Scene {
        WindowGroup {
            StatusView(daemon: daemon)
                .task {
                    // Unit tests are hosted in the app; don't start a real engine under them.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await daemon.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    daemon.stop()
                }
        }
    }
}
```

- [ ] **Step 3: Build and run the tests**

Run: `<test command>`
Expected: `Executed 14 tests, with 0 failures`, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Manual check — Karar starts and stops its own engine**

Make sure nothing listens: `curl -s localhost:11435/ || echo free` → `free`.
Run: `open build/Build/Products/Debug/Karar.app`, wait 2 s, then:
```sh
pgrep -fl 'Karar.app/Contents/MacOS/ollaya serve'
curl -s localhost:11435/
```
Expected: one `ollaya serve` process; `Ollaya is running`; the window shows
"Ollaya 0.3.2", "Started by Karar", and the installed models (or the empty hint).
Quit Karar (⌘Q), then `pgrep -fl 'ollaya serve' || echo stopped` → `stopped`.

- [ ] **Step 5: Manual check — Karar adopts a CLI daemon and leaves it running**

```sh
vendor/ollaya/bin/ollaya serve >/dev/null 2>&1 & echo $! > /tmp/karar-cli.pid
sleep 1; open build/Build/Products/Debug/Karar.app
```
Expected: window shows "Already running"; `pgrep -fl 'Karar.app/Contents/MacOS/ollaya'` prints
nothing. Quit Karar; `curl -s localhost:11435/` still prints `Ollaya is running`.
Clean up: `kill $(cat /tmp/karar-cli.pid)`.

- [ ] **Step 6: Manual check — port used by something else**

```sh
python3 -m http.server 11435 >/dev/null 2>&1 & echo $! > /tmp/karar-py.pid
sleep 1; open build/Build/Products/Debug/Karar.app
```
Expected: "Ollaya is not running" / "Port 11435 is in use by another program." with Retry.
Quit Karar; `kill $(cat /tmp/karar-py.pid)`; relaunch Karar → it starts its own engine.

- [ ] **Step 7: Commit and close the phase**

Tick Phase 1 in `docs/superpowers/plans/2026-09-24-karar-roadmap.md` (`- [x]`) and add any
surprises under "Notes for later phases".

```bash
git add Karar/KararApp.swift Karar/StatusView.swift docs/superpowers/plans/2026-09-24-karar-roadmap.md
git commit -m "Show engine status and installed models; Phase 1 done"
```
