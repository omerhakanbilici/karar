# Phase 6 — Release: DMG, CI, repo docs, publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Karar v0.1.0 is on GitHub: `releases/latest/download/Karar.dmg` downloads an ad-hoc
signed DMG built by GitHub Actions, the repo has a README (screenshots in light and dark), a
`THIRD_PARTY.md`, a real-engine smoke script and a few local XCUITest smoke tests.

**Architecture:** Two shell scripts (`scripts/make-dmg.sh`, `scripts/smoke.sh`) do the packaging and
the real-engine check, so CI and a developer run the same commands. `.github/workflows/release.yml`
runs on a `v*` tag (publish) or by hand (dry run, DMG as a workflow artifact): fetch Ollaya → unit
tests → Release build → `Karar.dmg` → GitHub Release. A new `KararUITests` target (XCUITest only,
own scheme, local only) drives the real app against Karar's own engine and a scratch store.
Publishing (repo, push, tag) is done by the controller, one explicit user OK per step.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, XcodeGen, Xcode 27 locally / newest Xcode ≥ 26 on
the `macos-26` runner, POSIX sh, `hdiutil`, `codesign`, `jq` (in macOS 15+), `gh`.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. No third-party Swift dependencies; tests use
  XCTest/XCUITest only (no Appium, ViewInspector, snapshot libraries).
- Bundle ID `io.github.omerhakanbilici.karar` never changes. Hardened Runtime stays on. Ad-hoc
  signing (`adhoc,runtime`). No notarization in v1 (spec §2).
- Ollaya pinned to `v0.5.0` (bumped at the start of this phase, commit `79b0ee7`); HTTP contract:
  `https://github.com/ollaya-dev/ollaya/blob/v0.5.0/docs/api.md` (byte-identical to v0.3.2).
- The DMG is always named `Karar.dmg` (no version in the name), so
  `https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg` is the latest.
- System semantic colours only; the only exceptions are spec §4's system orange (truncation
  warning) and system red (invalid question card). UI text English. Code, docs, commits English.
- "Ollaya" only descriptively. README says Karar is not affiliated with the Ollaya project.
- `project.yml` is the source of truth; after editing it run `xcodegen generate` and commit
  `project.yml`, `Karar.xcodeproj/project.pbxproj` and the generated
  `Karar.xcodeproj/xcshareddata/xcschemes/*.xcscheme`. Never hand-edit the pbxproj.
- `vendor/` is never committed. `*.dmg` is already in `.gitignore`.
- Never touch the user's model store `~/.ollaya`. Real engine runs use a scratch `OLLAYA_MODELS`.
  Scripts use `127.0.0.1:11436`; only Karar itself (and the UI tests, which launch Karar) use 11435.
- Never `pkill` Karar: quit with `osascript -e 'tell application id "io.github.omerhakanbilici.karar" to quit'`
  and check with `pgrep -x Karar`. Launch with `-ApplePersistenceIgnoreState YES`. SIGKILLing
  `ollaya serve` orphans its `ollaya runner` children (ppid 1): kill those afterwards.
- Never change system settings (Automation mode / Accessibility, Privacy & Security). The user
  does that.
- **Outward-facing steps need the user's explicit OK in this session, one at a time:** creating the
  GitHub repo `omerhakanbilici/karar`, every `git push`, pushing the tag `v0.1.0`, running the
  release workflow, creating/editing the GitHub Release. Subagents never do any of these.

Test command used throughout (from repo root; needs `vendor/ollaya`):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

One test class: add `-only-testing:KararTests/<ClassName>` before `test`.

## Facts measured before writing this plan

- `vendor/ollaya` is v0.5.0: `minos 11.0`, ad-hoc signed, `share/doc/ollaya/` has `LICENSE`,
  `THIRD_PARTY_NOTICES` (ONNX Runtime 1.28.0, MIT), `onnxruntime-ThirdPartyNotices.txt`. The
  About window already opens all three (`AboutView.swift:70-72`).
- Registry manifests (`https://ollaya.dev/v2/library/<name>/manifests/<tag>`) name these Hugging Face
  sources: `laya*` → `convaiinnovations/laya`; `nli:modernbert-large` →
  `MoritzLaurer/ModernBERT-large-zeroshot-v2.0`; `nli` → `MoritzLaurer/deberta-v3-large-zeroshot-v2.0`;
  `gliclass` → `knowledgator/gliclass-instruct-large-v1.0`; `decider:0.8b` → `Mapika/decider-0.8b`;
  `decider` → `Mapika/decider-2b`. Licences as in `Karar/Catalog.json` (from each manifest's
  licence blob, Phase 3).
- There are no shared schemes yet (`Karar.xcodeproj/xcshareddata` does not exist); Xcode
  auto-creates a `Karar` scheme. A UI-test target would join that auto-created scheme's tests, so
  this plan defines both schemes in `project.yml`.
- `OllayaClient.local` is hard-wired to `127.0.0.1:11435`, so UI tests need that port free (the
  user has quit Ollaya.app; `pgrep -lf "ollaya serve"` shows nothing).
- `liveness()` classifies any HTTP answer that is not `200` + "Ollaya is running" as `.other` →
  `Daemon.State.portInUse` → banner "Port 11435 is in use by another program".
- On launch with models, `AppModel` selects the first installed model and the `triage` preset
  (5 questions: `intent` choice, `is_urgent` noul, `frustration` score, …).
- Timing-based unit tests: `waitUntil` in `AppModelTests.swift:70` and `DaemonTests.swift:37` gives
  up after 100 × 20 ms = 2 s; `testAnOlderRefreshAnsweringLastIsDropped` (`AppModelTests.swift:196`)
  relies on a 50 ms sleep for call ordering. Both can flake on a shared CI runner.
- `gh` is logged in as `omerhakanbilici`; `jq` is `/usr/bin/jq`; `xcodegen` is installed.
- Local: Xcode 27.0. GitHub's `macos-26` image ships Xcode 26.x (maybe 27 later); `AppIcon.icon`
  needs Xcode 26+. Whether the code compiles with Xcode 26's Swift is only known after the first
  dry run (Task 7).

## Decisions (user, this session)

- UI tests run **locally only**, not in CI (no ~800 MB model download on a runner). CI runs the unit
  tests. The user enables Automation mode (`automationmodetool`) before the first local run.
- Ollaya v0.5.0 network-loss behaviour (bar freezes, 120 s idle timeout no longer fires) is
  accepted as is; no code change.

## Out of scope

The deferred review notes in the roadmap stay deferred (none blocks a release), except RootView's
stale top comment, fixed in Task 4 since the file is touched anyway. No website (Phase 7), no
Developer ID / notarization, no auto-update.

## File map

| File | Task | Responsibility |
|---|---|---|
| `KararTests/AppModelTests.swift`, `KararTests/DaemonTests.swift` | 1 | CI-safe waits |
| `scripts/smoke.sh` | 2 | real-engine check on 11436, fills a reusable store |
| `scripts/make-dmg.sh` | 3 | verifies the signature, packs `Karar.dmg` |
| `project.yml` (+ generated pbxproj, schemes) | 4 | `KararUITests` target, `Karar` + `KararUITests` schemes |
| `Karar/Views/MainView.swift`, `ErrorBanner.swift`, `OnboardingView.swift`, `RootView.swift` | 4 | accessibility identifiers |
| `KararUITests/KararUITests.swift` | 4 | five smoke tests + light/dark window screenshots |
| `.github/workflows/release.yml` | 5 | tag → GitHub Release; manual run → dry run |
| `docs/screenshots/*.png` | 6 | README (and later site) images, light + dark |
| `THIRD_PARTY.md`, `README.md`, `CLAUDE.md` | 6 | repo docs |
| roadmap | 8 | tick Phase 6, notes |

---

### Task 1: CI-safe timing in the unit tests

**Files:**
- Modify: `KararTests/AppModelTests.swift:70-73` and `:196-207`
- Modify: `KararTests/DaemonTests.swift:37-40`

**Interfaces:** none (tests only).

- [ ] **Step 1: Give `waitUntil` 10 s instead of 2 s in both files.** It returns as soon as the
  condition holds, so passing tests don't get slower; only a slow runner gets more room. In both
  `AppModelTests.swift` and `DaemonTests.swift` replace

```swift
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
```

with

```swift
        // 10 s: generous for shared CI runners; returns as soon as the condition holds.
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
```

- [ ] **Step 2: Replace the ordering sleep with a condition.** In
  `testAnOlderRefreshAnsweringLastIsDropped`, the 50 ms sleep only waits until the older call has
  entered `tags()` and taken its 300 ms delay (`tagsDelays.removeFirst()`). Wait for exactly that:

```swift
        let slow = Task { await app.refreshModels() }          // older call, answers last
        await waitUntil { fake.tagsDelays.count == 1 }         // the older call took its 300 ms delay
```

  (Remove the `try? await Task.sleep(for: .milliseconds(50))` line; everything else in the test
  stays.) Leave the other fixed sleeps alone: they check that *nothing* happens within a window, so
  a slow runner can only make them pass more easily.

- [ ] **Step 3: Run the tests three times.** Run the test command three times in a row.
  Expected: `** TEST SUCCEEDED **` each time, 96 tests.

- [ ] **Step 4: Commit**

```bash
git add KararTests/AppModelTests.swift KararTests/DaemonTests.swift
git commit -m "Make the timing-based unit tests safe on shared CI runners"
```

---

### Task 2: `scripts/smoke.sh`

**Files:**
- Create: `scripts/smoke.sh` (executable)

**Interfaces:**
- Produces: `scripts/smoke.sh [path/to/Karar.app]`; env `KARAR_SMOKE_MODELS=<dir>` keeps the store
  (with `laya:en`) for reuse, e.g. by the UI tests in Task 4. Exit 0 = passed.

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# Real-engine smoke test (spec §6), local only: starts the ollaya inside a built Karar.app on
# 127.0.0.1:11436 with a scratch model store, pulls laya:en, runs one decide with the triage
# question set, and checks the answer's shape. Never touches ~/.ollaya. Needs jq (macOS 15+).
#   scripts/smoke.sh [path/to/Karar.app]      default: the Release build
#   KARAR_SMOKE_MODELS=<dir> keeps the store (and laya:en, ~850 MB) for the next run and the UI tests.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$root/build/Build/Products/Release/Karar.app"}
ollaya="$app/Contents/MacOS/ollaya"
[ -x "$ollaya" ] || { echo "error: $ollaya not found; build Karar first" >&2; exit 1; }
host=127.0.0.1:11436
if curl -s -m 2 -o /dev/null "http://$host/"; then echo "error: something already listens on $host" >&2; exit 1; fi

tmp=$(mktemp -d)
models=${KARAR_SMOKE_MODELS:-"$tmp/models"}
mkdir -p "$models"
OLLAYA_HOST=$host OLLAYA_MODELS=$models "$ollaya" serve > "$tmp/serve.log" 2>&1 &
pid=$!
# SIGTERM: ollaya shuts down cleanly and stops its runners (SIGKILL would orphan them).
trap 'kill $pid 2>/dev/null; wait $pid 2>/dev/null; rm -rf "$tmp"' EXIT

i=0
until curl -fs -m 1 "http://$host/" 2>/dev/null | grep -q "Ollaya is running"; do
  i=$((i + 1))
  [ $i -lt 50 ] || { echo "error: the engine did not start" >&2; cat "$tmp/serve.log" >&2; exit 1; }
  sleep 0.2
done
echo "engine: $(curl -fs "http://$host/api/version")"

# /api/pull streams NDJSON; a failure mid-stream is a line with "error" (api.md §7.6).
curl -fsN "http://$host/api/pull" -d '{"model":"laya:en"}' > "$tmp/pull.ndjson"
if grep -q '"error"' "$tmp/pull.ndjson"; then grep '"error"' "$tmp/pull.ndjson" >&2; exit 1; fi
tail -n 1 "$tmp/pull.ndjson" | grep -q '"success"' || { echo "error: the pull did not finish" >&2; exit 1; }

# The preset is spliced in verbatim: question order matters and jq would keep it anyway.
printf '{"model":"laya:en","state":"I was charged twice this month. Please refund me by Friday.","questions":%s}' \
  "$(cat "$root/Karar/Presets/triage.json")" > "$tmp/body.json"
curl -fs "http://$host/api/decide" -d @"$tmp/body.json" > "$tmp/decide.json" \
  || { echo "error: /api/decide failed" >&2; exit 1; }
jq -e '(.answers | length) == 5
  and (.answers.intent.choice | type) == "string"
  and (.answers.is_urgent.noul | type) == "number"
  and (.answers.frustration.score | type) == "number"
  and .usage.input_tokens > 0' "$tmp/decide.json" > /dev/null \
  || { echo "error: unexpected answer:" >&2; cat "$tmp/decide.json" >&2; exit 1; }
echo "smoke test passed: $(jq -c '{model, intent: .answers.intent.choice, ms: (.total_duration / 1000000 | floor)}' "$tmp/decide.json")"
```

- [ ] **Step 2: Make it executable and build Release**

```bash
chmod +x scripts/smoke.sh
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '
```

  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run it against a kept scratch store**

```bash
S=<the controller's scratchpad dir>
KARAR_SMOKE_MODELS=$S/uitest-models scripts/smoke.sh
pgrep -lf "ollaya serve"; ps -eo pid,ppid,command | awk '$2==1 && /ollaya runner/'
```

  Expected: `engine: {"version":"0.5.0"}` and `smoke test passed: {"model":"laya:en","intent":"refund",…}`
  (the intent may differ; the shape is what counts); afterwards no `ollaya serve` and no orphaned
  runner. If `jq -e` fails, compare the printed JSON with api.md §7.1 and fix the jq filter, not the
  engine.

- [ ] **Step 4: Check the failure path.** `scripts/smoke.sh /nonexistent.app` → prints
  `error: /nonexistent.app/Contents/MacOS/ollaya not found; build Karar first`, exit status 1.

- [ ] **Step 5: Commit**

```bash
git add scripts/smoke.sh
git commit -m "Add scripts/smoke.sh: pull laya:en and decide on the bundled engine"
```

---

### Task 3: `scripts/make-dmg.sh`

**Files:**
- Create: `scripts/make-dmg.sh` (executable)

**Interfaces:**
- Consumes: the Release build at `build/Build/Products/Release/Karar.app`.
- Produces: `scripts/make-dmg.sh [path/to/Karar.app]` → `<repo root>/Karar.dmg` (always this
  name), used by `release.yml` (Task 5).

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# Packs a built Karar.app into Karar.dmg in the repo root, always under this name (spec §2), with
# an Applications link to drag it onto. Refuses an app that isn't signed adhoc,runtime.
#   scripts/make-dmg.sh [path/to/Karar.app]      default: the Release build
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$root/build/Build/Products/Release/Karar.app"}
[ -d "$app" ] || { echo "error: $app not found; run the Release build first" >&2; exit 1; }

codesign --verify --deep --strict "$app"
for binary in "$app" "$app/Contents/MacOS/ollaya"; do
  codesign -dv "$binary" 2>&1 | grep -q '(adhoc,runtime)' \
    || { echo "error: $binary is not signed adhoc,runtime" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/Karar"
ditto "$app" "$tmp/Karar/Karar.app"
ln -s /Applications "$tmp/Karar/Applications"
dmg="$root/Karar.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname Karar -srcfolder "$tmp/Karar" -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"
echo "$dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
```

- [ ] **Step 2: Run it**

```bash
chmod +x scripts/make-dmg.sh
scripts/make-dmg.sh
```

  Expected: one line `…/Karar.dmg (NNM)`. (`hdiutil` may print a deprecation warning on macOS 27;
  it still works and the `macos-26` runner has no warning.)

- [ ] **Step 3: Check the contents**

```bash
hdiutil attach -nobrowse -readonly Karar.dmg | tail -1
ls -la /Volumes/Karar
codesign --verify --deep --strict /Volumes/Karar/Karar.app && codesign -dv /Volumes/Karar/Karar.app 2>&1 | grep flags
cat /Volumes/Karar/Karar.app/Contents/Resources/Ollaya/VERSION
hdiutil detach /Volumes/Karar
```

  Expected: `Karar.app` and `Applications -> /Applications`; `flags=0x10002(adhoc,runtime)`;
  `v0.5.0`. `git status` does not list `Karar.dmg` (ignored).

- [ ] **Step 4: Check the failure path.** `scripts/make-dmg.sh /nonexistent.app` → the `not found`
  error, exit 1.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-dmg.sh
git commit -m "Add scripts/make-dmg.sh: verify the signature and pack Karar.dmg"
```

---

### Task 4: `KararUITests` (local XCUITest smoke tests)

**Files:**
- Modify: `project.yml` (new target + two schemes), then `xcodegen generate`
- Modify: `Karar/Views/MainView.swift` (identifiers `editor`, `answer`, `pin`, `pinnedResult`)
- Modify: `Karar/Views/ErrorBanner.swift` (identifier `bannerTitle`)
- Modify: `Karar/Views/OnboardingView.swift` (identifier `welcome`)
- Modify: `Karar/Views/RootView.swift:3-5` (stale comment)
- Create: `KararUITests/KararUITests.swift`

**Interfaces:**
- Consumes: DEBUG launch arguments (`-KararText`, `-KararAppearance`, `-advanced`,
  `-ApplePersistenceIgnoreState`); a store with `laya:en` from Task 2 (`KARAR_SMOKE_MODELS`).
- Produces: scheme `KararUITests`; env `KARAR_UITEST_MODELS` (passed to xcodebuild as
  `TEST_RUNNER_KARAR_UITEST_MODELS=<dir>`); screenshot attachments named `main-light`,
  `main-dark`, `typing-light`, `onboarding-light`, `port-in-use-light`.

- [ ] **Step 1: Add the target and the schemes to `project.yml`.** Append under `targets:` (same
  indentation as `KararTests`):

```yaml
  KararUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: KararUITests
        type: syncedFolder
    dependencies:
      - target: Karar
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

  and add a top-level `schemes:` section at the end of the file:

```yaml
schemes:
  # Unit tests only: what CI runs (release.yml).
  Karar:
    build:
      targets:
        Karar: all
        KararTests: [test]
    test:
      config: Debug
      targets:
        - KararTests
  # Local only: drives the real app with the mouse and keyboard (needs Automation mode).
  KararUITests:
    build:
      targets:
        Karar: all
        KararUITests: [test]
    test:
      config: Debug
      targets:
        - KararUITests
```

  Create the folder (`mkdir KararUITests`), then run `xcodegen generate`. Check:
  `ls Karar.xcodeproj/xcshareddata/xcschemes` → `Karar.xcscheme  KararUITests.xcscheme`.

- [ ] **Step 2: Add the accessibility identifiers.** Identifiers only; no layout or behaviour
  change.
  - `MainView.editor`: directly after `TextEditor(text: $app.text)` add
    `.accessibilityIdentifier("editor")`.
  - `MainView.results`: `Text(row.answer).bold()` → `Text(row.answer).bold().accessibilityIdentifier("answer")`.
  - The toolbar Pin button (`Label("Pin", systemImage: "pin")`): after `.keyboardShortcut(.return, modifiers: .command)`
    add `.accessibilityIdentifier("pin")`.
  - The sidebar pin row: on the `Button { app.restore(pin) } label: { … }`, after `.buttonStyle(.plain)`
    add `.accessibilityIdentifier("pinnedResult")`.
  - `ErrorBanner`: `Text(title).font(.headline)` → `Text(title).font(.headline).accessibilityIdentifier("bannerTitle")`.
  - `OnboardingView.welcome`: `Text("Welcome to Karar").font(.largeTitle.weight(.semibold))` →
    add `.accessibilityIdentifier("welcome")`.
  - `RootView.swift` top comment: replace "it never starts the daemon itself (`AppDelegate` alone
    does that)" with "it never starts the daemon itself (`AppDelegate` does at launch, the
    banner's buttons on the user's click)".

- [ ] **Step 3: Write `KararUITests/KararUITests.swift`**

```swift
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

    override func setUp() async throws {
        continueAfterFailure = false
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
        // Anything that answers HTTP but isn't Ollaya: python's file server says 200 + a listing.
        let squatter = Process()
        squatter.executableURL = URL(filePath: "/usr/bin/python3")
        squatter.arguments = ["-m", "http.server", "11435", "--bind", "127.0.0.1"]
        squatter.currentDirectoryURL = FileManager.default.temporaryDirectory
        squatter.standardOutput = FileHandle.nullDevice
        squatter.standardError = FileHandle.nullDevice
        try squatter.run()
        self.squatter = squatter
        for _ in 0..<50 where await Self.portAnswer() == nil { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotNil(await Self.portAnswer(), "the stand-in server did not start")

        let app = launch(models: try Self.emptyStore().path)
        let title = app.staticTexts["bannerTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.label, "Port 11435 is in use by another program")
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
```

- [ ] **Step 4: Build everything and run the unit tests.** Run the test command (scheme `Karar`).
  Expected: 96 tests pass, and **no** `KararUITests` in the output (the `Karar` scheme only tests
  `KararTests`). Then build the UI tests without running them:

```bash
xcodebuild -project Karar.xcodeproj -scheme KararUITests -destination 'platform=macOS' -derivedDataPath build build-for-testing 2>&1 | grep -E 'error:|\*\* '
```

  Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit** (the subagent stops here; the controller runs the UI tests in Step 6)

```bash
git add project.yml Karar.xcodeproj KararUITests Karar/Views
git commit -m "Add KararUITests: local XCUITest smoke tests with light and dark screenshots"
```

- [ ] **Step 6 (controller): run the UI tests locally.** First ask the user to enable Automation
  mode (`automationmodetool enable-automationmode-without-authentication`, or allow the prompt) and
  not to use the Mac during the run; never change the setting yourself. Check port 11435 is free.

```bash
S=<scratchpad>; rm -rf build/uitests.xcresult
TEST_RUNNER_KARAR_UITEST_MODELS=$S/uitest-models xcodebuild -project Karar.xcodeproj -scheme KararUITests \
  -destination 'platform=macOS' -derivedDataPath build -resultBundlePath build/uitests.xcresult test 2>&1 \
  | grep -E 'error:|failed|passed|Executed|\*\* '
xcrun xcresulttool export attachments --path build/uitests.xcresult --output-path $S/uitest-shots
pgrep -x Karar; pgrep -lf "ollaya serve"; ps -eo pid,ppid,command | awk '$2==1 && /ollaya runner/'
```

  Expected: 6 tests pass; afterwards no Karar, no `ollaya serve`, no orphaned runner. Look at every
  exported PNG (light and dark). If an identifier is not found (SwiftUI sometimes puts it on a
  wrapper), inspect with `print(app.debugDescription)` in a throwaway run and adjust the query, not
  the view. If the runner can't load the test bundle because of Hardened Runtime library
  validation, set `ENABLE_HARDENED_RUNTIME: NO` under `KararUITests` → `settings.base` only (a
  test target, never shipped) and regenerate. Commit any fix with the task.

---

### Task 5: `.github/workflows/release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/fetch-ollaya.sh`, the `Karar` scheme (unit tests only, Task 4),
  `scripts/make-dmg.sh` (Task 3), `MARKETING_VERSION` in `project.yml`.
- Produces: on tag `v*`, a GitHub Release named `Karar X.Y.Z` with asset `Karar.dmg`; on
  `workflow_dispatch`, the same build with `Karar.dmg` as a workflow artifact and no release.

- [ ] **Step 1: Write the workflow**

```yaml
name: Release

# A v* tag builds, tests and publishes Karar.dmg as a GitHub Release. Running it by hand
# (Actions → Release → Run workflow) is a dry run: same steps, the DMG is kept as an artifact.
on:
  push:
    tags: ["v*"]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5

      - name: Select the newest Xcode
        # AppIcon.icon needs Xcode 26 or later.
        run: |
          xcode=$(ls -d /Applications/Xcode_*.app | grep -iv beta | sort -V | tail -n 1)
          sudo xcode-select -s "$xcode"
          xcodebuild -version

      - name: Check the tag matches MARKETING_VERSION
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
          if [ "$GITHUB_REF_NAME" != "v$version" ]; then
            echo "::error::Tag $GITHUB_REF_NAME does not match MARKETING_VERSION $version in project.yml"
            exit 1
          fi

      - name: Fetch Ollaya
        run: scripts/fetch-ollaya.sh

      - name: Test
        run: xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test

      - name: Build
        run: xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build

      - name: Make Karar.dmg
        run: scripts/make-dmg.sh

      - name: Keep the DMG (dry run)
        if: ${{ !startsWith(github.ref, 'refs/tags/') }}
        uses: actions/upload-artifact@v4
        with:
          name: Karar.dmg
          path: Karar.dmg

      - name: Publish the release
        if: startsWith(github.ref, 'refs/tags/')
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" Karar.dmg \
            --title "Karar ${GITHUB_REF_NAME#v}" \
            --generate-notes \
            --notes "Apple silicon, macOS 14 or later. Karar is not notarized: after the first launch, open System Settings → Privacy & Security and click Open Anyway (see the README)."
```

- [ ] **Step 2: Validate the YAML and dry-run its shell steps locally**

```bash
ruby -ryaml -e 'y = YAML.load_file(".github/workflows/release.yml"); puts y["jobs"]["release"]["steps"].map { _1["name"] || _1["uses"] }'
version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml); echo "v$version"
```

  Expected: the step names in order; `v0.1.0`. If `actionlint` is installed (`which actionlint`),
  also run `actionlint .github/workflows/release.yml` (no output = fine); don't install it.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Add the release workflow: tag v* → test → Release build → Karar.dmg → GitHub Release"
```

---

### Task 6: Screenshots, `THIRD_PARTY.md`, `README.md`, `CLAUDE.md`

**Files:**
- Create: `docs/screenshots/main-light.png`, `main-dark.png`, `advanced-light.png`, `advanced-dark.png`
- Create: `THIRD_PARTY.md`, `README.md`
- Modify: `CLAUDE.md` (Commands)

**Interfaces:**
- Consumes: the Debug build, a store with `laya` (router), `-KararText`, `-advanced YES`.
- Produces: `docs/screenshots/*.png` (Phase 7's site reuses them).

- [ ] **Step 1 (controller): take the screenshots.** Use a store with the `laya` router so the
  sidebar and inspector look like a new user's (`laya`, `laya:en`, `laya:multilingual`): clone the
  UI-test store (`cp -c -R $S/uitest-models $S/shot-models`) and pull `laya` into it with the
  vendor engine on 11436 (`OLLAYA_HOST=127.0.0.1:11436 OLLAYA_MODELS=$S/shot-models vendor/ollaya/bin/ollaya serve &`,
  `curl -N 127.0.0.1:11436/api/pull -d '{"model":"laya"}'`, then SIGTERM it). Then for each of
  `light`/`dark` × simple/advanced, launch the Debug build with `OLLAYA_MODELS=$S/shot-models`,
  `-ApplePersistenceIgnoreState YES -KararAppearance <a> -advanced <NO|YES> -KararText "<AppModel.sampleTicket>"`
  and `"-NSWindow Frame main" "200 200 1100 700 0 0 <screen w> <screen h>"` (advanced: `1280 760`),
  wait for the answers (second launch onward is warm), pick the window by owner PID
  (`CGWindowListCopyWindowInfo`, layer 0) and `screencapture -x -o -l <id> docs/screenshots/<name>.png`.
  Quit with osascript between runs. Judge every image: alignment, nothing cut off, the token
  counter visible, no warning in the sidebar caption, both themes clean. Show them to the user
  before committing.

- [ ] **Step 2: Write `THIRD_PARTY.md`**

```markdown
# Third-party software and models

Karar is licensed under the Apache License 2.0 ([LICENSE](LICENSE)). This file lists what it
bundles and what it downloads.

## Ollaya

Karar.app contains the `ollaya` binary of [Ollaya](https://github.com/ollaya-dev/ollaya) v0.5.0
(`ollaya-darwin-arm64.tgz` from the project's GitHub release, pinned by version and SHA-256 in
[`scripts/fetch-ollaya.sh`](scripts/fetch-ollaya.sh)). Karar only re-signs it for the Hardened
Runtime. Ollaya is licensed under the Apache License 2.0, the same text as Karar's
[LICENSE](LICENSE).

`ollaya` links ONNX Runtime 1.28.0 (MIT) and the components ONNX Runtime bundles. Their notices ship
inside the app next to Ollaya's licence, and Karar ▸ About Karar opens each of them:

- `Karar.app/Contents/Resources/Ollaya/LICENSE`
- `Karar.app/Contents/Resources/Ollaya/THIRD_PARTY_NOTICES`
- `Karar.app/Contents/Resources/Ollaya/onnxruntime-ThirdPartyNotices.txt`

## Question sets

The five built-in question sets in [`Karar/Presets/`](Karar/Presets) (`triage`, `email`, `guard`,
`moderation`, `router`) are copied unchanged from Ollaya v0.5.0
(`crates/ollaya-api/src/presets/`), licensed under the Apache License 2.0.

## Models

Karar does not include or redistribute any model. When you download one, Ollaya fetches it from
the Ollaya registry (`ollaya.dev`) and its authors' Hugging Face repositories into `~/.ollaya`,
together with its licence file. The models Karar offers ([`Karar/Catalog.json`](Karar/Catalog.json)):

| Model | Source | Licence |
|---|---|---|
| `laya` (picks `laya:en` or `laya:multilingual`), `laya:en`, `laya:multilingual`, `laya:typed-decisions` | [convaiinnovations/laya](https://huggingface.co/convaiinnovations/laya) | Apache-2.0 |
| `nli:modernbert-large` | [MoritzLaurer/ModernBERT-large-zeroshot-v2.0](https://huggingface.co/MoritzLaurer/ModernBERT-large-zeroshot-v2.0) | Apache-2.0 |
| `nli` | [MoritzLaurer/deberta-v3-large-zeroshot-v2.0](https://huggingface.co/MoritzLaurer/deberta-v3-large-zeroshot-v2.0) | MIT |
| `gliclass` | [knowledgator/gliclass-instruct-large-v1.0](https://huggingface.co/knowledgator/gliclass-instruct-large-v1.0) | Apache-2.0 |
| `decider:0.8b` | [Mapika/decider-0.8b](https://huggingface.co/Mapika/decider-0.8b) | Apache-2.0 |
| `decider` | [Mapika/decider-2b](https://huggingface.co/Mapika/decider-2b) | Apache-2.0 |

Each model's own licence file (in its download) is authoritative.
```

- [ ] **Step 3: Write `README.md`**

````markdown
# Karar

**Karar — a Mac app for Ollaya.** Ask typed questions about any text and see calibrated answers
while you type. Everything runs on your Mac.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/main-dark.png">
  <img alt="Karar's main window: a support ticket and the answers to its five questions" src="docs/screenshots/main-light.png">
</picture>

Karar is a native macOS app for [Ollaya](https://ollaya.dev), an engine for decision models.
Decision models don't write text: they read a text and answer typed questions about it — a choice
(refund, technical help, …), a score (2.4 of 3) or a yes/no — each with a calibrated confidence.
Karar bundles the engine, downloads models for you, and re-runs the questions every time you
pause typing.

**[Download Karar.dmg](https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg)**
· Apple silicon · macOS 14 or later · [All releases](https://github.com/omerhakanbilici/karar/releases)

## What Karar adds

Ollaya has its own desktop app, which runs the engine from the menu bar, downloads models and runs
a question set on a text. Karar is for working on the text and the questions:

- **A native SwiftUI app** that follows your Mac's light or dark appearance.
- **Live answers while you type**: each edit re-runs the questions a moment after you pause.
- **Editable question cards** (Advanced): change instructions and options, add choice, score and
  yes/no questions; an invalid question is marked on its own card.
- **An inspector**: which model answered and why, timings, token usage, the raw response, Copy JSON
  and Copy as curl.
- **A token counter** under the text, with the engine's own count, and a **truncation warning**
  when the text is longer than the model can read.
- **Pins**: ⌘↩ keeps a text and its answers in the sidebar, to compare them later.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/advanced-dark.png">
  <img alt="Advanced mode: editable question cards and the inspector" src="docs/screenshots/advanced-light.png">
</picture>

Karar uses the same model store (`~/.ollaya`) as the `ollaya` command line and Ollaya's desktop
app. If one of them is already running, Karar uses that engine and leaves it running when you quit.

## Install

1. Download [Karar.dmg](https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg),
   open it and drag Karar to Applications.
2. Open Karar. Karar is not notarized by Apple, so macOS says it can't check the app for malware.
   Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to the message about Karar and click
   **Open Anyway**, then confirm. You only do this once.

On first launch Karar asks which model to download. `laya` is recommended: fast, 100+ languages,
about 1.5 GB.

## Build from source

You need Xcode 26 or later on Apple silicon. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is
only needed if you change `project.yml`.

```sh
git clone https://github.com/omerhakanbilici/karar.git
cd karar
scripts/fetch-ollaya.sh        # the pinned Ollaya, checksum-verified, into vendor/
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Karar.app
```

`scripts/make-dmg.sh` packs the build into `Karar.dmg`, and `scripts/smoke.sh` checks the bundled
engine against a real model. The `KararUITests` scheme has a few UI smoke tests that run locally
(see the header of `KararUITests/KararUITests.swift`).

## Licence

Karar is licensed under the [Apache License 2.0](LICENSE). It bundles Ollaya (Apache-2.0); see
[NOTICE](NOTICE) and [THIRD_PARTY.md](THIRD_PARTY.md) for Ollaya, the bundled question sets and
the models' licences. Models are downloaded from their authors and never redistributed by Karar.

Karar is not affiliated with or endorsed by the Ollaya project. "Ollaya" is only used to say what
Karar works with.
````

- [ ] **Step 4: Add the new commands to `CLAUDE.md`.** In the `## Commands` code block, after the
  Release build line, add:

```sh
scripts/make-dmg.sh                          # Release build → Karar.dmg (always this name)
KARAR_SMOKE_MODELS=<dir> scripts/smoke.sh    # real engine on 11436: pull laya:en, one decide
TEST_RUNNER_KARAR_UITEST_MODELS=<dir> xcodebuild -project Karar.xcodeproj -scheme KararUITests -destination 'platform=macOS' -derivedDataPath build test   # local only
```

- [ ] **Step 5: Check the docs.** Every relative link in README/THIRD_PARTY resolves:

```bash
for f in LICENSE NOTICE THIRD_PARTY.md scripts/fetch-ollaya.sh Karar/Presets Karar/Catalog.json \
  docs/screenshots/main-light.png docs/screenshots/main-dark.png docs/screenshots/advanced-light.png \
  docs/screenshots/advanced-dark.png KararUITests/KararUITests.swift; do [ -e "$f" ] || echo "missing $f"; done
grep -n "not affiliated" README.md
```

  Expected: no `missing` lines; the "not affiliated" sentence is there.

- [ ] **Step 6: Commit**

```bash
git add README.md THIRD_PARTY.md CLAUDE.md docs/screenshots
git commit -m "Add README, THIRD_PARTY.md and light/dark screenshots"
```

---

### Task 7 (controller only): publish v0.1.0

Every numbered step below that touches GitHub needs its own explicit OK from the user first.
Before starting: all tests pass, the branch is merged into local `main` (the user picks this in the
finishing-a-development-branch menu, or approves a local fast-forward merge now).

- [ ] **Step 1: Create the public repo** (OK needed): `gh repo create omerhakanbilici/karar --public
  --description "Karar — a Mac app for Ollaya" --homepage "https://omerhakanbilici.github.io/karar/"`.
- [ ] **Step 2: Push `main`** (OK needed): `git remote add origin https://github.com/omerhakanbilici/karar.git`
  (if absent), `git push -u origin main`. Check `vendor/` and `build/` are not in the push
  (`git ls-files | grep -E '^(vendor|build)/'` → nothing).
- [ ] **Step 3: Dry run** (OK needed): `gh workflow run release.yml --ref main`, watch with
  `gh run watch`. Expected: green, a `Karar.dmg` artifact. If the runner's Xcode 26 rejects code
  that Xcode 27 accepts, fix it on a branch (ask before pushing), and note the Xcode on the runner.
- [ ] **Step 4: Tag and release** (OK needed): `git tag -a v0.1.0 -m "Karar 0.1.0"`,
  `git push origin v0.1.0`, `gh run watch`. Expected: the Release `Karar 0.1.0` with `Karar.dmg`.
- [ ] **Step 5: Verify the download.**

```bash
curl -fsSLo $S/Karar-latest.dmg https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg
hdiutil attach -nobrowse -readonly $S/Karar-latest.dmg | tail -1
codesign -dv /Volumes/Karar/Karar.app 2>&1 | grep flags; cat /Volumes/Karar/Karar.app/Contents/Resources/Ollaya/VERSION
hdiutil detach /Volumes/Karar
```

  Expected: `flags=0x10002(adhoc,runtime)`, `v0.5.0`.
- [ ] **Step 6: Clean-account install (user).** Ask the user to log into a clean macOS user account
  (creating one is theirs to do), download the DMG from the README link in Safari, install, and go
  through Done → Privacy & Security → Open Anyway → onboarding → a live answer. Record what macOS
  showed (wording, number of dialogs) in Notes; fix the README steps if they differ.

---

### Task 8 (controller): close the phase

- [ ] Check each acceptance criterion: `releases/latest/download/Karar.dmg` downloads (Task 7 Step 5);
  the DMG installs on a clean account via Open Anyway (Task 7 Step 6).
- [ ] In the roadmap, tick Phase 6 (`- [x]`), add `Plan: [2026-09-25-phase-6-release.md](2026-09-25-phase-6-release.md)`,
  and add Notes: the runner's Xcode version, UI-test findings, the Gatekeeper flow as seen, anything
  surprising. Commit (`Phase 6 done: tick roadmap, add notes`); pushing it needs the user's OK.
- [ ] Show the finishing-a-development-branch menu.
