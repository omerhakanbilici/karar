# Phase 5 — Polish: errors, About, icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every row of spec §5 shows the specified UI (engine banner with Restart, port-in-use
banner, pull errors with Retry, deleted-model fallback), plus an About window (spec §3.3), an app
icon, empty states, a few keyboard shortcuts, and every screen checked in light and dark.

**Architecture:** `Daemon.State` gains `.portInUse`; the log rotates; `liveness()` stops calling a
slow answer "another program". `AppModel` learns to show a failed `/api/tags` (`modelsError`), to
clear a selection deleted outside Karar (`missingModel`), to leave onboarding when the CLI adds a
model, to ask again after an engine restart, to word pull errors by code, and to preload the
selected model with a longer `keep_alive`. A new `ErrorBanner` sits at the top of the detail
column. `AboutView` is a second `Window` scene opened from the app menu. The icon is drawn by a
small Swift script into `Karar/Assets.xcassets`.

**Tech Stack:** Swift 6, SwiftUI, Foundation, CoreGraphics (icon script only), XCTest, XcodeGen, Xcode 27.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. No third-party Swift dependencies.
  SwiftUI + Foundation only; AppKit only where SwiftUI lacks it (already: `NSPasteboard`,
  `NSApp.applicationIconImage`, window growth in `MainView`).
- Bundle ID `io.github.omerhakanbilici.karar`. Hardened Runtime on. Ad-hoc signing.
- Ollaya pinned to `v0.3.2`; HTTP contract: `https://github.com/ollaya-dev/ollaya/blob/v0.3.2/docs/api.md`
  (§4.1–4.3 error body, codes, errors inside a stream; §6 `keep_alive`; §7.3 "Load and unload";
  §7.6 pull errors before/after the stream starts; §10 cancellation). Not `main`.
- System semantic colours only (`.primary`, `.secondary`, `.tertiary`, `.quinary`, `.tint`,
  `.separator`, `.bar`, materials, `Color(nsColor: .textBackgroundColor)`). **Two exceptions only**
  (spec §4): `.orange` for the truncation warning, `.red` for a question card with a validation
  error. The error banner uses neither. The app icon's orange is artwork, not UI colour.
- UI text in English. "Ollaya" only descriptively; About says Karar is not affiliated with it.
- `project.yml` is the source of truth; run `xcodegen generate` after editing it and commit both.
  New files under `Karar/` or `KararTests/` need no project change (synced folders).
- The engine is started only by `AppDelegate` (and by the user's own Retry / Restart / Try Again
  buttons, which call `app.daemon.start()`), and stopped only in `applicationWillTerminate`.
  `AppModel` keeps taking the `Daemon` from `AppDelegate`. No view starts it on its own.
- Never touch the user's model store `~/.ollaya`. Real engine runs use `OLLAYA_MODELS=<scratch>`.
  The user's CLI daemon (`/usr/local/bin/ollaya serve`) may listen on 11435 and Karar adopts it;
  **ask the user before stopping it**, and restart it the same way afterwards.
- The icon is shown to the user **before** it is committed.

Test command used throughout (from repo root; needs `vendor/ollaya`, run `scripts/fetch-ollaya.sh` once):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

One test class: add `-only-testing:KararTests/<ClassName>` before `test`.

**UI check** (after every UI task; the controller does this, never a subagent):

```sh
S=<scratchpad>        # $S/models holds laya, laya:en, laya:multilingual (cloned from Phase 4's scratch)
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '
osascript -e 'tell application id "io.github.omerhakanbilici.karar" to quit'; sleep 2; pgrep -x Karar; pgrep -lf "ollaya serve"
# never pkill Karar: SIGTERM skips applicationWillTerminate and orphans its ollaya. Quit fails while a sheet is open.
APP=build/Build/Products/Debug/Karar.app/Contents/MacOS/Karar
OLLAYA_MODELS=$S/models $APP -ApplePersistenceIgnoreState YES -KararAppearance light -KararText "…" &
#   dark: -KararAppearance dark ; advanced: -advanced YES ; custom set: -KararQuestions '{…}'
#   size: "-NSWindow Frame main" "x y w h 0 0 <screen w> <screen h>"
cat > $S/winid.swift <<'EOF'
import CoreGraphics
// Karar's widest on-screen window, or the one whose title is the first argument.
let title = CommandLine.arguments.dropFirst().first
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let karar = list.filter { $0[kCGWindowOwnerName as String] as? String == "Karar" && $0[kCGWindowLayer as String] as? Int == 0
    && (title == nil || $0[kCGWindowName as String] as? String == title) }
let widest = karar.max { (($0[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) < (($1[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) }
print(widest?[kCGWindowNumber as String] as? Int ?? 0)
EOF
sleep 5; screencapture -x -o -l $(swift $S/winid.swift) $S/shot.png    # About: swift $S/winid.swift "About Karar"
```

Capture only Karar's windows, never the full screen. Clicking or typing needs the user (no
Accessibility): ask, and while they do it take one frame a second in the background and compare
the frames. Judge every capture: alignment, spacing, cramped or raw-looking parts, rows that
disappear or jump in an empty state, line breaks in live-updating text, light and dark.

## Facts measured before writing this plan

- The user's CLI daemon was **not** running at the start of this session (nothing on 11435), so
  Karar starts its own `ollaya` and the §5 engine cases can be reproduced without stopping it.
  Re-check with `lsof -nP -iTCP:11435 -sTCP:LISTEN` before each manual step.
- Pull errors before the stream can be produced through Karar's own daemon with `OLLAYA_REGISTRY`
  in Karar's environment (it reaches the child):
  - `OLLAYA_REGISTRY=http://127.0.0.1:8123` with `python3 -m http.server 8123` in an empty dir →
    `404 {"error":"model \"laya:en\" not found in registry http://127.0.0.1:8123","code":"MODEL_NOT_FOUND"}`;
  - `OLLAYA_REGISTRY=http://127.0.0.1:9` (nothing listens) → `502 REGISTRY_ERROR` (to confirm in Task 7).
- `vendor/ollaya/share/doc/ollaya/` (copied to `Contents/Resources/Ollaya/`) holds `LICENSE`
  (10 kB), `THIRD_PARTY_NOTICES` (550 kB) and `onnxruntime-ThirdPartyNotices.txt` (325 kB). Karar's
  own `LICENSE` and `NOTICE` are not in the bundle yet.
- `https://ollaya.dev` answers `200 text/html`.

## Design decisions (no user input needed)

- **Deleted outside Karar** (spec §5): when a refresh no longer lists the selected model, the
  selection becomes empty (not the first model: answers would silently change model) and
  `missingModel` remembers the name. The results area says "`<name>` is no longer installed." with
  "Download model…"; the toolbar reads "Choose a model". If that model comes back, it is selected
  again. A model deleted **in** Karar still hands the selection to the first model left (the user
  chose to delete it). A `404 MODEL_NOT_FOUND` from `/api/decide` triggers a refresh, so deletion
  shows even while Karar stays in front.
- **Engine banner** (spec §5): across the top of the detail column, `.bar` background, a
  `.secondary` triangle, title, message, buttons. Daemon failed → "Show Log" + "Restart"; port in
  use → how to free it + "Try Again"; `/api/tags` failing → "Try Again". Below it, the window keeps
  what it has (the editor and last models), or a "No models" empty state that says models appear
  once Karar can reach Ollaya.
- **Stale error after an automatic restart:** `connect()` runs after every (re)start and asks the
  engine again, so the old error goes away without an edit.
- **Liveness:** the probe's timeout goes from 1 s to 5 s. A connection refused still answers at
  once; only a listener that accepts and never answers waits. That listener is still "port in use".
- **`ollaya.log`:** past 10 MB at launch it becomes `ollaya.log.1` (one old file kept).
- **Cold starts:** every `/api/decide` carries `"keep_alive": "30m"` (docs/api.md §6; default 5m),
  and picking a model (or reconnecting) sends a load request for it (§7.3 "Load and unload"). The
  copied curl includes `keep_alive` too: it is the request Karar sends.
- **Onboarding and the CLI:** a refresh that finds models while onboarding ends onboarding, unless
  one of Karar's own downloads is running or finished (then "Get started" stays the way out).
- **Pull errors** keep the existing inline row + Retry (sheet) and label + Retry (onboarding); the
  text is worded by code: `REGISTRY_ERROR`, `DIGEST_MISMATCH`, `STORAGE_ERROR`, `MODEL_NOT_FOUND`,
  a lost connection to Ollaya; anything else shows the engine's message.
- **Keyboard shortcuts:** ⌥⌘I Advanced (Apple's inspector shortcut), ⇧⌘D Download model… (sidebar
  button), Esc closes the download sheet and the licence sheet. ⌘↩ (pin) exists.
- **About** (spec §3.3): icon, name, "A Mac app for Ollaya", version (build), engine (bundled
  version + what is running), licences (Karar Apache-2.0: LICENSE, NOTICE; Ollaya Apache-2.0:
  LICENSE, third-party notices, ONNX Runtime notices; models grouped by licence from
  `Catalog.json`), links (Karar on GitHub, ollaya.dev), "not affiliated" line. Licence texts open
  in a sheet, drawn lazily line by line (the notices are half a megabyte).
- **Icon:** a plain balance scale, beam tilted ~7° so the left pan hangs lower, no sword or
  blindfold, white on an orange gradient plate (macOS icon grid: 824 pt plate with 185 pt corners
  on a 1024 canvas, soft shadow). Drawn by `scripts/make-icon.swift` (committed, so the icon can be
  re-rendered) into `Karar/Assets.xcassets/AppIcon.appiconset` (10 PNGs, 16–1024 px).

## File structure

| File | Change |
|---|---|
| `Karar/Daemon.swift` | `.portInUse`, `State.isRunning`, `logURL`, `rotateLog(at:limit:)` |
| `Karar/OllayaClient.swift` | 5 s liveness timeout, `keepAlive`, `keep_alive` in `decideBody`, `load(model:)` |
| `Karar/AppModel.swift` | `modelsError`, `missingModel`, refresh ordering, onboarding exit, `connect()` re-runs, `MODEL_NOT_FOUND` refresh, in-app delete, `pullMessage`, `load` preload |
| `Karar/KararApp.swift` | `load` wiring, About `Window` + menu command |
| `Karar/Views/RootView.swift` | routes `.portInUse` and a failed first refresh to `MainView` |
| `Karar/Views/ErrorBanner.swift` | new: the banner |
| `Karar/Views/MainView.swift` | banner, detail states, missing-model note, "Choose a model", shortcuts |
| `Karar/Views/DownloadSheet.swift` | Esc closes |
| `Karar/Views/AboutView.swift` | new: About + licence sheet |
| `project.yml` (+ `Karar.xcodeproj`) | copy `LICENSE`/`NOTICE` into Resources; `ASSETCATALOG_COMPILER_APPICON_NAME` |
| `scripts/make-icon.swift`, `Karar/Assets.xcassets/**` | new: icon |
| `KararTests/DaemonTests.swift`, `OllayaClientTests.swift`, `AppModelTests.swift`, `AboutTests.swift` | tests |
| `docs/superpowers/plans/2026-09-24-karar-roadmap.md` | tick Phase 5, notes |

---

### Task 1: Daemon states, log rotation, liveness timeout, keep_alive and load

**Files:**
- Modify: `Karar/Daemon.swift`
- Modify: `Karar/OllayaClient.swift`
- Modify: `Karar/Views/RootView.swift` (routing only)
- Modify: `Karar/Views/MainView.swift` (one temporary `case`, replaced in Task 4)
- Test: `KararTests/DaemonTests.swift`, `KararTests/OllayaClientTests.swift`

**Interfaces:**
- Produces: `Daemon.State.portInUse`; `Daemon.State.isRunning: Bool`; `Daemon.logURL: URL`
  (nonisolated static); `Daemon.rotateLog(at: URL, limit: Int)` (nonisolated static);
  `OllayaClient.keepAlive: String` (`"30m"`); `OllayaClient.load(model: String) async throws`.

- [ ] **Step 1: Write the failing tests**

In `KararTests/DaemonTests.swift`, replace `testReportsWhenAnotherProgramHasThePort` and add two tests:

```swift
    func testReportsWhenAnotherProgramHasThePort() async {
        let daemon = makeDaemon(FakeEngine(), probe: { .other })
        await daemon.start()
        XCTAssertEqual(daemon.state, .portInUse)
        XCTAssertFalse(daemon.state.isRunning)
    }

    func testTheLogRotatesPastItsLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appending(path: "ollaya.log")
        try Data("old old old old".utf8).write(to: log)

        Daemon.rotateLog(at: log, limit: 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path), "under the limit: kept")

        Daemon.rotateLog(at: log, limit: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertEqual(try String(contentsOf: dir.appending(path: "ollaya.log.1"), encoding: .utf8), "old old old old")

        try Data("newer, and long enough".utf8).write(to: log)
        Daemon.rotateLog(at: log, limit: 10)
        XCTAssertEqual(try String(contentsOf: dir.appending(path: "ollaya.log.1"), encoding: .utf8),
                       "newer, and long enough", "only one old log is kept")
    }

    func testTheLogLivesInLibraryLogs() {
        XCTAssertTrue(Daemon.logURL.path.hasSuffix("Library/Logs/Karar/ollaya.log"), Daemon.logURL.path)
    }
```

In `KararTests/OllayaClientTests.swift`, add to `testDecideBodySplicesQuestionsVerbatim` (after the `state` assertion):

```swift
        XCTAssertEqual(object["keep_alive"] as? String, "30m")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: the test command with `-only-testing:KararTests/DaemonTests -only-testing:KararTests/OllayaClientTests`
Expected: build errors (`portInUse`, `isRunning`, `rotateLog`, `logURL` not found).

- [ ] **Step 3: Implement**

`Karar/Daemon.swift` — the state:

```swift
    enum State: Equatable {
        case starting
        case running(owned: Bool)
        case portInUse         // something that is not Ollaya answers on 11435 (spec §5)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { true } else { false }
        }
    }
```

In `start()`: `case .other: state = .portInUse`.

In the extension, add above `bundledLaunch`:

```swift
    /// Where a daemon Karar starts writes its output.
    nonisolated static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Karar/ollaya.log")

    /// Keeps the log bounded: past `limit` bytes it becomes `<name>.1`, replacing an older one.
    nonisolated static func rotateLog(at url: URL, limit: Int) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > limit else { return }
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
```

In `bundledLaunch`, replace the lines from `let logs = …` through `let logURL = logs.appending(path: "ollaya.log")` with:

```swift
        let logURL = logURL
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateLog(at: logURL, limit: 10_000_000)
```

and update its doc comment to "…logging to `logURL` (~/Library/Logs/Karar/ollaya.log)."

`Karar/OllayaClient.swift`:
- `liveness()`: `request.timeoutInterval = 5` with the comment
  `// A refused connection fails at once; only a listener that never answers waits this long.`
- Add under `static let decoder`:

```swift
    /// How long the engine keeps a model loaded after a request (docs/api.md §6). The default is 5m;
    /// reloading costs 2.5–3.3 s, so a longer pause in typing shouldn't pay it.
    static let keepAlive = "30m"
```

- `decideBody`: insert `keep_alive` after the model:

```swift
        Data(#"{"model":"#.utf8) + (try JSONEncoder().encode(model))
            + Data(#","keep_alive":"#.utf8) + (try JSONEncoder().encode(keepAlive))
            + Data(#","state":"#.utf8) + (try stateJSON(state))
            + Data(#","questions":"#.utf8) + questions + Data("}".utf8)
```

- Add after `decide`:

```swift
    /// Loads a model before the first question (docs/api.md §7.3 "Load and unload": no `state`,
    /// no `questions`), so the first answer doesn't wait for the load.
    func load(model: String) async throws {
        var request = URLRequest(url: base.appending(path: "api/decide"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": model, "keep_alive": Self.keepAlive])
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, data)
    }
```

`Karar/Views/RootView.swift`: replace `if case .failed = app.daemon.state {` with

```swift
            if !app.daemon.state.isRunning, app.daemon.state != .starting {
```

and its comment with "A daemon that failed or found the port taken needs MainView's banner even
mid-onboarding, so it is checked first."

`Karar/Views/MainView.swift` (temporary, Task 4 replaces the whole switch): add to `detail`'s switch, after the `.failed` case:

```swift
        case .portInUse:
            ContentUnavailableView("Port 11435 is in use by another program", systemImage: "exclamationmark.triangle")
```

- [ ] **Step 4: Run the full test suite**

Run: the test command. Expected: all tests pass (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**

```bash
git add Karar/Daemon.swift Karar/OllayaClient.swift Karar/Views/RootView.swift Karar/Views/MainView.swift KararTests/DaemonTests.swift KararTests/OllayaClientTests.swift
git commit -m "Report a taken port as its own state, rotate ollaya.log, keep models loaded longer"
```

---

### Task 2: AppModel — failed refreshes, deleted models, onboarding exit, reconnect

**Files:**
- Modify: `Karar/AppModel.swift`
- Test: `KararTests/AppModelTests.swift`

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces: `AppModel.modelsError: String?` (private(set)); `AppModel.missingModel: String?`
  (private(set)); `connect()` now re-runs the current input; `delete(_ name: String)`.

- [ ] **Step 1: Write the failing tests**

In `FakeOllaya` add a property and use it in `tags()`:

```swift
    var tagsFailure: Error?
```

```swift
    func tags() async throws -> [ModelInfo] {
        let snapshot = installed
        let delay = tagsDelays.isEmpty ? .zero : tagsDelays.removeFirst()
        try await Task.sleep(for: delay)
        if let tagsFailure { throw tagsFailure }
        return snapshot.map { ModelInfo(name: $0, size: 1, details: .init(format: "onnx", family: "laya", parameterSize: "")) }
    }
```

Replace the last three lines of `testRefreshModelsKeepsOrReplacesTheSelection` (from `fake.installed = ["laya:en"]`) with:

```swift
        fake.installed = ["laya:en"]
        await app.refreshModels()
        XCTAssertNil(app.model, "deleted outside Karar: no silent switch to another model (spec §5)")
        XCTAssertEqual(app.missingModel, "laya:multilingual")
        fake.installed = ["laya:en", "laya:multilingual"]
        await app.refreshModels()
        XCTAssertEqual(app.model, "laya:multilingual", "it came back: selected again")
        XCTAssertNil(app.missingModel)
```

Add these tests:

```swift
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
        try? await Task.sleep(for: .milliseconds(50))
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
```

(`testDeleteRemovesTheModelAndMovesTheSelection`, `testTheNewestRefreshWins`,
`testADownloadFoldsProgressAndRefreshesOnSuccess` — "stays until Get started" — and
`testGetStartedShowsASampleTicketWithTheNewModel` must keep passing unchanged.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: the test command with `-only-testing:KararTests/AppModelTests`
Expected: build errors (`modelsError`, `missingModel` not found).

- [ ] **Step 3: Implement**

In `AppModel`:

Replace the `model` property:

```swift
    var model: String? {
        didSet {
            guard model != oldValue else { return }
            if model != nil { missingModel = nil }
            run()
        }
    }
```

Add next to `modelsLoaded`:

```swift
    /// Why the last `/api/tags` failed, shown in the window's banner (spec §5); nil once it works.
    private(set) var modelsError: String?
    /// The selected model after it disappeared outside Karar (spec §5); cleared once one is picked.
    private(set) var missingModel: String?
```

Replace `private var refreshes = 0` with:

```swift
    private var refreshes = 0   // refreshModels() calls started
    private var applied = 0     // the newest call whose answer is on screen
```

Replace `connect()` and `refreshModels()`:

```swift
    /// Called whenever the engine becomes ready: at launch and after every (re)start. Asking again
    /// replaces an error left from before an automatic restart (spec §5).
    func connect() async {
        await refreshModels()
        engineVersion = (try? await version()) ?? ""
        run()
    }

    /// Reloads the installed models. The newest call's answer wins; an older one that answers later
    /// is dropped. A failure keeps the list and shows why (spec §5).
    ///
    /// The selection stays while installed. One that disappeared outside Karar is cleared, not
    /// replaced (spec §5), and comes back if the model does. Finding no model starts onboarding
    /// (spec §3.1); finding some ends it, unless one of Karar's own downloads is running or done
    /// (its "Get started" is then the way out).
    func refreshModels() async {
        refreshes += 1
        let call = refreshes
        let fresh: [ModelInfo]
        do {
            fresh = try await tags()
        } catch {
            guard call > applied else { return }
            applied = call
            modelsError = error.localizedDescription
            return
        }
        guard call > applied else { return }
        applied = call
        modelsError = nil
        models = fresh
        modelsLoaded = true
        if fresh.isEmpty {
            isOnboarding = true
        } else if isOnboarding, !downloads.values.contains(where: { $0.error == nil }) {
            isOnboarding = false
        }
        if let model, !fresh.contains(where: { $0.name == model }) {
            missingModel = model
            self.model = nil
        } else if model == nil {
            if let missingModel {
                if fresh.contains(where: { $0.name == missingModel }) { model = missingModel }
            } else {
                model = fresh.first?.name
            }
        }
    }
```

Replace `delete(_:)`:

```swift
    func delete(_ name: String) async {
        do {
            try await deleteModel(name)
            if model == name { model = nil }   // deleted here: the first model left takes over
        } catch {
            deleteError = error.localizedDescription
        }
        await refreshModels()
        // A finished download of the just-deleted model is now stale; drop it so onboarding (or
        // the download sheet) doesn't resume at a download that can never be cancelled or finished.
        downloads = downloads.filter { !$0.value.isFinished }
    }
```

In `run()`, replace the task body's `do { … } catch { … }` and the `isUpdating = false` after it with:

```swift
            do {
                let response = try await decide(model, text, questions)
                guard !Task.isCancelled else { return }
                result = response
                error = nil
                questionErrors = [:]
                isUpdating = false
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                isUpdating = false
                if (error as? OllayaError)?.code == "MODEL_NOT_FOUND" {
                    // Deleted outside Karar (spec §5): the refresh clears the selection, and the
                    // missing-model note replaces this message.
                    self.error = nil
                    await refreshModels()
                } else {
                    show(error)
                }
            }
```

(A router whose *target* is missing also answers `MODEL_NOT_FOUND`; the router is still listed, so
the selection stays and the next edit shows the engine's message again. Acceptable.)

- [ ] **Step 4: Run the full test suite**

Run: the test command. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Karar/AppModel.swift KararTests/AppModelTests.swift
git commit -m "Show failed model refreshes, clear a model deleted outside Karar, ask again after a restart"
```

---

### Task 3: Pull error wording and model preload

**Files:**
- Modify: `Karar/AppModel.swift`
- Modify: `Karar/KararApp.swift` (wiring)
- Test: `KararTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `OllayaClient.load(model:)` (Task 1).
- Produces: `AppModel.Load` typealias; `init(…, delete:, load: @escaping Load = { _ in }, debounce:)`;
  `static func pullMessage(_ error: Error) -> String`.

- [ ] **Step 1: Write the failing tests**

In `FakeOllaya` add:

```swift
    var loads: [String] = []

    func load(_ model: String) async throws { loads.append(model) }
```

In `makeApp`, pass it: `pull: fake.pull, delete: fake.delete, load: fake.load, debounce: .milliseconds(50))`.

Add tests:

```swift
    func testPullErrorsAreWordedByCode() {
        func message(_ code: String?, _ text: String = "raw") -> String {
            AppModel.pullMessage(OllayaError(error: text, code: code))
        }
        XCTAssertEqual(message("REGISTRY_ERROR"), "Could not reach the model registry. Check your internet connection.")
        XCTAssertEqual(message("DIGEST_MISMATCH"), "A downloaded file was damaged and has been discarded.")
        XCTAssertEqual(message("STORAGE_ERROR", "No space left on device"), "Could not save the model: No space left on device")
        XCTAssertEqual(message("MODEL_NOT_FOUND"), "This model is not in the registry.")
        XCTAssertEqual(message(nil, "The download was interrupted."), "The download was interrupted.")
        XCTAssertEqual(message("SOMETHING_NEW", "engine words"), "engine words", "unknown codes fall back to the message")
        XCTAssertEqual(AppModel.pullMessage(URLError(.networkConnectionLost)), "Lost the connection to Ollaya.")
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

    func testPickingAModelPreloadsIt() async {
        let fake = FakeOllaya()
        let app = makeApp(fake)
        app.model = "laya:multilingual"
        await waitUntil { fake.loads.last == "laya:multilingual" }
        fake.loads = []
        await app.connect()                                    // after an engine restart
        await waitUntil { fake.loads == ["laya:multilingual"] }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: the test command with `-only-testing:KararTests/AppModelTests`
Expected: build errors (`load:` argument, `pullMessage` not found).

- [ ] **Step 3: Implement**

In `AppModel`:

```swift
    typealias Load = @MainActor (_ model: String) async throws -> Void
```

a stored `private let load: Load`, and the init gains `load: @escaping Load = { _ in },` between
`delete:` and `debounce:` (assign `self.load = load`).

`model`'s `didSet` becomes:

```swift
        didSet {
            guard model != oldValue else { return }
            if model != nil { missingModel = nil }
            preload()
            run()
        }
```

`connect()` calls `preload()` right before `run()`.

Add, next to `run()`:

```swift
    /// Loads the selected model in the background (docs/api.md §7.3), so the first answer after
    /// picking it, or after an engine restart, doesn't wait 2.5–3.3 s for the load. Best effort.
    private func preload() {
        guard let model else { return }
        Task { try? await load(model) }
    }
```

In `download(_:)`, the catch becomes `downloads[name]?.error = Self.pullMessage(error)`, and add:

```swift
    /// A failed pull's text on its row (spec §5), by error code (docs/api.md §4.2, §7.6).
    static func pullMessage(_ error: Error) -> String {
        if error is URLError { return "Lost the connection to Ollaya." }
        guard let error = error as? OllayaError else { return error.localizedDescription }
        switch error.code {
        case "REGISTRY_ERROR": return "Could not reach the model registry. Check your internet connection."
        case "DIGEST_MISMATCH": return "A downloaded file was damaged and has been discarded."
        case "STORAGE_ERROR": return "Could not save the model: \(error.error)"
        case "MODEL_NOT_FOUND": return "This model is not in the registry."
        default: return error.error
        }
    }
```

In `Karar/KararApp.swift`, `AppDelegate.init` passes
`load: { try await client.load(model: $0) }` after `delete:`.

- [ ] **Step 4: Run the full test suite**

Run: the test command. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Karar/AppModel.swift Karar/KararApp.swift KararTests/AppModelTests.swift
git commit -m "Word pull errors by code; preload the selected model"
```

---

### Task 4: Error banner, empty states, keyboard shortcuts

**Files:**
- Create: `Karar/Views/ErrorBanner.swift`
- Modify: `Karar/Views/MainView.swift`
- Modify: `Karar/Views/RootView.swift`
- Modify: `Karar/Views/DownloadSheet.swift`

**Interfaces:**
- Consumes: `Daemon.State.portInUse`, `.isRunning`, `Daemon.logURL` (Task 1);
  `AppModel.modelsError`, `.missingModel`, `refreshModels()` (Task 2).
- Produces: `ErrorBanner(title:message:actions:)`.

No unit tests (views); the controller's UI check covers it.

- [ ] **Step 1: The banner**

`Karar/Views/ErrorBanner.swift`:

```swift
import SwiftUI

/// A problem with the engine, across the top of the window (spec §5): what happened, what to do,
/// and the buttons that do it. System colours only (spec §4).
struct ErrorBanner<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
```

- [ ] **Step 2: MainView**

Add `@Environment(\.openURL) private var openURL` to `MainView`.

The split view's detail closure becomes:

```swift
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) { banner }
        }
```

Replace the whole `detail` property with:

```swift
    @ViewBuilder private var detail: some View {
        if app.daemon.state == .starting {
            ProgressView("Starting Ollaya…")
        } else if app.models.isEmpty {
            let reachable = app.daemon.state.isRunning && app.modelsError == nil
            ContentUnavailableView {
                Label("No models", systemImage: "shippingbox")
            } description: {
                // Unreachable: the banner above says why.
                Text(reachable ? "Download a model to ask questions about your text."
                               : "Installed models appear here once Karar can reach Ollaya.")
            } actions: {
                if reachable {
                    Button("Download model…") { showsDownloadSheet = true }
                }
            }
        } else {
            VStack(spacing: 0) {
                editor
                    .padding([.horizontal, .top], 20)
                // Always reserve 30 pt for the counter or warning.
                tokenCounter
                    .padding(.horizontal, 20)
                Divider()
                if advanced { cards } else { results }
            }
            .inspector(isPresented: advancedBinding) {
                InspectorView(app: app)
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
            }
        }
    }

    /// Spec §5: the engine failed (message + Restart), the port is taken (how to free it), or the
    /// installed models can't be listed. Retrying is always the user's click.
    @ViewBuilder private var banner: some View {
        switch app.daemon.state {
        case .portInUse:
            ErrorBanner(title: "Port 11435 is in use by another program",
                        message: "Ollaya needs this port. Quit the program that uses it, then click Try Again. "
                            + "To see which program it is, run lsof -i :11435 in Terminal.") {
                Button("Try Again") { Task { await app.daemon.start() } }
            }
        case .failed(let message):
            ErrorBanner(title: "Ollaya is not running", message: message) {
                Button("Show Log") { openURL(Daemon.logURL) }
                Button("Restart") { Task { await app.daemon.start() } }
            }
        case .running where app.modelsError != nil:
            ErrorBanner(title: "Could not load the installed models", message: app.modelsError ?? "") {
                Button("Try Again") { Task { await app.refreshModels() } }
            }
        default:
            EmptyView()
        }
    }

    /// Spec §5: the selected model was deleted outside Karar, so no model is selected.
    private var noModelNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.missingModel.map { "\($0) is no longer installed." } ?? "No model is selected.")
                    .font(.headline)
                Text("Choose a model in the toolbar, or download one.")
                    .foregroundStyle(.secondary)
            }
            Button("Download model…") { showsDownloadSheet = true }
        }
    }
```

In `results`, the first branch of the inner `VStack` becomes:

```swift
                if app.model == nil {
                    noModelNote
                } else if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Answers appear here as you type.")
                        .foregroundStyle(.secondary)
                } else {
```

(the existing `else` body is unchanged). In `cards`, right after `answersHeader`:

```swift
                if app.model == nil { noModelNote }
```

Toolbar:
- Model menu label: `Label(app.model ?? "Choose a model", systemImage: "cpu")`.
- Advanced toggle: add `.keyboardShortcut("i", modifiers: [.command, .option])` and change its help
  to `"Edit the questions and inspect the response (⌥⌘I)"`.

Sidebar "Download model…" button: add `.keyboardShortcut("d", modifiers: [.command, .shift])` and
`.help("Download model… (⇧⌘D)")`.

- [ ] **Step 3: RootView — a failed first refresh shows the window, not a spinner**

```swift
    /// Until models have loaded once, a full-window spinner stands in for `MainView`, unless that
    /// load failed: `MainView`'s banner then says why. (A failed daemon never reaches here.)
    private var showsStartupProgress: Bool { !app.modelsLoaded && app.modelsError == nil }
```

- [ ] **Step 4: Esc closes the download sheet**

In `DownloadSheet.body`, after `.frame(width: 600, height: 540)`: `.onExitCommand { dismiss() }`.

- [ ] **Step 5: Build and run the full test suite**

Run: the test command. Expected: all tests pass, no warnings in the changed files.

- [ ] **Step 6: Commit**

```bash
git add Karar/Views/ErrorBanner.swift Karar/Views/MainView.swift Karar/Views/RootView.swift Karar/Views/DownloadSheet.swift
git commit -m "Engine banner, missing-model and no-engine empty states, keyboard shortcuts"
```

- [ ] **Step 7 (controller): UI check** — light and dark: main window with a result, the
  no-model note (`OLLAYA_MODELS` store where the selected model is deleted with
  `OLLAYA_HOST=127.0.0.1:11435 vendor/ollaya/bin/ollaya rm laya:en` while Karar runs its own
  daemon), the port banner (`python3 -m http.server 11435` in an empty dir, then launch Karar),
  the crash banner (see Task 7). Fix what looks off before moving on.

---

### Task 5: About window

**Files:**
- Create: `Karar/Views/AboutView.swift`
- Modify: `Karar/KararApp.swift`
- Modify: `project.yml` (then `xcodegen generate`; commit `Karar.xcodeproj` too)
- Test: `KararTests/AboutTests.swift`

**Interfaces:**
- Consumes: `Daemon.bundledVersion`, `AppModel.engineVersion`, `app.daemon.state`, `CatalogEntry.all`.
- Produces: `AboutView(app:)`, `AboutView.modelLicences: [(licence: String, models: [String])]`.

- [ ] **Step 1: Write the failing test**

`KararTests/AboutTests.swift`:

```swift
import XCTest
@testable import Karar

final class AboutTests: XCTestCase {
    func testModelLicencesComeFromTheCatalog() {
        let licences = AboutView.modelLicences
        XCTAssertEqual(licences.map(\.licence), ["Apache-2.0", "MIT"])
        XCTAssertEqual(licences.first?.models.first, "laya", "catalog order")
        XCTAssertEqual(licences.last?.models, ["nli"])
    }

    func testTheLicenceTextsShipInTheApp() {
        for (name, dir) in [("LICENSE", nil), ("NOTICE", nil), ("LICENSE", "Ollaya"),
                            ("THIRD_PARTY_NOTICES", "Ollaya"), ("onnxruntime-ThirdPartyNotices.txt", "Ollaya")] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil, subdirectory: dir), "\(dir ?? "")/\(name)")
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: the test command with `-only-testing:KararTests/AboutTests`
Expected: build error (`AboutView` not found).

- [ ] **Step 3: Bundle Karar's LICENSE and NOTICE**

In `project.yml`, the "Embed Ollaya" script, add as its last line:

```sh
          cp "$SRCROOT/LICENSE" "$SRCROOT/NOTICE" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"
```

Run: `xcodegen generate`

- [ ] **Step 4: AboutView**

`Karar/Views/AboutView.swift`:

```swift
import SwiftUI

/// About Karar (spec §3.3): versions, links, and the licences of Karar, Ollaya and the models.
struct AboutView: View {
    let app: AppModel
    @State private var shown: Licence?

    struct Licence: Identifiable {
        let title: String
        let url: URL?
        var id: String { url?.path ?? title }
    }

    /// Catalog models grouped by licence, licences and models in catalog order.
    static var modelLicences: [(licence: String, models: [String])] {
        var groups: [(licence: String, models: [String])] = []
        for entry in CatalogEntry.all {
            if let index = groups.firstIndex(where: { $0.licence == entry.license }) {
                groups[index].models.append(entry.name)
            } else {
                groups.append((entry.license, [entry.name]))
            }
        }
        return groups
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }()

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("Karar").font(.title.weight(.semibold))
                Text("A Mac app for Ollaya").foregroundStyle(.secondary)
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    label("Engine")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ollaya \(Daemon.bundledVersion), built in")
                        Text(running).font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    label("Karar")
                    licences("Apache-2.0", [
                        Licence(title: "Licence", url: Bundle.main.url(forResource: "LICENSE", withExtension: nil)),
                        Licence(title: "Notice", url: Bundle.main.url(forResource: "NOTICE", withExtension: nil)),
                    ])
                }
                GridRow {
                    label("Ollaya")
                    licences("Apache-2.0", [
                        Licence(title: "Licence", url: ollaya("LICENSE")),
                        Licence(title: "Third-party notices", url: ollaya("THIRD_PARTY_NOTICES")),
                        Licence(title: "ONNX Runtime notices", url: ollaya("onnxruntime-ThirdPartyNotices.txt")),
                    ])
                }
                GridRow {
                    label("Models")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.modelLicences, id: \.licence) { group in
                            Text("\(group.licence): \(group.models.joined(separator: ", "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Each model has its own licence. Ollaya downloads models from their authors; Karar includes none.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 20) {
                Link("Karar on GitHub", destination: URL(string: "https://github.com/omerhakanbilici/karar")!)
                Link("ollaya.dev", destination: URL(string: "https://ollaya.dev")!)
            }
            Text("Karar is not affiliated with the Ollaya project.\n© 2026 Ömer Hakan Bilici")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 440)
        .sheet(item: $shown) { LicenceView(licence: $0) }
    }

    private var running: String {
        switch app.daemon.state {
        case .running(let owned) where !app.engineVersion.isEmpty:
            "v\(app.engineVersion) running, \(owned ? "started by Karar" : "started outside Karar")"
        case .running, .starting: "Starting…"
        case .portInUse, .failed: "Not running"
        }
    }

    private func ollaya(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Ollaya")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func licences(_ name: String, _ files: [Licence]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            HStack(spacing: 12) {
                ForEach(files) { file in
                    Button(file.title) { shown = file }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(file.url == nil)
                }
            }
        }
    }
}

/// One licence text in a sheet. Lines are drawn lazily: the notices run to half a megabyte.
private struct LicenceView: View {
    let licence: AboutView.Licence
    private let lines: [String]
    @Environment(\.dismiss) private var dismiss

    init(licence: AboutView.Licence) {
        self.licence = licence
        let text = licence.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Not found in the app."
        lines = text.components(separatedBy: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(licence.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(lines[index].isEmpty ? " " : lines[index])
                    }
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
        .onExitCommand { dismiss() }
    }
}
```

- [ ] **Step 5: The scene and the menu item**

`Karar/KararApp.swift`, `KararApp.body`:

```swift
    var body: some Scene {
        Window("Karar", id: "main") {
            RootView(app: appDelegate.app)
        }
        .commands {
            CommandGroup(replacing: .appInfo) { AboutButton() }
        }
        Window("About Karar", id: "about") {
            AboutView(app: appDelegate.app)
        }
        .windowResizability(.contentSize)
    }
```

and below `KararApp`:

```swift
/// Karar ▸ About Karar opens the About window instead of the standard panel (spec §3.3).
private struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Karar") { openWindow(id: "about") }
    }
}
```

- [ ] **Step 6: Run the full test suite**

Run: the test command. Expected: all tests pass (the bundle test proves the copy step works).

- [ ] **Step 7: Commit**

```bash
git add Karar/Views/AboutView.swift Karar/KararApp.swift KararTests/AboutTests.swift project.yml Karar.xcodeproj
git commit -m "About window with versions, links and licences"
```

- [ ] **Step 8 (controller): UI check** — ask the user to open Karar ▸ About Karar (and one
  licence sheet); capture `About Karar` in light and dark. Check the grid's label column aligns, the
  links don't wrap, the icon placeholder (generic until Task 6) and the sheet's text scroll.

---

### Task 6: App icon (controller; show the user before committing)

**Files:**
- Create: `scripts/make-icon.swift`
- Create: `Karar/Assets.xcassets/Contents.json`, `Karar/Assets.xcassets/AppIcon.appiconset/{Contents.json, icon_*.png}`
- Modify: `project.yml` (then `xcodegen generate`)

- [ ] **Step 1: The drawing script**

`scripts/make-icon.swift`:

```swift
// Renders Karar's app icon into Karar/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit
import ImageIO

let set = URL(fileURLWithPath: "Karar/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }

/// A plain balance scale, white on an orange plate, on a 1024 × 1024 canvas (macOS icon grid:
/// an 824 plate at 100 with 185 corners). The beam tilts so the left pan hangs a little lower.
func draw(in ctx: CGContext) {
    let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                       cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(plate)
    ctx.setFillColor(rgb(0.93, 0.45, 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(1.0, 0.66, 0.25), rgb(0.93, 0.42, 0.08)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.translateBy(x: 0, y: 24)   // optical centre sits a little above the middle
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.18))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)   // one shadow for the whole scale
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Base and post.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 392, y: 236, width: 240, height: 40), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 494, y: 256, width: 36, height: 450), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.fillPath()

    // Beam and pivot.
    let pivot = CGPoint(x: 512, y: 700)
    let tilt = 7 * CGFloat.pi / 180, half: CGFloat = 230
    let left = CGPoint(x: pivot.x - half * cos(tilt), y: pivot.y - half * sin(tilt))
    let right = CGPoint(x: pivot.x + half * cos(tilt), y: pivot.y + half * sin(tilt))
    ctx.setLineWidth(30)
    ctx.move(to: left)
    ctx.addLine(to: right)
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: pivot.x - 34, y: pivot.y - 34, width: 68, height: 68))

    // Pans: two cords from each beam end, a shallow bowl under the rim. They hang straight down.
    for end in [left, right] {
        let rim = end.y - 200, rimHalf: CGFloat = 95
        ctx.setLineWidth(10)
        ctx.move(to: CGPoint(x: end.x - rimHalf + 8, y: rim))
        ctx.addLine(to: end)
        ctx.addLine(to: CGPoint(x: end.x + rimHalf - 8, y: rim))
        ctx.strokePath()
        let bowl = CGMutablePath()
        bowl.move(to: CGPoint(x: end.x - rimHalf, y: rim))
        bowl.addQuadCurve(to: CGPoint(x: end.x + rimHalf, y: rim), control: CGPoint(x: end.x, y: rim - 110))
        bowl.closeSubpath()
        ctx.addPath(bowl)
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(in: ctx)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let dest = CGImageDestinationCreateWithURL(set.appending(path: name) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let info = ["author": "xcode", "version": 1] as [String: Any]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appending(path: "Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: set.deletingLastPathComponent().appending(path: "Contents.json"))
```

Run: `swift scripts/make-icon.swift` and look at `icon_512x512@2x.png`, `icon_128x128.png`,
`icon_32x32.png` (Read them). Iterate on proportions until the scale reads clearly at 32 px and
looks balanced at 1024 px.

- [ ] **Step 2: Use it**

In `project.yml`, Karar target `settings.base`, add `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
Run `xcodegen generate`, build, relaunch. Check how this macOS draws it (it may frame
non-conforming icons): render the icon Finder shows,

```sh
cat > $S/appicon.swift <<'EOF'
import AppKit
let icon = NSWorkspace.shared.icon(forFile: CommandLine.arguments[1])
icon.size = NSSize(width: 512, height: 512)
let rep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
EOF
swift $S/appicon.swift build/Build/Products/Debug/Karar.app $S/finder-icon.png
```

and capture onboarding's welcome step (empty `OLLAYA_MODELS`) and About in light and dark.

- [ ] **Step 3: Show the user** the 1024 px render, the Finder icon and the captures
  (`SendUserFile`). Iterate on their feedback. **Do not commit before they approve.**

- [ ] **Step 4: Run the full test suite, then commit**

```bash
git add scripts/make-icon.swift Karar/Assets.xcassets project.yml Karar.xcodeproj
git commit -m "App icon: a tilted balance scale, white on orange"
```

---

### Task 7: Reproduce every §5 row by hand, light/dark sweep, roadmap (controller)

Each row below: reproduce, capture light **and** dark, judge the design, fix what is off (a fix
goes through the test suite and gets its own commit). Before each step check what listens on
11435 (`lsof -nP -iTCP:11435 -sTCP:LISTEN`). If the user's CLI daemon is up, **ask before
stopping it** and restart it afterwards the same way. Quit Karar with osascript, check `pgrep`.

- [ ] **§5.1 Daemon fails / crashes twice.** Launch Karar (own daemon, `OLLAYA_MODELS=$S/models`).
  `kill -9 $(pgrep -f "Karar.app/Contents/MacOS/ollaya")`; wait until a new one runs (the one
  automatic restart; results come back without an edit — the stale error is gone); kill it again.
  Expect the banner "Ollaya is not running" / "Ollaya stopped unexpectedly (exit code 9)." with
  Show Log and Restart. Ask the user to click Restart; expect answers again.
- [ ] **§5.2 Port in use.** `cd $S/empty && python3 -m http.server 11435 &`, launch Karar. Expect the
  port banner with the `lsof` hint and Try Again, and the "No models" empty state below. Stop the
  server, ask the user to click Try Again; expect the main window.
- [ ] **§5.3 Pull fails before the stream (404, 502).** Karar with
  `OLLAYA_REGISTRY=http://127.0.0.1:8123` (+ `python3 -m http.server 8123` in an empty dir): ask
  the user to open Download model… and click Download on a model that isn't installed → "This model
  is not in the registry." + Retry. Then `OLLAYA_REGISTRY=http://127.0.0.1:9` → "Could not reach
  the model registry…" + Retry. Also in onboarding (empty store): the label + Retry.
- [ ] **§5.4 Pull fails mid-stream.** (a) Storage: `hdiutil create -size 300m -fs APFS -volname
  KararTiny $S/tiny.dmg && hdiutil attach $S/tiny.dmg`, Karar with
  `OLLAYA_MODELS=/Volumes/KararTiny/models`, download `laya:en` (853 MB) → "Could not save the
  model: …" + Retry; `hdiutil detach /Volumes/KararTiny` afterwards. (b) Network: ask the user to
  turn Wi-Fi off during a download of a model not in `$S/models`, capture a frame a second, turn it
  back on, Retry → the bar resumes from the bytes on disk (not 0). If the pull just stalls with no
  error line, report that to the user with the frames before adding any stall handling.
- [ ] **§5.5 Selected model deleted outside the app.** Karar (own daemon, `$S/models` copy, `laya:en`
  selected, a text on screen). `OLLAYA_HOST=127.0.0.1:11435 vendor/ollaya/bin/ollaya rm laya:en`,
  then bring Karar to the front (or let the next answer's 404 do it) → "Choose a model" in the
  toolbar, "laya:en is no longer installed." with Download model…. Use a cloned store
  (`cp -c -R $S/models $S/models-del`) so `$S/models` stays whole.
- [ ] **§5.6 `422`** and **§5.7 `state_truncated`**: done in Phase 4; recapture both once in light and
  dark to check nothing regressed (`-advanced YES -KararQuestions '{"q": {"type": "score", "criteria": ["a"]}}'`;
  a long `-KararText` on `laya:en`).
- [ ] **Also:** a failed `/api/tags` (a fake "Ollaya is running" server on 11435 that answers 500
  elsewhere — a 10-line `python3 -c` with `http.server.BaseHTTPRequestHandler`) → "Could not load
  the installed models" banner + Try Again instead of an endless spinner.
- [ ] **Light/dark sweep** of every screen: onboarding (welcome, choose, downloading), main window
  simple and advanced (with inspector), download sheet, About (+ a licence sheet), each banner,
  the empty states ("Answers appear here as you type.", no-model note, "No models", inspector
  "No response yet."). Ask the user for the clicks needed to open sheets and windows.
- [ ] **Roadmap:** tick Phase 5 in `docs/superpowers/plans/2026-09-24-karar-roadmap.md`, link this
  plan under it, add notes (what surprised you: how a network cut shows, how this macOS frames the
  icon, anything left open). Run the full test suite. Commit:

```bash
git add docs/superpowers/plans/2026-09-24-karar-roadmap.md
git commit -m "Phase 5 done: tick roadmap, add notes"
```

- [ ] Show the `superpowers:finishing-a-development-branch` menu.
