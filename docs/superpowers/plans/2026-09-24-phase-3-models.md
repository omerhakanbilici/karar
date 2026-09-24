# Phase 3 — Models: download, delete, onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new user with an empty model store goes from launch to a live result without the
terminal: onboarding picks and downloads a first model; the main window can download more
("Download model…") and delete models; an interrupted download resumes on Retry.

**Architecture:** `OllayaClient.pull` turns the `/api/pull` NDJSON stream into an
`AsyncThrowingStream<PullProgress, Error>` (error lines and cut-off streams throw);
`OllayaClient.delete` calls `DELETE /api/delete`. `Catalog.json` lists the models Karar offers.
`Download` is a value type that folds progress lines into one bar per model (a router's targets
each get one) with speed and ETA. `AppModel` owns downloads, delete, the onboarding flag and the
engine version, through injected closures so it is unit-tested without a server. A new `RootView`
chooses between onboarding, a start-up spinner and `MainView`, and is the one place that reacts to
the daemon becoming ready.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, XcodeGen, Xcode 27.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. No third-party Swift dependencies.
  SwiftUI + Foundation only; AppKit only where SwiftUI lacks it.
- Bundle ID `io.github.omerhakanbilici.karar`. Hardened Runtime on. Ad-hoc signing.
- Ollaya pinned to `v0.3.2`; HTTP contract: `https://github.com/ollaya-dev/ollaya/blob/v0.3.2/docs/api.md`
  (§7.6 pull, §7.7 delete, §4.3 errors inside a stream, §10 cancellation). Not `main`.
- System semantic colours only (`.primary`, `.secondary`, `.tertiary`, `.tint`, `.separator`,
  `Color(nsColor: .textBackgroundColor)`, materials, `.background`/`.fill` styles). No custom
  palette, no `.green`/`.red`, so light/dark is automatic. UI text in English.
- `project.yml` is the source of truth; new files under `Karar/` or `KararTests/` need no project
  change (synced folders; `Catalog.json` becomes a bundle resource like `Presets/*.json`).
- The engine is started only by `AppDelegate` (`applicationDidFinishLaunching`) and stopped only in
  `applicationWillTerminate`. `AppModel` keeps taking the `Daemon` from `AppDelegate`. No view
  starts it on appear (the existing user-clicked Retry stays).
- Never touch the user's model store `~/.ollaya`. Every real download or delete during this phase
  runs against a Karar-started daemon with `OLLAYA_MODELS` pointing to a scratch directory.
- The user's own CLI daemon (`/usr/local/bin/ollaya serve`, 0.3.2) usually listens on 11435 and
  Karar adopts it. **Ask the user before stopping it**, and restart it the same way afterwards.
- Screenshots: capture only Karar's window (never the full screen) with the commands in
  "UI check" below. Typing into the app is impossible (no Accessibility): ask the user when a click
  or typed state is needed.
- Out of scope (later phases): Advanced mode, "My questions…", inspector, pinned results, error
  banner, port-in-use banner, About window, app icon.

Test command used throughout (from repo root; needs `vendor/ollaya`, run `scripts/fetch-ollaya.sh` once):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

**UI check** (used after every UI task; the controller does this, not a subagent):

```sh
S=<scratchpad>
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '
pkill -x Karar; sleep 1
open build/Build/Products/Debug/Karar.app            # light (follows the system)
# dark without touching system settings:  build/Build/Products/Debug/Karar.app/Contents/MacOS/Karar -AppleInterfaceStyle Dark &
# empty store, Karar's own daemon (user's daemon must be stopped first):
#   OLLAYA_MODELS=$S/store build/Build/Products/Debug/Karar.app/Contents/MacOS/Karar &
cat > $S/winid.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let karar = list.filter { $0[kCGWindowOwnerName as String] as? String == "Karar" && $0[kCGWindowLayer as String] as? Int == 0 }
let widest = karar.max { (($0[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) < (($1[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) }
print(widest?[kCGWindowNumber as String] as? Int ?? 0)
EOF
sleep 3; screencapture -x -o -l $(swift $S/winid.swift) $S/shot.png   # then Read $S/shot.png
```

Judge every capture: alignment, spacing, cramped or raw-looking parts, both appearances. Fix, then
show the user.

## Facts measured before writing this plan

- Registry `ollaya.dev` at v0.3.2 serves these manifests (HTTP 200), every blob URL (ollaya.dev
  and Hugging Face) answers HEAD 200, and every layout (`laya-markers-v1`, `decider-slots-v1`,
  `nli-pairs-v1`, `gliclass-uni-v1`) is compiled into the pinned binary (`strings`). Sizes are the
  manifest totals (config + all layers; on this Mac both the fp32 and fp16 graphs download):

  | Name | Bytes | Languages | License (from the manifest's license blob) |
  |---|---|---|---|
  | `laya` (router → `laya:en`, `laya:multilingual`) | 1,537,806,952 | 100+ languages | Apache-2.0 |
  | `laya:multilingual` (mmBERT-base, 322M) | 684,161,400 | 100+ languages | Apache-2.0 |
  | `laya:en` (ModernBERT-large, 421M) | 853,634,822 | English | Apache-2.0 |
  | `laya:typed-decisions` (ModernBERT-large) | 853,527,607 | English | Apache-2.0 |
  | `nli:modernbert-large` | 798,924,815 | English | Apache-2.0 |
  | `nli` (DeBERTa-v3-large) | 884,351,079 | English | MIT |
  | `gliclass` (DeBERTa-v3-large) | 1,768,474,434 | English | Apache-2.0 |
  | `decider:0.8b` (Qwen3.5-0.8B) | 1,532,870,365 | English | Apache-2.0 |
  | `decider` (= `decider:2b`, Qwen3.5-2B) | 3,791,735,106 | English | Apache-2.0 |

- A real `laya` pull (throwaway daemon on port 11436, scratch store) streams: `pulling manifest`,
  the router's 3 tiny blobs, `verifying sha256 digest`, then `pulling manifest` again for
  `laya:en` with its blobs, and so on per target — exactly api.md §7.6. Each blob first appears
  with `completed: 0`; lines repeat about every 10 MB. Download speed here was ~40 MB/s.
- **Resume is real, and looks like a jump:** after cutting a pull at 408 MB and pulling again, the
  weights blob reported `completed: 0` and then `408094215` on the next line. Speed must therefore
  ignore the bytes a blob already had (its first non-zero `completed`).
- The user chose (this session) **one progress bar per model in the pull**, not one per blob
  (blobs only carry digests; a router pull has ~16, mostly a few bytes). Task 6 updates spec §3.1.

---

### Task 1: `/api/pull` and `/api/delete` in the client

**Files:**
- Modify: `Karar/OllayaAPI.swift` (append `PullProgress`)
- Modify: `Karar/OllayaClient.swift` (add `pull`, `readPull`, `delete`, `checkDelete`)
- Test: `KararTests/OllayaClientTests.swift` (append tests)

**Interfaces:**
- Produces:
  - `struct PullProgress: Decodable, Equatable, Sendable { let status: String; let digest: String?; let total: Int64?; let completed: Int64? }` (memberwise init used by tests)
  - `OllayaClient.pull(model: String) -> AsyncThrowingStream<PullProgress, Error>` — finishes after `success`; throws an `OllayaError` for HTTP errors, error lines and a stream cut off without `success`. Cancelling the consumer cancels the HTTP request (the daemon then stops the pull and keeps partial blobs, api.md §10).
  - `static OllayaClient.readPull<Lines: AsyncSequence>(_ lines: Lines, onProgress: (PullProgress) -> Void) async throws where Lines.Element == String`
  - `OllayaClient.delete(model: String) async throws` — `404 MODEL_NOT_FOUND` counts as success.
  - `static OllayaClient.checkDelete(_ response: URLResponse, _ data: Data) throws`

- [ ] **Step 1: Write the failing tests** (append to `OllayaClientTests`)

```swift
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
```

- [ ] **Step 2: Run the tests, expect a build failure** (`PullProgress`, `readPull`, `checkDelete` missing).

- [ ] **Step 3: Implement**

Append to `Karar/OllayaAPI.swift`:

```swift
/// One line of the `POST /api/pull` stream (docs/api.md §7.6). Layer lines carry `digest`,
/// `total` and `completed`; the others only `status`.
struct PullProgress: Decodable, Equatable, Sendable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}
```

Add to `OllayaClient` (after `decide`):

```swift
    /// `POST /api/pull` as a stream of progress lines. Cancelling the consumer closes the
    /// connection; the daemon then stops the pull and keeps what it has (docs/api.md §10), so the
    /// next pull of the same name resumes.
    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        let request: URLRequest = {
            var request = URLRequest(url: base.appending(path: "api/pull"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["model": model])
            return request
        }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    // Errors before the stream starts are ordinary HTTP errors (docs/api.md §7.6).
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try Self.check(response, body)
                    }
                    try await Self.readPull(bytes.lines) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads pull lines until `success`. An error line (docs/api.md §4.3) is thrown; a stream
    /// that ends without `success` was cut off and is a failure.
    static func readPull<Lines: AsyncSequence>(_ lines: Lines, onProgress: (PullProgress) -> Void) async throws
    where Lines.Element == String {
        for try await line in lines where !line.isEmpty {
            let data = Data(line.utf8)
            if let error = try? decoder.decode(OllayaError.self, from: data) { throw error }
            let progress = try decoder.decode(PullProgress.self, from: data)
            onProgress(progress)
            if progress.status == "success" { return }
        }
        throw OllayaError(error: "The download was interrupted.", code: nil)
    }

    func delete(model: String) async throws {
        var request = URLRequest(url: base.appending(path: "api/delete"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["model": model])
        let (data, response) = try await Self.session.data(for: request)
        try Self.checkDelete(response, data)
    }

    /// A `404 MODEL_NOT_FOUND` means the model is already gone, which is what was asked
    /// (docs/api.md §7.7).
    static func checkDelete(_ response: URLResponse, _ data: Data) throws {
        do {
            try check(response, data)
        } catch let error as OllayaError where error.code == "MODEL_NOT_FOUND" {
            return
        }
    }
```

If Swift 6 complains about sending `bytes`/`continuation` into the `Task`, keep the structure and
fix only the annotation (e.g. mark the closure `@Sendable` or capture `continuation` explicitly);
do not switch to a delegate-based session.

- [ ] **Step 4: Run the tests, expect all to pass.**

- [ ] **Step 5: Commit**

```bash
git add Karar/OllayaAPI.swift Karar/OllayaClient.swift KararTests/OllayaClientTests.swift
git commit -m "Add OllayaClient.pull (NDJSON stream) and delete"
```

---

### Task 2: `Catalog.json`

**Files:**
- Create: `Karar/Catalog.json`
- Create: `Karar/Catalog.swift`
- Test: `KararTests/CatalogTests.swift`

**Interfaces:**
- Produces:
  - `struct CatalogEntry: Decodable, Identifiable, Hashable, Sendable { let name: String; let summary: String; let languages: String; let license: String; let size: Int64; let recommended: Bool; let includes: [String]; var id: String { name }; var canonicalName: String }`
  - `CatalogEntry.all: [CatalogEntry]` (bundled `Catalog.json`, in file order)
  - `CatalogEntry.named(_ name: String) -> CatalogEntry?`
  - `canonicalName`: the name as `/api/tags` reports it (`laya` → `laya:latest`, `laya:en` stays).

- [ ] **Step 1: Write the failing test** `KararTests/CatalogTests.swift`

```swift
import XCTest
@testable import Karar

final class CatalogTests: XCTestCase {
    func testBundlesTheCatalogWithLayaRecommendedFirst() {
        let names = CatalogEntry.all.map(\.name)
        XCTAssertEqual(names, ["laya", "laya:multilingual", "laya:en", "laya:typed-decisions",
                               "nli:modernbert-large", "nli", "gliclass", "decider:0.8b", "decider"])
        XCTAssertEqual(CatalogEntry.all.filter(\.recommended).map(\.name), ["laya"])
        for entry in CatalogEntry.all {
            XCTAssertFalse(entry.summary.isEmpty, entry.name)
            XCTAssertFalse(entry.languages.isEmpty, entry.name)
            XCTAssertFalse(entry.license.isEmpty, entry.name)
            XCTAssertGreaterThan(entry.size, 100_000_000, entry.name)
        }
    }

    func testCanonicalNamesMatchTags() {
        XCTAssertEqual(CatalogEntry.named("laya")?.canonicalName, "laya:latest")
        XCTAssertEqual(CatalogEntry.named("laya:en")?.canonicalName, "laya:en")
    }

    func testTheRouterIncludesItsTargetsInRouteOrder() throws {
        let laya = try XCTUnwrap(CatalogEntry.named("laya"))
        XCTAssertEqual(laya.includes, ["laya:en", "laya:multilingual"])
        XCTAssertEqual(laya.size, laya.includes.compactMap { CatalogEntry.named($0)?.size }.reduce(10_730, +))
        XCTAssertTrue(CatalogEntry.all.filter { $0.name != "laya" }.allSatisfy(\.includes.isEmpty))
    }
}
```

- [ ] **Step 2: Run the tests, expect a build failure.**

- [ ] **Step 3: Implement**

`Karar/Catalog.json` (sizes and licences verified against the v0.3.2 registry, see "Facts"; route
order from the `laya:latest` router blob: english → `laya:en`, multilingual → `laya:multilingual`):

```json
[
  {"name": "laya", "summary": "Picks the English or the multilingual Laya model for each text. Fast.",
   "languages": "100+ languages", "license": "Apache-2.0", "size": 1537806952, "recommended": true,
   "includes": ["laya:en", "laya:multilingual"]},
  {"name": "laya:multilingual", "summary": "Laya on mmBERT-base (322M parameters).",
   "languages": "100+ languages", "license": "Apache-2.0", "size": 684161400, "recommended": false, "includes": []},
  {"name": "laya:en", "summary": "Laya on ModernBERT-large (421M parameters). The fastest for English.",
   "languages": "English", "license": "Apache-2.0", "size": 853634822, "recommended": false, "includes": []},
  {"name": "laya:typed-decisions", "summary": "Laya fine-tuned on the typed-decisions workflows.",
   "languages": "English", "license": "Apache-2.0", "size": 853527607, "recommended": false, "includes": []},
  {"name": "nli:modernbert-large", "summary": "Moritz Laurer's zero-shot NLI classifier on ModernBERT-large.",
   "languages": "English", "license": "Apache-2.0", "size": 798924815, "recommended": false, "includes": []},
  {"name": "nli", "summary": "Moritz Laurer's zero-shot NLI classifier on DeBERTa-v3-large.",
   "languages": "English", "license": "MIT", "size": 884351079, "recommended": false, "includes": []},
  {"name": "gliclass", "summary": "Knowledgator's instruction-following zero-shot classifier on DeBERTa-v3-large.",
   "languages": "English", "license": "Apache-2.0", "size": 1768474434, "recommended": false, "includes": []},
  {"name": "decider:0.8b", "summary": "Mapika's decider on Qwen3.5-0.8B.",
   "languages": "English", "license": "Apache-2.0", "size": 1532870365, "recommended": false, "includes": []},
  {"name": "decider", "summary": "Mapika's decider on Qwen3.5-2B. The most accurate, and the largest.",
   "languages": "English", "license": "Apache-2.0", "size": 3791735106, "recommended": false, "includes": []}
]
```

`Karar/Catalog.swift`:

```swift
import Foundation

/// A model Karar offers to download (spec §1: the registry has no list endpoint, so Karar ships
/// `Catalog.json`). `size` is the manifest total at the pinned Ollaya version, shown as "~" until
/// the download reports real sizes.
struct CatalogEntry: Decodable, Identifiable, Hashable, Sendable {
    let name: String          // as `ollaya pull` takes it
    let summary: String
    let languages: String
    let license: String
    let size: Int64
    let recommended: Bool
    let includes: [String]    // a router's targets, in route order; a pull downloads them too

    var id: String { name }

    /// The name `/api/tags` reports (docs/api.md §3): the tag is always shown.
    var canonicalName: String { name.contains(":") ? name : name + ":latest" }

    static let all: [CatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CatalogEntry].self, from: data) else {
            fatalError("Catalog.json is missing from the app bundle or invalid")
        }
        return entries
    }()

    static func named(_ name: String) -> CatalogEntry? {
        all.first { $0.name == name }
    }
}
```

- [ ] **Step 4: Run the tests, expect all to pass.**

- [ ] **Step 5: Commit**

```bash
git add Karar/Catalog.json Karar/Catalog.swift KararTests/CatalogTests.swift
git commit -m "Add the model catalog, verified against the v0.3.2 registry"
```

---

### Task 3: `Download`: one bar per model, speed, ETA

**Files:**
- Create: `Karar/Download.swift`
- Test: `KararTests/DownloadTests.swift`

**Interfaces:**
- Consumes: `PullProgress` (Task 1), `CatalogEntry` (Task 2).
- Produces:
  - `struct Download: Equatable` with
    - `init(for entry: CatalogEntry)` — one `Part` per model the pull downloads: the entry itself, or a router's `includes` (looked up in `CatalogEntry.all` for their `size`).
    - `private(set) var parts: [Download.Part]`, `private(set) var isFinished: Bool`, `var error: String?`, `private(set) var bytesPerSecond: Double?`
    - `var fraction: Double` (all parts together, 0…1)
    - `mutating func apply(_ progress: PullProgress, at now: Date)`
    - `func secondsLeft(_ part: Part) -> Double?`
  - `struct Download.Part: Equatable, Identifiable { let name: String; let estimate: Int64; var isDone: Bool; var total: Int64; var completed: Int64; var fraction: Double; var id: String }`

Rules (from the measured stream, see "Facts"):
- Each `pulling manifest` line starts the next model. A router's own manifest comes first and has
  no bar, so for a router the first group is skipped.
- A part's `total` is the sum of its blob sizes seen so far, but never less than the catalog
  estimate until the part is done (blobs are announced one by one, so the bar must not jump back).
  A part is done when the next `pulling manifest` or `success` arrives.
- Speed ignores bytes a blob already had: its first non-zero `completed` is its baseline, and time
  counts from the first such line. No speed until 1 s has passed.

- [ ] **Step 1: Write the failing tests** `KararTests/DownloadTests.swift`

```swift
import XCTest
@testable import Karar

final class DownloadTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func manifest() -> PullProgress { PullProgress(status: "pulling manifest", digest: nil, total: nil, completed: nil) }
    private func layer(_ digest: String, _ total: Int64, _ completed: Int64) -> PullProgress {
        PullProgress(status: "pulling \(digest)", digest: "sha256:\(digest)", total: total, completed: completed)
    }
    private func status(_ s: String) -> PullProgress { PullProgress(status: s, digest: nil, total: nil, completed: nil) }

    func testASingleModelHasOnePartThatUsesTheEstimateUntilDone() throws {
        let entry = try XCTUnwrap(CatalogEntry.named("laya:en"))
        var d = Download(for: entry)
        XCTAssertEqual(d.parts.map(\.name), ["laya:en"])
        d.apply(manifest(), at: t0)
        d.apply(layer("a", 400, 400), at: t0)
        XCTAssertEqual(d.parts[0].completed, 400)
        XCTAssertEqual(d.parts[0].total, entry.size, "not 400: more blobs are coming")
        d.apply(layer("b", 1000, 500), at: t0)
        d.apply(layer("b", 1000, 1000), at: t0)
        XCTAssertEqual(d.parts[0].completed, 1400, "a repeated blob line replaces, not adds")
        d.apply(status("verifying sha256 digest"), at: t0)
        d.apply(status("writing manifest"), at: t0)
        XCTAssertFalse(d.isFinished)
        d.apply(status("success"), at: t0)
        XCTAssertTrue(d.isFinished)
        XCTAssertTrue(d.parts[0].isDone)
        XCTAssertEqual(d.parts[0].total, 1400)
        XCTAssertEqual(d.fraction, 1)
    }

    func testARouterGetsOneBarPerTargetAndNoneForItself() throws {
        var d = Download(for: try XCTUnwrap(CatalogEntry.named("laya")))
        XCTAssertEqual(d.parts.map(\.name), ["laya:en", "laya:multilingual"])
        d.apply(manifest(), at: t0)                 // the router's own manifest
        d.apply(layer("r", 135, 135), at: t0)
        XCTAssertEqual(d.parts.map(\.completed), [0, 0])
        d.apply(manifest(), at: t0)                 // laya:en
        d.apply(layer("e", 800, 800), at: t0)
        d.apply(manifest(), at: t0)                 // laya:multilingual
        XCTAssertTrue(d.parts[0].isDone)
        XCTAssertEqual(d.parts[0].total, 800)
        d.apply(layer("m", 600, 300), at: t0)
        XCTAssertEqual(d.parts[1].completed, 300)
        XCTAssertFalse(d.parts[1].isDone)
    }

    func testSpeedIgnoresBytesAlreadyOnDiskAndETAUsesIt() throws {
        let entry = try XCTUnwrap(CatalogEntry.named("laya:multilingual"))
        var d = Download(for: entry)
        d.apply(manifest(), at: t0)
        d.apply(layer("w", 600_000_000, 0), at: t0)
        d.apply(layer("w", 600_000_000, 400_000_000), at: t0.addingTimeInterval(0.1))   // resumed
        XCTAssertNil(d.bytesPerSecond, "no speed in the first second")
        d.apply(layer("w", 600_000_000, 440_000_000), at: t0.addingTimeInterval(2.1))
        XCTAssertEqual(try XCTUnwrap(d.bytesPerSecond), 20_000_000, accuracy: 1)
        let left = try XCTUnwrap(d.secondsLeft(d.parts[0]))
        XCTAssertEqual(left, Double(entry.size - 440_000_000) / 20_000_000, accuracy: 0.01)
    }

    func testOverallFractionCoversEveryPart() throws {
        var d = Download(for: try XCTUnwrap(CatalogEntry.named("laya")))
        d.apply(manifest(), at: t0)
        d.apply(manifest(), at: t0)
        d.apply(layer("e", 853_634_822, 853_634_822), at: t0)
        let expected = 853_634_822.0 / Double(853_634_822 + 684_161_400)
        XCTAssertEqual(d.fraction, expected, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the tests, expect a build failure.**

- [ ] **Step 3: Implement** `Karar/Download.swift`

```swift
import Foundation

/// The progress of one `/api/pull`, folded into one bar per model it downloads (a router has no
/// weights; its targets each get a bar). Lines carry only blob digests, so models are told apart
/// by their `pulling manifest` lines (docs/api.md §7.6: a router's own manifest first, then each
/// target in route order).
struct Download: Equatable {
    struct Part: Equatable, Identifiable {
        let name: String
        let estimate: Int64                        // catalog size, until the real sizes are known
        fileprivate(set) var isDone = false
        fileprivate var sizes: [String: Int64] = [:]      // digest → blob size
        fileprivate var present: [String: Int64] = [:]    // digest → bytes on disk

        var id: String { name }
        var completed: Int64 { present.values.reduce(0, +) }
        var total: Int64 {
            let known = sizes.values.reduce(0, +)
            return isDone ? known : max(known, estimate)   // blobs are announced one by one
        }
        var fraction: Double { total > 0 ? min(Double(completed) / Double(total), 1) : 0 }
    }

    private(set) var parts: [Part]
    private(set) var isFinished = false
    private(set) var bytesPerSecond: Double?
    var error: String?

    private let skipsFirstManifest: Bool           // a router's own manifest has no bar
    private var manifests = 0
    private var baselines: [String: Int64] = [:]   // digest → first non-zero `completed` (resumed bytes)
    private var firstByteAt: Date?

    init(for entry: CatalogEntry) {
        if entry.includes.isEmpty {
            parts = [Part(name: entry.name, estimate: entry.size)]
            skipsFirstManifest = false
        } else {
            parts = entry.includes.map { Part(name: $0, estimate: CatalogEntry.named($0)?.size ?? 0) }
            skipsFirstManifest = true
        }
    }

    var fraction: Double {
        let total = parts.map(\.total).reduce(0, +)
        return total > 0 ? min(Double(parts.map(\.completed).reduce(0, +)) / Double(total), 1) : 0
    }

    func secondsLeft(_ part: Part) -> Double? {
        guard let speed = bytesPerSecond, speed > 0, !part.isDone else { return nil }
        return Double(max(part.total - part.completed, 0)) / speed
    }

    private var current: Int? {
        let index = manifests - 1 - (skipsFirstManifest ? 1 : 0)
        return parts.indices.contains(index) ? index : nil
    }

    mutating func apply(_ progress: PullProgress, at now: Date) {
        switch progress.status {
        case "pulling manifest":
            if let current { parts[current].isDone = true }
            manifests += 1
        case "success":
            for index in parts.indices { parts[index].isDone = true }
            isFinished = true
        default:
            guard let digest = progress.digest, let size = progress.total, let bytes = progress.completed,
                  let current else { return }
            parts[current].sizes[digest] = size
            parts[current].present[digest] = bytes
            if bytes > 0, baselines[digest] == nil {
                baselines[digest] = bytes
                if firstByteAt == nil { firstByteAt = now }
            }
            updateSpeed(at: now)
        }
    }

    // ponytail: average since the first byte, not a moving window; fine for a steady connection.
    private mutating func updateSpeed(at now: Date) {
        guard let start = firstByteAt, now.timeIntervalSince(start) >= 1 else { return }
        var fresh: Int64 = 0
        for part in parts {
            for (digest, bytes) in part.present { fresh += bytes - (baselines[digest] ?? bytes) }
        }
        bytesPerSecond = Double(fresh) / now.timeIntervalSince(start)
    }
}
```

Note: the same blob (e.g. the shared license) can appear in several parts; its baseline is per
digest, so it never adds speed twice.

- [ ] **Step 4: Run the tests, expect all to pass.**

- [ ] **Step 5: Commit**

```bash
git add Karar/Download.swift KararTests/DownloadTests.swift
git commit -m "Add Download: one progress bar per pulled model, speed and ETA"
```

---

### Task 4: `AppModel`: models loading, downloads, delete, onboarding state

Also fixes the two Phase 2 review notes: concurrent `refreshModels()` calls finishing out of
order, and "No models yet" showing before the first refresh; and moves the engine version into
`AppModel`.

**Files:**
- Modify: `Karar/AppModel.swift`
- Modify: `Karar/KararApp.swift` (pass the new closures)
- Modify: `Karar/Views/MainView.swift` (use `app.connect()` and `app.engineVersion`; show the empty
  state only after the first load)
- Test: `KararTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `OllayaClient.pull/delete/version` (Task 1), `CatalogEntry` (Task 2), `Download` (Task 3).
- Produces (all on `@MainActor AppModel`):
  - `typealias Pull = @MainActor (_ model: String) -> AsyncThrowingStream<PullProgress, Error>`
  - `typealias Delete = @MainActor (_ model: String) async throws -> Void`
  - `typealias Version = @MainActor () async throws -> String`
  - `init(daemon:decide:tags:version:pull:delete:debounce:)`
  - `private(set) var modelsLoaded: Bool` — false until the first successful `/api/tags`
  - `private(set) var engineVersion: String`
  - `private(set) var isOnboarding: Bool` — set when a refresh finds no model; cleared by `getStarted`
  - `private(set) var downloads: [String: Download]` — keyed by `CatalogEntry.name`
  - `var deleteError: String?`
  - `func connect() async` — refresh models, then read the engine version
  - `func refreshModels() async` — newest call wins
  - `func isInstalled(_ entry: CatalogEntry) -> Bool`
  - `func download(_ entry: CatalogEntry)` — starts or retries; ignored while one runs
  - `func cancelDownload(_ entry: CatalogEntry)` — stops it; its `downloads` entry goes away
  - `func delete(_ model: String) async` — then refreshes; errors land in `deleteError`
  - `func getStarted(with entry: CatalogEntry)` — select it, Support ticket, sample ticket, leave onboarding
  - `static let sampleTicket: String`

- [ ] **Step 1: Write the failing tests.** In `KararTests/AppModelTests.swift`, extend `FakeOllaya`
and `makeApp`, then append the tests.

Replace `func tags()` in `FakeOllaya` and add the new members:

```swift
    var tagsDelays: [Duration] = []    // one per call, in call order; missing = no delay
    var pulls: [String: AsyncThrowingStream<PullProgress, Error>.Continuation] = [:]
    var deleted: [String] = []
    var deleteFailure: Error?

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
```

Replace `makeApp`:

```swift
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
```

New tests:

```swift
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
```

- [ ] **Step 2: Run the tests, expect a build failure** (new init parameters and members).

- [ ] **Step 3: Implement.** In `Karar/AppModel.swift`:

Add the typealiases next to `Decide`/`Tags`, the stored closures `version`, `pull`, `deleteModel`,
and extend `init`:

```swift
    typealias Version = @MainActor () async throws -> String
    typealias Pull = @MainActor (_ model: String) -> AsyncThrowingStream<PullProgress, Error>
    typealias Delete = @MainActor (_ model: String) async throws -> Void

    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, version: @escaping Version,
         pull: @escaping Pull, delete: @escaping Delete, debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.version = version
        self.pull = pull
        self.deleteModel = delete
        self.debounce = debounce
    }
```

New state (below `isUpdating`):

```swift
    private(set) var modelsLoaded = false
    private(set) var engineVersion = ""
    private(set) var isOnboarding = false
    private(set) var downloads: [String: Download] = [:]
    var deleteError: String?

    private var refreshes = 0
    private var pullTasks: [String: Task<Void, Never>] = [:]
```

Replace `refreshModels()` and add the rest:

```swift
    /// Called when the engine is ready.
    func connect() async {
        await refreshModels()
        engineVersion = (try? await version()) ?? ""
    }

    /// Reloads the installed models; keeps the selection if it is still installed. When calls
    /// overlap, the newest one wins. Finding no model starts onboarding (spec §3.1).
    func refreshModels() async {
        refreshes += 1
        let call = refreshes
        guard let fresh = try? await tags(), call == refreshes else { return }
        models = fresh
        modelsLoaded = true
        if fresh.isEmpty { isOnboarding = true }
        if !fresh.contains(where: { $0.name == model }) {
            model = fresh.first?.name
        }
    }

    func isInstalled(_ entry: CatalogEntry) -> Bool {
        models.contains { $0.name == entry.canonicalName }
    }

    /// Starts a pull, or retries a failed one; the daemon resumes from what it already has.
    func download(_ entry: CatalogEntry) {
        let name = entry.name
        guard pullTasks[name] == nil else { return }
        downloads[name] = Download(for: entry)
        let stream = pull(name)
        pullTasks[name] = Task {
            do {
                for try await progress in stream {
                    downloads[name]?.apply(progress, at: .now)
                }
            } catch {
                downloads[name]?.error = error.localizedDescription
            }
            pullTasks[name] = nil
            if Task.isCancelled {
                downloads[name] = nil
            } else if downloads[name]?.error == nil {
                await refreshModels()
            }
        }
    }

    /// Closing the stream detaches Karar from the pull; the daemon stops it and keeps the partial
    /// blobs (docs/api.md §10). The task above then forgets the download.
    func cancelDownload(_ entry: CatalogEntry) {
        pullTasks[entry.name]?.cancel()
    }

    func delete(_ model: String) async {
        do {
            try await deleteModel(model)
        } catch {
            deleteError = error.localizedDescription
        }
        await refreshModels()
    }

    /// Leaves onboarding with a result on screen at once (spec §3.1).
    func getStarted(with entry: CatalogEntry) {
        isOnboarding = false
        model = entry.canonicalName
        preset = Preset.all.first { $0.id == "triage" } ?? Preset.all[0]
        text = Self.sampleTicket
    }

    static let sampleTicket = """
        Hi, I was charged twice for my subscription this month. Please refund the second payment. \
        I have been a customer for three years, but if this is not fixed by Friday I will cancel my account.
        """
```

Cancelling the consuming task makes the `AsyncThrowingStream` end (its iterator returns `nil`
and calls `onTermination`, which cancels the HTTP request in `OllayaClient.pull`), so the loop
exits and the `Task.isCancelled` branch cleans up. The client guarantees that a stream which ends
without throwing saw `success`.

In `Karar/KararApp.swift` pass the new closures:

```swift
        app = AppModel(
            daemon: Daemon(probe: { await client.liveness() }, launch: Daemon.bundledLaunch),
            decide: { try await client.decide(model: $0, state: $1, questions: $2) },
            tags: { try await client.tags() },
            version: { try await client.version() },
            pull: { client.pull(model: $0) },
            delete: { try await client.delete(model: $0) }
        )
```

In `Karar/Views/MainView.swift`: remove `@State private var engineVersion`; the `.task` becomes

```swift
        .task(id: app.daemon.state) {
            guard case .running = app.daemon.state else { return }
            await app.connect()
        }
```

`engineStatus` reads `app.engineVersion`; in `detail`, `.running` shows `ProgressView()` while
`!app.modelsLoaded` and the existing "No models yet" view only when loaded and empty.

- [ ] **Step 4: Run the tests, expect all to pass** (old and new).

- [ ] **Step 5: Commit**

```bash
git add Karar/AppModel.swift Karar/KararApp.swift Karar/Views/MainView.swift KararTests/AppModelTests.swift
git commit -m "AppModel: downloads, delete, onboarding state; newest model refresh wins"
```

---

### Task 5: Root view, "Download model…" sheet, delete

**Files:**
- Create: `Karar/Views/RootView.swift`
- Create: `Karar/Views/DownloadSheet.swift`
- Modify: `Karar/KararApp.swift` (`Window` shows `RootView`)
- Modify: `Karar/Views/MainView.swift`

**Interfaces:**
- Consumes: Task 4's `AppModel` API, `CatalogEntry`, `Download`.
- Produces:
  - `struct RootView: View { let app: AppModel }` — the only place that calls `app.connect()` (on `.task(id: app.daemon.state)` when `.running`) and `refreshModels()` on `didBecomeActive`. Until Task 6 it shows `MainView`, or a full-window `ProgressView("Starting Ollaya…")` while `!app.modelsLoaded` and the daemon has not failed.
  - `struct DownloadSheet: View { let app: AppModel }` — the catalog with per-row state.
  - `struct DownloadCaption: View { let download: Download; let part: Download.Part }` — "420 MB of 854 MB · 40 MB/s · 12 sec left" / "854 MB · Done" / "Waiting…", reused by onboarding (Task 6).

Behaviour:
- `MainView` loses its `.task(id:)` and `.onReceive` (moved to `RootView`).
- Toolbar Model menu: after the inline picker, a `Divider()` and `Button("Download model…")`.
- Sidebar: under the model rows, in the Models section, a plain borderless row
  `Label("Download model…", systemImage: "plus")` (secondary foreground) that opens the sheet; it
  must not become a selectable model row (selection binding ignores it). Each model row gets
  `.contextMenu { Button("Delete…", role: .destructive) { … } }` that opens a
  `.confirmationDialog("Delete \(name)?", …)` with message
  "It is removed from this Mac, also for the ollaya command line. You can download it again." and a
  destructive "Delete" button calling `await app.delete(name)`. `app.deleteError` shows as an
  `.alert("Could not delete the model", …)` with an OK button that clears it.
- `MainView`'s empty-models fallback: `ContentUnavailableView` "No models" with a
  "Download model…" button (no Terminal instructions any more).
- `DownloadSheet` (`.sheet`, about 560 × 520): title "Download a model", secondary subtitle
  "Models are shared with the ollaya command line.", then a list, one row per `CatalogEntry.all`:
  - leading: name (headline) + "Recommended" capsule for `recommended` (`.caption2`, `.tint`
    foreground, `.quaternary` capsule fill), summary
    (secondary), and a caption line `languages · license · ~size` (tertiary; size via
    `ByteCountFormatter.string(fromByteCount:countStyle: .file)` prefixed with "~").
  - trailing, by state: installed → `Label("Installed", systemImage: "checkmark")` secondary;
    downloading → a 140 pt `ProgressView(value: download.fraction)` with the active part's
    `DownloadCaption` under it and an `xmark.circle.fill` borderless Cancel button (help "Cancel");
    failed → the error (secondary, caption, 2 lines max) and a "Retry" button; otherwise a
    "Download" button (`.bordered`).
  - bottom bar: "Done" (`.keyboardShortcut(.defaultAction)`) dismisses; downloads continue in
    the background and are visible again when the sheet reopens.

- [ ] **Step 1: Implement `RootView`, `DownloadSheet`, `DownloadCaption` and the `MainView` changes above.**

Caption formatting (in `DownloadSheet.swift`):

```swift
struct DownloadCaption: View {
    let download: Download
    let part: Download.Part

    var body: some View {
        Text(text).font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }

    private var text: String {
        let bytes = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if part.isDone { return "\(bytes(part.total)) · Done" }
        if part.completed == 0 && download.bytesPerSecond == nil { return "Waiting…" }
        var pieces = ["\(bytes(part.completed)) of \(bytes(part.total))"]
        if let speed = download.bytesPerSecond { pieces.append("\(bytes(Int64(speed)))/s") }
        if let left = download.secondsLeft(part) {
            pieces.append(Duration.seconds(left.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)) + " left")
        }
        return pieces.joined(separator: " · ")
    }
}
```

"Active part" for a row = the first part that is not done (else the last).

- [ ] **Step 2: Build and run the tests; expect all to pass.**

- [ ] **Step 3: UI check (controller).** With the user's daemon (adopted, models installed):
  main window, the Model menu (open it: ask the user to click, or trust the code), the sidebar
  "Download model…" row, the sheet with "Installed" rows. Light and dark. Then — **after asking
  the user to stop their daemon** — relaunch with `OLLAYA_MODELS=$S/store` (empty scratch store):
  the user clicks Download on `laya:multilingual` in the sheet; capture the downloading row, then
  Cancel; capture again. Fix what looks cramped or unaligned, re-check, show the user.

- [ ] **Step 4: Commit**

```bash
git add Karar/Views Karar/KararApp.swift
git commit -m "Add the Download model sheet, model delete, and a root view"
```

---

### Task 6: Onboarding

**Files:**
- Create: `Karar/Views/OnboardingView.swift`
- Modify: `Karar/Views/RootView.swift` (show onboarding while `app.isOnboarding`)
- Modify: `docs/superpowers/specs/2026-09-24-karar-design.md` (§3.1 step 3: one bar per model)

**Interfaces:**
- Consumes: `AppModel.isOnboarding`, `.engineVersion`, `.download`, `.cancelDownload`,
  `.downloads`, `.getStarted(with:)`, `CatalogEntry.all`, `DownloadCaption` (Task 5).
- Produces: `struct OnboardingView: View { let app: AppModel }`.

Screens (spec §3.1), in the same window (min 720 × 480), content centred in a column of max width
~480 pt with generous padding, buttons bottom-trailing, primary button `.borderedProminent`,
`.controlSize(.large)`, `.keyboardShortcut(.defaultAction)`:

1. **Welcome.** `Image(nsImage: NSApp.applicationIconImage)` at 96 pt (the real icon arrives in
   Phase 5), "Welcome to Karar" (`.largeTitle`, semibold), the sentence "Ask typed questions about
   any text and get calibrated answers in milliseconds. Everything runs on this Mac." (secondary,
   centred), a status line `Label("Ollaya engine ready · v\(app.engineVersion)", systemImage:
   "checkmark.circle.fill")` with the icon in `.tint`. Button: Continue.
2. **Choose your first model.** Title + secondary "You can download more models later.". A
   scrollable single-choice list of `CatalogEntry.all` inside a rounded `.background` /
   `.separator`-bordered container: each row = radio indicator
   (`largecircle.fill.circle` in `.tint` when selected, `circle` in `.tertiary` otherwise), name
   (+ "Recommended" capsule, same style as the sheet), summary, caption `languages · license ·
   ~size`; the whole row is the hit target (`contentShape(.rect)` + `onTapGesture`); rows separated
   by `Divider()`s. `laya` (the `recommended` entry) is preselected. Buttons: Back, Download (starts
   `app.download(entry)` and goes to step 3).
3. **Downloading.** Title "Downloading \(entry.name)", then for each `Download.Part`: name,
   `ProgressView(value: part.fraction)`, `DownloadCaption`. If `download.error` is set: a
   `Label(error, systemImage: "exclamationmark.triangle")` (secondary) and buttons Back
   (cancelDownload + step 2) and Retry (`app.download(entry)`). Otherwise buttons Cancel
   (`app.cancelDownload(entry)` + step 2) and "Get started" (disabled until
   `download.isFinished`; calls `app.getStarted(with: entry)`).

The step lives in `@State private var step` (`.welcome`, `.choose`, `.downloading(CatalogEntry)`);
if a download for some entry is already running when onboarding appears, start at step 3 for it.

Spec §3.1 step 3 becomes: "**Downloading.** One progress bar per model the pull downloads (a router
such as `laya` downloads its targets, `laya:en` and `laya:multilingual`, one bar each), with bytes,
speed and ETA. Cancel. …" (rest unchanged). Reason: `/api/pull` lines name blobs only by digest,
and a router pull has ~16 blobs, most of a few bytes (decided with the user in the Phase 3 session).

- [ ] **Step 1: Implement `OnboardingView` and the `RootView` switch** (`if app.isOnboarding { OnboardingView } else if … spinner … else { MainView }`).

- [ ] **Step 2: Build and run the tests; expect all to pass.**

- [ ] **Step 3: UI check (controller), empty store, Karar's own daemon, light and dark:** welcome,
  choose (ask the user to click Continue), downloading with a real `laya:multilingual` pull (ask
  the user to pick it and click Download), an error state (kill the child `ollaya` with
  `pkill -9 -f 'Karar.app/Contents/MacOS/ollaya'` mid-download; Karar restarts it once and the cut
  stream shows the error + Retry), and the finished state. Fix, re-check, show the user.

- [ ] **Step 4: Update spec §3.1 as above. Commit**

```bash
git add Karar/Views docs/superpowers/specs/2026-09-24-karar-design.md
git commit -m "Add onboarding: welcome, choose a first model, download, get started"
```

---

### Task 7: Acceptance, notes, roadmap (controller, with the user)

- [ ] **Step 1: Full test run** — all tests pass.
- [ ] **Step 2: Stop the user's daemon (ask first).** Find how it runs
  (`pgrep -fl 'ollaya serve'`, `ps -o ppid=,command= -p <pid>`, `launchctl list | grep -i ollaya`,
  `brew services list`), note the exact way, stop it the same way.
- [ ] **Step 3: Fresh store:** `rm -rf $S/store && mkdir $S/store`, launch
  `OLLAYA_MODELS=$S/store build/Build/Products/Debug/Karar.app/Contents/MacOS/Karar &`.
  Check `ps` that the `ollaya serve` child has the env (`ps eww <pid> | grep -o OLLAYA_MODELS=[^ ]*`).
- [ ] **Step 4: Launch → live result without the terminal.** User: Continue → pick
  `laya:multilingual` (smallest, 684 MB) → Download. Mid-download (≥ 30 %), interrupt: kill the
  child `ollaya` (`pkill -9 -f 'Karar.app/Contents/MacOS/ollaya'`); capture the error + Retry.
  Record the partial blob size in `$S/store/blobs` (`ls -l`). User: Retry. Capture: the bar resumes
  near the old percentage within a couple of seconds, not from 0 (the weights blob's first
  non-zero line ≈ the recorded partial size). Wait for success; user: Get started. Capture the
  main window: sample ticket, Support ticket, answers shown.
- [ ] **Step 5: Delete, in the scratch store:** user right-clicks the model in the sidebar →
  Delete… → Delete. Onboarding appears again (no model left). `ls $S/store` shows the manifest gone.
- [ ] **Step 6: Quit Karar; check its `ollaya` child is gone. Restart the user's daemon exactly
  as it was;** `curl -s 127.0.0.1:11435/api/tags` lists their models again. `rm -rf $S/store`.
- [ ] **Step 7: Roadmap:** tick Phase 3 `[x]`, add the plan link, add notes under "Notes for later
  phases" (e.g. resume shows as a jump from `completed: 0`; speed is an average since the first
  byte; `modelsLoaded` stays false if `/api/tags` keeps failing, which leaves the start-up spinner up
  — Phase 5 error banner). Commit:

```bash
git add docs/superpowers/plans/2026-09-24-karar-roadmap.md
git commit -m "Phase 3 done: tick roadmap, add notes"
```

- [ ] **Step 8:** `superpowers:finishing-a-development-branch` menu for the user.
