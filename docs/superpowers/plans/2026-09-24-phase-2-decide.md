# Phase 2 — Decide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The main window shows live answers: pick an installed model and a question set, type
text, and simple-mode result rows update as you type.

**Architecture:** `OllayaClient.decide` posts to `/api/decide`; the bundled preset JSON is spliced
into the request body byte for byte so question and criteria order reach the server unchanged.
`AppModel` (`@MainActor @Observable`) takes the `Daemon` from `AppDelegate` (which alone starts and
stops it), holds the selection and text, and runs live updates (cancel in-flight, 300 ms debounce)
through injected closures so the logic is unit-tested without a server. `MainView` is a
`NavigationSplitView` (sidebar = installed models) with toolbar pickers, a `TextEditor` and result rows.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, XcodeGen, Xcode 27.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. No third-party Swift dependencies.
- Bundle ID `io.github.omerhakanbilici.karar`. Hardened Runtime on. Ad-hoc signing.
- Ollaya pinned to `v0.3.2`; HTTP contract: `https://github.com/ollaya-dev/ollaya/blob/v0.3.2/docs/api.md`.
- Presets are copied verbatim from Ollaya `crates/ollaya/src/presets/` **at tag `v0.3.2`** (not `main`).
- System semantic colours only. UI text in English.
- `project.yml` is the source of truth; after editing it run `xcodegen generate` and commit both.
  New files under `Karar/` or `KararTests/` need no project change (synced folders).
- The engine is started only by `AppDelegate` (`applicationDidFinishLaunching`) and stopped only
  in `applicationWillTerminate`. No view starts it on appear. (The existing user-clicked Retry
  button stays.)
- Question set names (spec §3.2): Support ticket = `triage`, Email = `email`, Safety = `guard`,
  Moderation = `moderation`, Routing = `router`.
- Live results (spec §3.2): every edit cancels the in-flight request, waits 300 ms, then calls
  `/api/decide`.
- Out of scope here (later phases): "Download model…", "My questions…", Advanced toggle,
  inspector, pinned results, error banner, `state_truncated` note.

Test command used throughout (from repo root; needs `vendor/ollaya`, run `scripts/fetch-ollaya.sh` once):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

Facts measured before writing this plan (M1 Pro, CLI daemon 0.3.2, warm model): a 5-question
preset takes ~1.25 s on `laya:en` and ~0.47 s on `laya:multilingual`; time grows linearly with the
number of questions. So an "updating" indicator is needed and old rows stay visible, dimmed,
while a request runs.

---

### Task 1: `/api/decide` types and client method

**Files:**
- Modify: `Karar/OllayaAPI.swift` (append types)
- Modify: `Karar/OllayaClient.swift` (add `decide`, `decideBody`, `stateJSON`)
- Test: `KararTests/OllayaClientTests.swift` (append tests)

**Interfaces:**
- Produces:
  - `struct DecideResponse: Decodable, Sendable { let model: String; let answers: [String: Answer]; let totalDuration: Int64 }` (memberwise init used by tests)
  - `struct Answer: Decodable, Hashable, Sendable { let type: String; let choice: String?; let score: Double?; let noul: Double?; let confidence: Double?; let legend: [String: String]? }`
  - `OllayaClient.decide(model: String, state: String, questions: Data) async throws -> DecideResponse`
  - `static OllayaClient.decideBody(model: String, state: String, questions: Data) throws -> Data`
  - `static OllayaClient.stateJSON(_ text: String) throws -> Data`

**Gotcha:** `OllayaClient.decoder` uses `.convertFromSnakeCase`, which JSONDecoder also applies to
**dictionary keys**: answer id `is_urgent` would come back as `isUrgent`. `DecideResponse` must be
decoded with a plain `JSONDecoder()` and explicit `CodingKeys`. A test uses a snake_case id to
guard this.

- [ ] **Step 1: Write the failing tests** (append inside `OllayaClientTests`)

```swift
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
        XCTAssertEqual(r.answers["urgency"]?.legend?.count, 3)
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
    }

    func testStateIsTextUnlessItIsAJSONObjectOrArray() throws {
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("  {\"a\": 1}\n"), as: UTF8.self), #"{"a": 1}"#)
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("[1, 2]"), as: UTF8.self), "[1, 2]")
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("{not json"), as: UTF8.self), #""{not json""#)
        XCTAssertEqual(String(decoding: try OllayaClient.stateJSON("hello\n\n"), as: UTF8.self), #""hello""#)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: build error, `cannot find 'DecideResponse' in scope` /
`type 'OllayaClient' has no member 'decideBody'`.

- [ ] **Step 3: Add the wire types** (append to `Karar/OllayaAPI.swift`)

```swift
/// `POST /api/decide` response. Decode with a plain `JSONDecoder()`: `.convertFromSnakeCase`
/// would also rewrite the caller's question ids in `answers` (`is_urgent` → `isUrgent`).
struct DecideResponse: Decodable, Sendable {
    let model: String            // the model that answered (a router's target)
    let answers: [String: Answer]
    let totalDuration: Int64     // nanoseconds

    enum CodingKeys: String, CodingKey {
        case model, answers
        case totalDuration = "total_duration"
    }
}

/// One answer; which fields are set depends on `type` (docs/api.md §5.4).
struct Answer: Decodable, Hashable, Sendable {
    let type: String             // "choice", "score" or "noul"
    let choice: String?
    let score: Double?
    let noul: Double?
    let confidence: Double?
    let legend: [String: String]?
}
```

- [ ] **Step 4: Add the client method** (in `Karar/OllayaClient.swift`, after `tags()`)

```swift
    func decide(model: String, state: String, questions: Data) async throws -> DecideResponse {
        var request = URLRequest(url: base.appending(path: "api/decide"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.decideBody(model: model, state: state, questions: questions)
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(DecideResponse.self, from: data)
    }

    /// The questions are spliced in as raw bytes so their key order (question order, criteria
    /// order) reaches the server unchanged; encoding them as Swift dictionaries would reorder them.
    static func decideBody(model: String, state: String, questions: Data) throws -> Data {
        Data(#"{"model":"#.utf8) + (try JSONEncoder().encode(model))
            + Data(#","state":"#.utf8) + (try stateJSON(state))
            + Data(#","questions":"#.utf8) + questions + Data("}".utf8)
    }

    /// As `ollaya run` does: a JSON object or array is sent as JSON, anything else as the text
    /// itself without trailing newlines.
    static func stateJSON(_ text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" || trimmed.first == "[",
           let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
           object is [Any] || object is [String: Any] {
            return Data(trimmed.utf8)
        }
        var text = text
        while text.last?.isNewline == true { text.removeLast() }
        return try JSONEncoder().encode(text)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Karar/OllayaAPI.swift Karar/OllayaClient.swift KararTests/OllayaClientTests.swift
git commit -m "Add OllayaClient.decide with order-preserving request body"
```

---

### Task 2: Bundled presets

**Files:**
- Create: `Karar/Presets/triage.json`, `email.json`, `guard.json`, `moderation.json`, `router.json` (downloaded, verbatim)
- Create: `Karar/Preset.swift`
- Create: `KararTests/PresetTests.swift`
- Modify: `NOTICE` (one paragraph)

**Interfaces:**
- Produces:
  - `struct Preset: Identifiable, Hashable, Sendable { let id: String; let name: String; let questions: Data; let questionIDs: [String] }`
  - `static Preset.all: [Preset]` — order: triage, email, guard, moderation, router
  - `static Preset.topLevelKeys(of json: Data) -> [String]`

JSONDecoder and JSONSerialization both lose object key order, and the key order *is* the question
order shown to the user, so a small depth- and string-aware scanner reads the top-level keys.

- [ ] **Step 1: Download the presets at the pinned tag**

```bash
mkdir -p Karar/Presets
for p in triage email guard moderation router; do
  curl -fsSL -o "Karar/Presets/$p.json" \
    "https://raw.githubusercontent.com/ollaya-dev/ollaya/v0.3.2/crates/ollaya/src/presets/$p.json"
done
head -3 Karar/Presets/triage.json
```

Expected: `{`, `  "intent": {`, `    "type": "choice",`.

- [ ] **Step 2: Write the failing tests** (`KararTests/PresetTests.swift`)

```swift
import XCTest
@testable import Karar

final class PresetTests: XCTestCase {
    func testBundlesEveryPresetInPickerOrder() throws {
        XCTAssertEqual(Preset.all.map(\.id), ["triage", "email", "guard", "moderation", "router"])
        XCTAssertEqual(Preset.all.map(\.name), ["Support ticket", "Email", "Safety", "Moderation", "Routing"])
        for preset in Preset.all {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: preset.questions) as? [String: Any], preset.id)
            XCTAssertEqual(Set(preset.questionIDs), Set(object.keys), preset.id)
            XCTAssertEqual(preset.questionIDs.count, object.count, preset.id)
        }
    }

    func testTriageQuestionsKeepFileOrder() {
        XCTAssertEqual(Preset.all[0].questionIDs,
                       ["intent", "is_urgent", "frustration", "refund_requested", "churn_risk"])
    }

    func testTopLevelKeysSkipNestedKeysAndStringContents() {
        let json = #"{"b": {"a": 1, "x:y": "}"}, "a\"q": [1, {"z": 2}], "c": "d:e", "ç": null}"#
        XCTAssertEqual(Preset.topLevelKeys(of: Data(json.utf8)), ["b", "a\"q", "c", "ç"])
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the test command. Expected: build error, `cannot find 'Preset' in scope`.

- [ ] **Step 4: Implement `Karar/Preset.swift`**

```swift
import Foundation

/// A built-in question set. The JSON files in `Presets/` are copied verbatim from Ollaya
/// `crates/ollaya/src/presets/` at the pinned tag (the HTTP API does not serve them).
struct Preset: Identifiable, Hashable, Sendable {
    let id: String              // file name, as `ollaya run --preset` spells it
    let name: String            // shown in the Question set picker
    let questions: Data         // the JSON object, sent to /api/decide byte for byte
    let questionIDs: [String]   // in file order: the order of the result rows

    static let all: [Preset] = [
        ("triage", "Support ticket"), ("email", "Email"), ("guard", "Safety"),
        ("moderation", "Moderation"), ("router", "Routing"),
    ].map { Preset(id: $0.0, name: $0.1) }

    private init(id: String, name: String) {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("\(id).json is missing from the app bundle")
        }
        self.id = id
        self.name = name
        questions = data
        questionIDs = Self.topLevelKeys(of: data)
    }

    /// The keys of a JSON object in document order. JSONDecoder and JSONSerialization both
    /// lose key order. Assumes valid JSON.
    static func topLevelKeys(of json: Data) -> [String] {
        let bytes = [UInt8](json)
        var keys: [String] = []
        var depth = 0
        var pending: Range<Int>?   // a string at depth 1; a key if a ':' follows
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                let start = i
                i += 1
                while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
                    i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
                }
                pending = depth == 1 ? start..<min(i + 1, bytes.count) : nil
            case UInt8(ascii: ":"):
                if let range = pending,
                   let key = try? JSONDecoder().decode(String.self, from: Data(bytes[range])) {
                    keys.append(key)
                }
                pending = nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                pending = nil
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                pending = nil
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                break
            default:
                pending = nil
            }
            i += 1
        }
        return keys
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.
If `testBundlesEveryPresetInPickerOrder` hits the `fatalError`, check where Xcode put the files:
`ls build/Build/Products/Debug/Karar.app/Contents/Resources/`. They are expected flat
(`triage.json` next to `Ollaya/`); if they are under `Presets/`, pass `subdirectory: "Presets"`.

- [ ] **Step 6: Attribute the presets in `NOTICE`**

Insert this paragraph after the paragraph that ends "…ship inside the app at Contents/Resources/Ollaya/.":

```
The question sets in Karar/Presets/ are copied from Ollaya v0.3.2
(crates/ollaya/src/presets/), licensed under the Apache License, Version 2.0.
```

- [ ] **Step 7: Commit**

```bash
git add Karar/Presets Karar/Preset.swift KararTests/PresetTests.swift NOTICE
git commit -m "Bundle Ollaya v0.3.2 presets with their question order"
```

---

### Task 3: Simple-mode result rows

**Files:**
- Create: `Karar/ResultRow.swift`
- Create: `KararTests/ResultRowTests.swift`

**Interfaces:**
- Consumes: `Answer` (Task 1).
- Produces: `struct ResultRow: Identifiable, Equatable { let id: String; let label: String; let answer: String; let sureness: Double; init(id: String, answer: Answer); static func humanize(_ id: String) -> String }`

Spec §3.2 simple mode: human label, answer in words ("Yes"/"No", the choice label, "1.8 / 3"),
a bar, a percentage. The bar and the percentage show the same number, "how sure":
`confidence` for choice and score; for noul (which has no confidence) the probability of the
answer shown, i.e. `max(p, 1 − p)`.

- [ ] **Step 1: Write the failing tests** (`KararTests/ResultRowTests.swift`)

```swift
import XCTest
@testable import Karar

final class ResultRowTests: XCTestCase {
    private func answer(_ type: String, choice: String? = nil, score: Double? = nil, noul: Double? = nil,
                        confidence: Double? = nil, levels: Int? = nil) -> Answer {
        Answer(type: type, choice: choice, score: score, noul: noul, confidence: confidence,
               legend: levels.map { n in Dictionary(uniqueKeysWithValues: (0..<n).map { ("\($0)", "level \($0)") }) })
    }

    func testNoulSaysYesOrNoWithTheProbabilityOfThatAnswer() {
        let yes = ResultRow(id: "is_urgent", answer: answer("noul", noul: 0.9127))
        XCTAssertEqual(yes.label, "Is urgent")
        XCTAssertEqual(yes.answer, "Yes")
        XCTAssertEqual(yes.sureness, 0.9127, accuracy: 1e-9)

        let no = ResultRow(id: "is_spam", answer: answer("noul", noul: 0.2))
        XCTAssertEqual(no.answer, "No")
        XCTAssertEqual(no.sureness, 0.8, accuracy: 1e-9)
    }

    func testScoreShowsLevelOutOfTheTopLevel() {
        let row = ResultRow(id: "frustration", answer: answer("score", score: 1.7612, confidence: 0.3418, levels: 4))
        XCTAssertEqual(row.answer, "1.8 / 3")
        XCTAssertEqual(row.sureness, 0.3418)
    }

    func testChoiceShowsTheLabelInWords() {
        let row = ResultRow(id: "intent", answer: answer("choice", choice: "technical_help", confidence: 0.5))
        XCTAssertEqual(row.label, "Intent")
        XCTAssertEqual(row.answer, "Technical help")
        XCTAssertEqual(row.sureness, 0.5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: build error, `cannot find 'ResultRow' in scope`.

- [ ] **Step 3: Implement `Karar/ResultRow.swift`**

```swift
import Foundation

/// One simple-mode result line (spec §3.2): the question and the answer in words, and how sure
/// the model is (0…1, drawn as a bar and a percentage).
struct ResultRow: Identifiable, Equatable {
    let id: String
    let label: String
    let answer: String
    let sureness: Double

    init(id: String, answer a: Answer) {
        self.id = id
        label = Self.humanize(id)
        switch a.type {
        case "noul":
            let p = a.noul ?? 0
            answer = p >= 0.5 ? "Yes" : "No"
            sureness = max(p, 1 - p)
        case "score":
            let top = max((a.legend?.count ?? 2) - 1, 1)
            answer = String(format: "%.1f / %d", a.score ?? 0, top)
            sureness = a.confidence ?? 0
        default:   // "choice", and any type a newer Ollaya adds
            answer = Self.humanize(a.choice ?? a.type)
            sureness = a.confidence ?? 0
        }
    }

    /// `refund_requested` → "Refund requested".
    static func humanize(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Karar/ResultRow.swift KararTests/ResultRowTests.swift
git commit -m "Add simple-mode result rows"
```

---

### Task 4: `AppModel` with live updates, owned by `AppDelegate`

**Files:**
- Create: `Karar/AppModel.swift`
- Create: `KararTests/AppModelTests.swift`
- Modify: `Karar/KararApp.swift` (AppDelegate builds `AppModel`; window keeps `StatusView` for now)

**Interfaces:**
- Consumes: `Daemon` (existing), `OllayaClient.decide/tags` (Task 1), `Preset` (Task 2), `ResultRow` (Task 3).
- Produces:
  - `@MainActor @Observable final class AppModel`
    - `typealias Decide = @MainActor (_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse`
    - `typealias Tags = @MainActor () async throws -> [ModelInfo]`
    - `init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, debounce: Duration = .milliseconds(300))`
    - `let daemon: Daemon`
    - `private(set) var models: [ModelInfo]`
    - `var model: String?`, `var preset: Preset`, `var text: String` (each change re-runs)
    - `private(set) var result: DecideResponse?`, `private(set) var error: String?`, `private(set) var isUpdating: Bool`
    - `var rows: [ResultRow]` (current result in the preset's question order)
    - `func refreshModels() async`
  - `AppDelegate.app: AppModel` (replaces `AppDelegate.daemon`; use `app.daemon`)

Behaviour:
- Each change of `text`, `model` or `preset` cancels the running task, and (if a model is
  selected and the text is not blank) starts a new one that sleeps `debounce`, then calls `decide`.
  Cancelling the Swift task cancels the URLSession request, which closes the connection; Ollaya
  then skips a request still waiting in its queue.
- A cancelled task never writes `result`, `error` or `isUpdating`.
- Blank text or no model: nothing is sent; `result`, `error` cleared; `isUpdating = false`.
- Changing `preset` clears `result` at once (old rows belong to other questions). Changing
  `model` keeps the old rows (dimmed by the view) until the new answer arrives.
- On error: `error = error.localizedDescription`, `result = nil`.
- `refreshModels()`: on failure keep everything as is; otherwise set `models`, keep `model` if it
  is still installed, else select the first model (or `nil`).

- [ ] **Step 1: Write the failing tests** (`KararTests/AppModelTests.swift`)

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: build error, `cannot find 'AppModel' in scope`.

- [ ] **Step 3: Implement `Karar/AppModel.swift`**

```swift
import Foundation
import Observation

/// The main window's state. The `Daemon` comes from `AppDelegate`, which alone starts and stops it.
@MainActor @Observable
final class AppModel {
    typealias Decide = @MainActor (_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse
    typealias Tags = @MainActor () async throws -> [ModelInfo]

    let daemon: Daemon
    private(set) var models: [ModelInfo] = []
    var model: String? { didSet { if model != oldValue { run() } } }
    var preset = Preset.all[0] { didSet { if preset != oldValue { result = nil; run() } } }
    var text = "" { didSet { if text != oldValue { run() } } }
    private(set) var result: DecideResponse?
    private(set) var error: String?
    private(set) var isUpdating = false

    private let decide: Decide
    private let tags: Tags
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.debounce = debounce
    }

    /// The current answers, in the question set's order.
    var rows: [ResultRow] {
        guard let result else { return [] }
        return preset.questionIDs.compactMap { id in result.answers[id].map { ResultRow(id: id, answer: $0) } }
    }

    /// Reloads the installed models; keeps the selection if it is still installed.
    func refreshModels() async {
        guard let fresh = try? await tags() else { return }
        models = fresh
        if !fresh.contains(where: { $0.name == model }) {
            model = fresh.first?.name
        }
    }

    /// Live results (spec §3.2): cancel the request in flight, wait for typing to pause, ask again.
    private func run() {
        task?.cancel()
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            task = nil
            isUpdating = false
            result = nil
            error = nil
            return
        }
        let text = text, questions = preset.questions
        isUpdating = true
        task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let response = try await decide(model, text, questions)
                guard !Task.isCancelled else { return }
                result = response
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                self.error = error.localizedDescription
            }
            isUpdating = false
        }
    }
}
```

- [ ] **Step 4: Let `AppDelegate` own the `AppModel`** (replace the `AppDelegate` class and the
  window content in `Karar/KararApp.swift`)

```swift
/// Owns the engine's lifecycle at the app level, not the window: it must survive window
/// close/reopen and stop exactly once on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app: AppModel

    override init() {
        let client = OllayaClient.local
        app = AppModel(
            daemon: Daemon(probe: { await client.liveness() }, launch: Daemon.bundledLaunch),
            decide: { try await client.decide(model: $0, state: $1, questions: $2) },
            tags: { try await client.tags() }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted in the app; don't start a real engine under them.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await app.daemon.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.daemon.stop()
    }
}
```

and in `KararApp.body`: `StatusView(daemon: appDelegate.app.daemon)` (replaced in Task 5).

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`, including all `AppModelTests` and the
existing `DaemonTests`.

- [ ] **Step 6: Commit**

```bash
git add Karar/AppModel.swift KararTests/AppModelTests.swift Karar/KararApp.swift
git commit -m "Add AppModel with live decide updates, owned by AppDelegate"
```

---

### Task 5: Main window

**Files:**
- Create: `Karar/Views/MainView.swift`
- Delete: `Karar/StatusView.swift`
- Modify: `Karar/KararApp.swift` (window shows `MainView`)
- Modify: `Karar/Daemon.swift` (add `bundledVersion`)
- Modify: `project.yml` (embed script copies `VERSION`), then `xcodegen generate`
- Test: `KararTests/SmokeTests.swift` (append)

**Interfaces:**
- Consumes: `AppModel` (Task 4), `Preset.all` (Task 2), `ResultRow` (Task 3), `OllayaClient.local.version()`.
- Produces: `nonisolated static let Daemon.bundledVersion: String` (e.g. `"v0.3.2"`, `""` if missing).

Layout (spec §3.2, Phase 2 subset): sidebar "Models" lists installed models (selection = the
selected model; router models show "Router", others their parameter size); a caption at the
bottom of the sidebar shows the engine version and whether Karar started it, plus a warning when
the running engine's version differs from the bundled one (roadmap note). Toolbar: Model picker,
Question set picker. Detail: `TextEditor` on top, result rows below (label, answer, bar,
percentage), dimmed with a small spinner while updating, and an "Answered by <model> in <n> ms"
caption. Models are refreshed when the engine becomes running and whenever Karar becomes the
active app (so a model pulled with the CLI shows up after switching back).

- [ ] **Step 1: Write the failing test** (append inside `SmokeTests`)

```swift
    func testBundledOllayaVersionIsReadable() {
        XCTAssertTrue(Daemon.bundledVersion.hasPrefix("v"), Daemon.bundledVersion)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run the test command. Expected: build error, `type 'Daemon' has no member 'bundledVersion'`.

- [ ] **Step 3: Embed the version file and read it**

In `project.yml`, in the `Embed Ollaya` script, after the `cp "$src/share/doc/ollaya/"* …` line add:

```sh
          cp "$src/VERSION" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Ollaya/VERSION"
```

Then run `xcodegen generate`.

In `Karar/Daemon.swift`, inside `extension Daemon` (above `bundledLaunch`):

```swift
    /// The pinned Ollaya version inside the app ("v0.3.2"), copied from vendor/ollaya/VERSION.
    nonisolated static let bundledVersion: String =
        Bundle.main.url(forResource: "VERSION", withExtension: nil, subdirectory: "Ollaya")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
```

- [ ] **Step 4: Write `Karar/Views/MainView.swift`**

```swift
import SwiftUI

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @State private var engineVersion = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $app.model) {
                Section("Models") {
                    ForEach(app.models, id: \.name) { model in
                        LabeledContent(model.name,
                                       value: model.details.format == "router" ? "Router" : model.details.parameterSize)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { engineStatus }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Model", selection: $app.model) {
                    ForEach(app.models, id: \.name) { Text($0.name).tag(Optional($0.name)) }
                }
                Picker("Question set", selection: $app.preset) {
                    ForEach(Preset.all) { Text($0.name).tag($0) }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task(id: app.daemon.state) {
            guard case .running = app.daemon.state else { return }
            await app.refreshModels()
            engineVersion = (try? await OllayaClient.local.version()) ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await app.refreshModels() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.daemon.state {
        case .starting:
            ProgressView("Starting Ollaya…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Ollaya is not running", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await app.daemon.start() } }
            }
        case .running:
            if app.models.isEmpty {
                ContentUnavailableView("No models yet", systemImage: "shippingbox",
                                       description: Text("Run `ollaya pull laya` in Terminal, then come back to Karar."))
            } else {
                VStack(spacing: 0) {
                    TextEditor(text: $app.text)
                        .font(.body)
                        .padding(8)
                        .frame(minHeight: 120, idealHeight: 160, maxHeight: 240)
                    Divider()
                    results
                }
            }
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = app.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type or paste text above to see the answers.")
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(app.rows) { row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.answer).bold()
                            ProgressView(value: row.sureness).frame(width: 120)
                            Text(row.sureness, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                }
                .opacity(app.isUpdating ? 0.5 : 1)
                if let result = app.result {
                    Text("Answered by \(result.model) in \(result.totalDuration / 1_000_000) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if app.isUpdating {
                ProgressView().controlSize(.small).padding()
            }
        }
    }

    @ViewBuilder private var engineStatus: some View {
        if case .running(let owned) = app.daemon.state, !engineVersion.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollaya \(engineVersion) · \(owned ? "started by Karar" : "already running")")
                if !Daemon.bundledVersion.isEmpty, "v\(engineVersion)" != Daemon.bundledVersion {
                    Label("Karar was built for Ollaya \(Daemon.bundledVersion)", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 5: Show it and delete `StatusView`**

In `Karar/KararApp.swift` set the window content to `MainView(app: appDelegate.app)`, then:

```bash
git rm Karar/StatusView.swift
```

- [ ] **Step 6: Run the tests, then a Release build**

Run the test command. Expected: `** TEST SUCCEEDED **`.
Then:

```bash
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error:|warning:|\*\* '
cat build/Build/Products/Release/Karar.app/Contents/Resources/Ollaya/VERSION
```

Expected: `** BUILD SUCCEEDED **`, no new warnings from Karar sources, `v0.3.2`.

- [ ] **Step 7: Commit**

```bash
git add Karar/Views/MainView.swift Karar/KararApp.swift Karar/Daemon.swift project.yml \
        Karar.xcodeproj KararTests/SmokeTests.swift
git commit -m "Main window: models sidebar, pickers, live result rows"
```

---

### Task 6: Acceptance (done by the controller, not a subagent)

The user's CLI daemon (`/usr/local/bin/ollaya serve`, 0.3.2, models installed) is running on
11435. Do not stop it; if a check would need that, ask the user first and restart it the same way
afterwards.

- [ ] **Step 1: Adopt check.** `pgrep -fl 'ollaya serve'` (note the PID), `open build/Build/Products/Debug/Karar.app`
  (Debug build from the test run), wait 3 s, `pgrep -fl 'ollaya serve'` again: same single PID,
  no `Karar.app/Contents/MacOS/ollaya`. Quit Karar (`osascript -e 'quit app "Karar"'`), check the
  PID is still alive.
- [ ] **Step 2: Latency.** With the user's daemon and installed models, measure warm and cold
  `/api/decide` for each preset on `laya` / `laya:en` / `laya:multilingual` (scratch script, not
  committed). Record the numbers in the roadmap "Notes for later phases".
- [ ] **Step 3: UI check by the user.** Karar has no AppleScript/Accessibility access: ask the user
  to confirm by eye: sidebar lists the installed models and the footer says
  "Ollaya 0.3.2 · already running"; typing updates the rows (spinner, dimmed rows, then new rows);
  switching model or question set re-runs; "Answered by … in … ms" shows the latency.
- [ ] **Step 4: Roadmap.** Tick Phase 2, add notes, commit.
