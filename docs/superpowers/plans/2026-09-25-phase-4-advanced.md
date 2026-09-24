# Phase 4 — Advanced mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One **Advanced** toggle turns the answers into editable question cards (choice / score /
noul, add / remove) and opens an inspector (model, route, timings, tokens, response JSON, Copy JSON,
Copy as curl). "My questions…" is a question set built in the UI. A `422` marks the card named by
`detail[].loc`. ⌘↩ pins the input and answers to the sidebar. In both modes, a token counter under
the editor shows `usage.input_tokens`, or an orange warning when `state_truncated` is true.

**Architecture:** `DecideResponse` gains `usage`, `routing`, `state_truncated`, `eval_duration`,
`load_duration` and the raw body; `OllayaError` gains `detail` (validation issues) and
`OllayaClient` builds the curl command. `OrderedJSON` reads JSON members in document order and
re-indents compact JSON (both stdlib parsers lose key order). `Question` is the editable form of a
question: parsed from a question-set JSON object, written back in order. `AppModel` holds the
questions in use (a preset's, or "My questions" once edited), maps a `422` onto questions, and
keeps pins. `QuestionCard` and `InspectorView` are new views; `MainView` gets the counter, the
toggle, the pins and the "My questions…" entry.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, XcodeGen, Xcode 27.

## Global Constraints

- macOS deployment target `14.0`, `ARCHS = arm64`. No third-party Swift dependencies.
  SwiftUI + Foundation only; AppKit only where SwiftUI lacks it (here: `NSPasteboard`).
- Bundle ID `io.github.omerhakanbilici.karar`. Hardened Runtime on. Ad-hoc signing.
- Ollaya pinned to `v0.3.2`; HTTP contract: `https://github.com/ollaya-dev/ollaya/blob/v0.3.2/docs/api.md`
  (§4.4 validation issues and `detail[].loc`, §5 questions and limits, §5.4 answer shapes, §7.3
  `/api/decide` response, §9 routing). Not `main`.
- System semantic colours only (`.primary`, `.secondary`, `.tertiary`, `.quinary`, `.tint`,
  `.separator`, `Color(nsColor: .textBackgroundColor)`, materials). **Two exceptions only** (spec §4):
  `.orange` for the truncation warning, `.red` for a question card with a validation error.
  UI text in English.
- `project.yml` is the source of truth; new files under `Karar/` or `KararTests/` need no project
  change (synced folders).
- The engine is started only by `AppDelegate` and stopped only in `applicationWillTerminate`.
  `AppModel` keeps taking the `Daemon` from `AppDelegate`. No view starts it.
- `DecideResponse` is decoded with a plain `JSONDecoder()` (never `.convertFromSnakeCase`: it would
  rename question ids such as `is_urgent` in `answers`). A preset's questions are sent byte for
  byte (`OllayaClient.decideBody` splices them); question and option order always follows the JSON
  document, never a Swift dictionary.
- Never touch the user's model store `~/.ollaya`. Real engine runs use `OLLAYA_MODELS=<scratch>`.
  The user's CLI daemon (`/usr/local/bin/ollaya serve`) may listen on 11435 and Karar adopts it;
  **ask the user before stopping it**, and restart it the same way afterwards.
- Out of scope (later phases): error banner, port-in-use banner, About window, app icon, saved
  custom question sets, persistent pins.

Test command used throughout (from repo root; needs `vendor/ollaya`, run `scripts/fetch-ollaya.sh` once):

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E 'error:|failed|passed|Executed|\*\* '
```

One test class: add `-only-testing:KararTests/<ClassName>` before `test`.

**UI check** (after every UI task; the controller does this, not a subagent):

```sh
S=<scratchpad>                          # $S/models holds laya, laya:en, laya:multilingual
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '
osascript -e 'tell application id "io.github.omerhakanbilici.karar" to quit'; sleep 2; pgrep -x Karar   # never pkill: it orphans ollaya
APP=build/Build/Products/Debug/Karar.app/Contents/MacOS/Karar
# light:  OLLAYA_MODELS=$S/models $APP -NSRequiresAquaSystemAppearance YES -KararText "…" &
# dark:   OLLAYA_MODELS=$S/models $APP -AppleInterfaceStyle Dark -KararText "…" &
# advanced mode: add  -advanced YES ; a custom set: add  -KararQuestions '{"q": {"type": "score", "criteria": ["a"]}}'
cat > $S/winid.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let karar = list.filter { $0[kCGWindowOwnerName as String] as? String == "Karar" && $0[kCGWindowLayer as String] as? Int == 0 }
let widest = karar.max { (($0[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) < (($1[kCGWindowBounds as String] as! [String: Any])["Width"] as! Double) }
print(widest?[kCGWindowNumber as String] as? Int ?? 0)
EOF
sleep 5; screencapture -x -o -l $(swift $S/winid.swift) $S/shot.png   # then Read $S/shot.png
```

`-KararText` / `-KararQuestions` are DEBUG-only launch arguments added in Task 5, because typing
into the app needs the user (no Accessibility). `-advanced YES` sets the `@AppStorage("advanced")`
value through the argument domain. Judge every capture: alignment, spacing, cramped or raw-looking
parts, line breaks or jumps in live-updating text, light and dark.

## Facts measured before writing this plan

(Pinned engine from `vendor/ollaya`, `OLLAYA_HOST=127.0.0.1:11436`, scratch `OLLAYA_MODELS`; the
same notes are in the roadmap.)

- `usage.input_tokens` = Σ over questions of (text + that question's instructions + options +
  special tokens). One noul question: 48; the same question twice: 96; empty text: 32. **The user
  chose** to show this number as is ("1,840 tokens") with a tooltip that explains it counts the
  text once per question (spec §3.2 updated).
- After truncation the count is the truncated one: each question is capped at the model's context
  (512 on `laya:en`, 1,024 on `laya:multilingual`), with `state_truncated: true`.
- A real `422` (three bad questions at once):

  ```json
  {"error":"questions.q.score.criteria: List should have at least 2 items after validation, not 1; questions.a b.choice.criteria: Dictionary should have at least 2 items after validation, not 0; questions.n.noul.criteria.true: Input should be a string, an object, an array or null","code":"INVALID_REQUEST","detail":[{"loc":["body","questions","q","score","criteria"],"msg":"List should have at least 2 items after validation, not 1","type":"too_short","ctx":{"field_type":"List","min_length":2,"actual_length":1}},{"loc":["body","questions","a b","choice","criteria"],"msg":"Dictionary should have at least 2 items after validation, not 0","type":"too_short","ctx":{"field_type":"Dictionary","min_length":2,"actual_length":0}},{"loc":["body","questions","n","noul","criteria","true"],"msg":"Input should be a string, an object, an array or null","type":"json_type"}]}
  ```

- `/api/decide` answers compact JSON on one line. `JSONSerialization` pretty-printing reorders keys
  and prints `0.3237` as `0.32369999999999999`, so the inspector re-indents the bytes.
- Presets: every instruction and description is a string, except `guard.topic`'s six options,
  whose descriptions are `null`. Choice criteria are objects; score criteria are arrays of strings.
- **The user chose** system red for an invalid card (spec §4 and CLAUDE.md updated).

## Design decisions (no user input needed)

- "My questions…" starts as a copy of the questions on screen. Editing any card also switches the
  set to "My questions" (toolbar label changes), so the preset stays as shipped. Choosing a preset
  keeps "My questions" in memory; "My questions…" brings them back. Nothing is saved to disk
  (spec §2).
- A new question is `question_<n>`, type `noul`, empty instructions (the model then reads the id,
  api.md §5.2). Changing a card's type resets its options to that type's template.
- Empty instructions are left out of the request; an empty option description is sent as `null`
  (choice) or left out (noul). Score levels are always sent as strings.
- Two questions with the same id cannot be sent as a JSON object: Karar sends nothing and marks
  both cards "Another question has the same id." Every other rule (option counts, …) is the
  engine's, reported through `422`.
- Simple mode with an invalid custom set says "Some questions are not valid. Turn on Advanced to
  see which."
- The counter sits in a fixed-height row just under the editor's bottom-right corner (inside the
  editor it would cover the text, and the warning is long).
- Clicking a pin restores its model, question set and text; the live result runs again. The
  pinned answers show in the pin's tooltip.

## File structure

- Modify `Karar/OllayaAPI.swift`: `DecideResponse` fields, `Answer.probabilities` (replaces `legend`),
  `OllayaError.detail`.
- Modify `Karar/OllayaClient.swift`: `decide` keeps the raw body; `curl(body:)`.
- Create `Karar/OrderedJSON.swift`: `members(of:)`, `pretty(_:)`.
- Modify `Karar/Preset.swift`: `topLevelKeys` uses `OrderedJSON`.
- Modify `Karar/ResultRow.swift`: score levels from `probabilities`.
- Create `Karar/Question.swift`: `Question`, parse, JSON, templates, duplicates, `Answer.rawText`.
- Modify `Karar/AppModel.swift`: questions / "My questions", question errors, request body, pins.
- Modify `Karar/KararApp.swift`: DEBUG launch arguments.
- Modify `Karar/Views/MainView.swift`: counter, pins, toolbar, advanced layout.
- Create `Karar/Views/QuestionCard.swift`, `Karar/Views/InspectorView.swift`.
- Tests: modify `KararTests/OllayaClientTests.swift`, `ResultRowTests.swift`, `AppModelTests.swift`;
  create `KararTests/OrderedJSONTests.swift`, `KararTests/QuestionTests.swift`.

---

### Task 1: Response fields, validation issues, curl

**Files:**
- Modify: `Karar/OllayaAPI.swift`
- Modify: `Karar/OllayaClient.swift` (`decide`, new `curl(body:)`)
- Modify: `Karar/ResultRow.swift` (score case)
- Test: `KararTests/OllayaClientTests.swift`, `KararTests/ResultRowTests.swift`, `KararTests/AppModelTests.swift` (fake only)

**Interfaces:**
- Produces:
  - `DecideResponse` keeps `model: String`, `answers: [String: Answer]`, `totalDuration: Int64` and
    adds `var evalDuration: Int64?`, `var loadDuration: Int64?`, `var usage: DecideResponse.Usage?`
    (`inputTokens: Int`), `var routing: DecideResponse.Routing?` (`route: String`, `reason: String`),
    `var stateTruncated: Bool?`, `var json: Data` (raw body, not decoded; default `Data()`).
    Memberwise init `DecideResponse(model:answers:totalDuration:)` still compiles.
  - `Answer(type:choice:score:noul:confidence:probabilities:)`, `probabilities: [String: Double]?`
    (the `legend` field is gone).
  - `OllayaError(error:code:detail:)` with `var detail: [OllayaError.Issue]? = nil`;
    `Issue(loc: [OllayaError.Loc], msg: String)`, `Issue.questionID: String?`;
    `enum Loc { case key(String), index(Int) }`.
  - `OllayaClient.curl(body: Data) -> String`.

- [ ] **Step 1: Write the failing tests**

In `KararTests/OllayaClientTests.swift`, in `testDecodesDecideResponseFromTheAPIDoc`, replace
`XCTAssertEqual(r.answers["urgency"]?.legend?.count, 3)` with the lines below, and add the new
tests to the class:

```swift
        XCTAssertEqual(r.answers["urgency"]?.probabilities?.count, 3)
        XCTAssertEqual(r.usage?.inputTokens, 118)
        XCTAssertEqual(r.routing?.route, "english")
        XCTAssertEqual(r.routing?.reason, "English Latin text")
        XCTAssertEqual(r.stateTruncated, false)
        XCTAssertEqual(r.evalDuration, 16_302_117)
        XCTAssertEqual(r.loadDuration, 0)
```

```swift
    func testDecodesATruncatedResponseWithoutARouter() throws {
        let json = #"""
        {"model": "laya:en", "answers": {}, "usage": {"input_tokens": 512, "output_tokens": 0},
         "routing": null, "state_truncated": true, "total_duration": 1, "eval_duration": 1}
        """#
        let r = try JSONDecoder().decode(DecideResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.usage?.inputTokens, 512)
        XCTAssertEqual(r.stateTruncated, true)
        XCTAssertNil(r.routing)
    }

    func testAValidationErrorNamesItsQuestions() throws {
        // Recorded from the pinned engine (docs/api.md §4.4), plus a state issue.
        let body = Data(#"""
        {"error":"state: Field required; questions.q.score.criteria: List should have at least 2 items after validation, not 1; questions.a b.choice.criteria: Dictionary should have at least 2 items after validation, not 0","code":"INVALID_REQUEST","detail":[{"loc":["body","state"],"msg":"Field required","type":"missing"},{"loc":["body","questions","q","score","criteria"],"msg":"List should have at least 2 items after validation, not 1","type":"too_short","ctx":{"field_type":"List","min_length":2,"actual_length":1}},{"loc":["body","questions","a b","choice","criteria"],"msg":"Dictionary should have at least 2 items after validation, not 0","type":"too_short","ctx":{"field_type":"Dictionary","min_length":2,"actual_length":0}}]}
        """#.utf8)
        let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 422, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try OllayaClient.check(response, body)) { error in
            let detail = (error as? OllayaError)?.detail ?? []
            XCTAssertEqual(detail.map(\.questionID), [nil, "q", "a b"])
            XCTAssertEqual(detail[1].msg, "List should have at least 2 items after validation, not 1")
            XCTAssertEqual(detail[1].loc, [.key("body"), .key("questions"), .key("q"), .key("score"), .key("criteria")])
        }
    }

    func testAnIndexInALocIsAnInt() throws {
        let issue = try JSONDecoder().decode(OllayaError.Issue.self, from: Data(#"{"loc": ["body", "questions", "1", 0], "msg": "x"}"#.utf8))
        XCTAssertEqual(issue.loc, [.key("body"), .key("questions"), .key("1"), .index(0)])
        XCTAssertEqual(issue.questionID, "1")
    }

    func testCurlQuotesTheBodyForTheShell() throws {
        let body = try OllayaClient.decideBody(model: "laya", state: "It's \"late\"\nand $HOME `x`", questions: Data(#"{"q": {"type": "noul"}}"#.utf8))
        let command = OllayaClient.local.curl(body: body)
        XCTAssertTrue(command.hasPrefix("curl http://127.0.0.1:11435/api/decide -d '"), command)
        // A shell function named curl prints the -d argument, so this checks what a shell really passes.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "curl() { printf %s \"$3\"; }; " + command]
        let out = Pipe()
        shell.standardOutput = out
        try shell.run()
        shell.waitUntilExit()
        XCTAssertEqual(out.fileHandleForReading.readDataToEndOfFile(), body)
    }
```

In `KararTests/ResultRowTests.swift`, replace the `answer(...)` helper:

```swift
    private func answer(_ type: String, choice: String? = nil, score: Double? = nil, noul: Double? = nil,
                        confidence: Double? = nil, levels: Int? = nil) -> Answer {
        Answer(type: type, choice: choice, score: score, noul: noul, confidence: confidence,
               probabilities: levels.map { n in Dictionary(uniqueKeysWithValues: (0..<n).map { ("\($0)", 1 / Double(n)) }) })
    }
```

In `KararTests/AppModelTests.swift`, in `FakeOllaya.decide`, replace the `yes` line:

```swift
        let yes = Answer(type: "noul", choice: nil, score: nil, noul: 0.9, confidence: nil, probabilities: nil)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: build errors (`probabilities`, `usage`, `detail`, `curl` unknown).

- [ ] **Step 3: Implement**

In `Karar/OllayaAPI.swift`, replace `OllayaError`, `DecideResponse` and `Answer` with:

```swift
struct OllayaError: Error, Decodable, Sendable, LocalizedError {
    let error: String
    let code: String?
    var detail: [Issue]? = nil   // validation issues (docs/api.md §4.4), for 422s

    var errorDescription: String? { error }

    /// One validation problem. `loc` is the path to the bad value: `"body"`, then keys and indexes;
    /// inside a question its type follows its id (`["body", "questions", "urgency", "score", "criteria"]`).
    struct Issue: Decodable, Hashable, Sendable {
        let loc: [Loc]
        let msg: String

        /// The question the issue is about, if any.
        var questionID: String? {
            guard loc.count > 2, loc[0] == .key("body"), loc[1] == .key("questions"), case .key(let id) = loc[2] else {
                return nil
            }
            return id
        }
    }

    enum Loc: Decodable, Hashable, Sendable {
        case key(String)
        case index(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
            } else {
                self = .key(try container.decode(String.self))
            }
        }
    }
}

/// `POST /api/decide` response (docs/api.md §7.3). Decode with a plain `JSONDecoder()`:
/// `.convertFromSnakeCase` would also rewrite the caller's question ids in `answers`
/// (`is_urgent` → `isUrgent`).
struct DecideResponse: Decodable, Sendable {
    let model: String            // the model that answered (a router's target)
    let answers: [String: Answer]
    let totalDuration: Int64     // nanoseconds
    var evalDuration: Int64?
    var loadDuration: Int64?
    var usage: Usage?
    var routing: Routing?        // only for a router
    var stateTruncated: Bool?
    /// The body as the server sent it, for the inspector. Set by `OllayaClient.decide`.
    var json = Data()

    /// `inputTokens` counts the text once per question, with that question's instructions and
    /// options, summed over the questions; a truncated text counts as cut (measured, Phase 4).
    struct Usage: Decodable, Hashable, Sendable {
        let inputTokens: Int
        enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
    }

    struct Routing: Decodable, Hashable, Sendable {
        let route: String        // `english`, `multilingual`
        let reason: String       // in words; informative only
    }

    enum CodingKeys: String, CodingKey {
        case model, answers, usage, routing
        case totalDuration = "total_duration"
        case evalDuration = "eval_duration"
        case loadDuration = "load_duration"
        case stateTruncated = "state_truncated"
    }
}

/// One answer; which fields are set depends on `type` (docs/api.md §5.4). `probabilities` is keyed
/// by label (choice) or level `"0"`… (score); a Swift dictionary, so its order is not the criteria's.
struct Answer: Decodable, Hashable, Sendable {
    let type: String             // "choice", "score" or "noul"
    let choice: String?
    let score: Double?
    let noul: Double?
    let confidence: Double?
    let probabilities: [String: Double]?
}
```

(`legend` is dropped: its values may be objects or arrays for custom questions, which
`[String: String]` would fail to decode, and Karar only needed the level count.)

In `Karar/OllayaClient.swift`, replace the last line of `decide` (`return try JSONDecoder()…`) with:

```swift
        var decoded = try JSONDecoder().decode(DecideResponse.self, from: data)
        decoded.json = data
        return decoded
```

and add after `decideBody`:

```swift
    /// The request as a Terminal command (inspector's "Copy as curl"). The body goes in single
    /// quotes, so only `'` needs escaping.
    func curl(body: Data) -> String {
        let quoted = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "'", with: #"'\''"#)
        return "curl \(base.appending(path: "api/decide").absoluteString) -d '\(quoted)'"
    }
```

In `Karar/ResultRow.swift`, in the `score` case, replace the `top` line:

```swift
            let top = max((a.probabilities?.count ?? 2) - 1, 1)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Karar/OllayaAPI.swift Karar/OllayaClient.swift Karar/ResultRow.swift KararTests
git commit -m "Decode usage, routing, truncation and validation issues; build curl commands"
```

---

### Task 2: `OrderedJSON`

**Files:**
- Create: `Karar/OrderedJSON.swift`
- Modify: `Karar/Preset.swift` (`topLevelKeys`)
- Test: `KararTests/OrderedJSONTests.swift` (the existing `PresetTests.testTopLevelKeysSkipNestedKeysAndStringContents` must keep passing)

**Interfaces:**
- Produces: `OrderedJSON.members(of: Data) -> [(key: String, value: Data)]` (value = that member's
  JSON text, possibly with surrounding whitespace); `OrderedJSON.pretty(_ json: Data) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `KararTests/OrderedJSONTests.swift`:

```swift
import XCTest
@testable import Karar

final class OrderedJSONTests: XCTestCase {
    func testMembersKeepDocumentOrderAndTheirValues() {
        let json = #"{"b": {"x": [1, 2]}, "a" : "s,}\"", "c":null}"#
        let members = OrderedJSON.members(of: Data(json.utf8))
        XCTAssertEqual(members.map(\.key), ["b", "a", "c"])
        XCTAssertEqual(members.map { String(decoding: $0.value, as: UTF8.self).trimmingCharacters(in: .whitespaces) },
                       [#"{"x": [1, 2]}"#, #""s,}\"""#, "null"])
    }

    func testMembersOfSomethingElseAreEmpty() {
        XCTAssertTrue(OrderedJSON.members(of: Data("[1, 2]".utf8)).isEmpty)
        XCTAssertTrue(OrderedJSON.members(of: Data(#""a:b""#.utf8)).isEmpty)
    }

    func testPrettyKeepsOrderAndNumbers() {
        let json = #"{"b":{"x":0.3237,"e":{},"s":"a,{\"b"},"a":[1,2],"z":[]}"#
        XCTAssertEqual(OrderedJSON.pretty(Data(json.utf8)), #"""
        {
          "b": {
            "x": 0.3237,
            "e": {},
            "s": "a,{\"b"
          },
          "a": [
            1,
            2
          ],
          "z": []
        }
        """#)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:KararTests/OrderedJSONTests`. Expected: build error, `OrderedJSON` unknown.

- [ ] **Step 3: Implement**

Create `Karar/OrderedJSON.swift`:

```swift
import Foundation

/// JSON read without losing key order: JSONDecoder and JSONSerialization both drop it, and here
/// order is meaning (question order, option order). Assumes valid JSON.
enum OrderedJSON {
    /// The members of a JSON object in document order, each value as its own JSON text. Anything
    /// that is not an object has no members.
    static func members(of json: Data) -> [(key: String, value: Data)] {
        let bytes = [UInt8](json)
        var members: [(key: String, value: Data)] = []
        var depth = 0
        var key: String?              // the member being read
        var valueStart = 0
        var pending: Range<Int>?      // a string at depth 1 where a key may be: a key if a ':' follows
        func finish(at end: Int) {
            if let key { members.append((key, Data(bytes[valueStart..<end]))) }
            key = nil
            pending = nil
        }
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                let start = i
                i = endOfString(bytes, from: i)
                pending = depth == 1 && key == nil ? start..<(i + 1) : nil
            case UInt8(ascii: ":"):
                if depth == 1, key == nil, let range = pending {
                    key = try? JSONDecoder().decode(String.self, from: Data(bytes[range]))
                    valueStart = i + 1
                }
                pending = nil
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if depth == 1 { finish(at: i) }
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 1 { finish(at: i) }
            default:
                break
            }
            i += 1
        }
        return members
    }

    /// Compact JSON laid out for reading with a two-space indent. Keys and numbers stay exactly as
    /// sent (JSONSerialization would reorder keys and print 0.3237 as 0.32369999999999999).
    static func pretty(_ json: Data) -> String {
        let bytes = [UInt8](json)
        var out: [UInt8] = []
        var depth = 0
        func newline() {
            out.append(UInt8(ascii: "\n"))
            out += repeatElement(UInt8(ascii: " "), count: max(0, 2 * depth))
        }
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            switch byte {
            case UInt8(ascii: "\""):
                let end = endOfString(bytes, from: i)
                out += bytes[i...end]
                i = end
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                out.append(byte)
                let close = byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                var next = i + 1
                while next < bytes.count, isWhitespace(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == close {   // `{}` and `[]` stay on one line
                    out.append(close)
                    i = next
                } else {
                    depth += 1
                    newline()
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                newline()
                out.append(byte)
            case UInt8(ascii: ","):
                out.append(byte)
                newline()
            case UInt8(ascii: ":"):
                out += [UInt8(ascii: ":"), UInt8(ascii: " ")]
            default:
                if !isWhitespace(byte) { out.append(byte) }
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The index of the quote that closes the string opening at `open`.
    private static func endOfString(_ bytes: [UInt8], from open: Int) -> Int {
        var i = open + 1
        while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
            i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
        }
        return min(i, bytes.count - 1)
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t")
    }
}
```

In `Karar/Preset.swift`, replace the whole `topLevelKeys(of:)` function (doc comment and body) with:

```swift
    /// The keys of a JSON object in document order (JSONDecoder and JSONSerialization both lose it).
    static func topLevelKeys(of json: Data) -> [String] {
        OrderedJSON.members(of: json).map(\.key)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **` (including `PresetTests`).

- [ ] **Step 5: Commit**

```bash
git add Karar/OrderedJSON.swift Karar/Preset.swift KararTests/OrderedJSONTests.swift
git commit -m "Add OrderedJSON: members in document order and order-keeping pretty print"
```

---

### Task 3: `Question`

**Files:**
- Create: `Karar/Question.swift`
- Test: `KararTests/QuestionTests.swift`

**Interfaces:**
- Consumes: `OrderedJSON.members(of:)` (Task 2), `Answer` (Task 1), `Preset.all`.
- Produces:
  - `struct Question: Identifiable, Hashable, Sendable` with `var id: UUID` (card identity),
    `var key: String` (the question id sent to the engine), `var kind: Question.Kind`,
    `var instructions: String`, `var options: [Question.Option]`.
  - `enum Question.Kind: String, CaseIterable { case choice, score, noul }`.
  - `struct Question.Option: Identifiable, Hashable, Sendable { var id = UUID(); var label = ""; var text = "" }`
    — choice: label + description; score: level description in `text` (level 0 first); noul:
    exactly two options, labels `"true"` and `"false"`, descriptions in `text`.
  - `Question(key:kind:)` (options from the template), `mutating func change(to: Kind)`,
    `static func template(_: Kind) -> [Option]`, `static func parse(_ json: Data) -> [Question]`,
    `static func json(_ questions: [Question]) -> Data`, `static func duplicateKeys(_: [Question]) -> Set<String>`.
  - `extension Answer { var rawText: String }`.

- [ ] **Step 1: Write the failing tests**

Create `KararTests/QuestionTests.swift`:

```swift
import XCTest
@testable import Karar

final class QuestionTests: XCTestCase {
    func testEveryPresetSurvivesARoundTrip() throws {
        for preset in Preset.all {
            let questions = Question.parse(preset.questions)
            XCTAssertEqual(questions.map(\.key), preset.questionIDs, preset.id)
            let written = Question.json(questions)
            XCTAssertEqual(OrderedJSON.members(of: written).map(\.key), preset.questionIDs, preset.id)
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: preset.questions) as? NSDictionary)
            let copy = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? NSDictionary, String(decoding: written, as: UTF8.self))
            XCTAssertEqual(copy, original, preset.id)
        }
    }

    func testParseKeepsOptionOrderAndReadsEveryKind() {
        let triage = Question.parse(Preset.all[0].questions)
        XCTAssertEqual(triage[0].kind, .choice)
        XCTAssertEqual(triage[0].options.map(\.label),
                       ["refund", "technical_help", "billing_question", "information", "cancellation", "other"])
        XCTAssertEqual(triage[0].options[0].text, "money returned or a duplicate charge reversed")
        XCTAssertEqual(triage[2].kind, .score)
        XCTAssertEqual(triage[2].options.map(\.text).first, "calm and neutral")
        XCTAssertEqual(triage[1].kind, .noul)
        XCTAssertEqual(triage[1].options.map(\.label), ["true", "false"])
        XCTAssertEqual(triage[1].instructions, "Does `message` communicate time pressure or a deadline?")
    }

    func testChoiceLabelsMayBeAnArray() {
        let questions = Question.parse(Data(#"{"tone": {"type": "choice", "criteria": ["calm", "angry"]}}"#.utf8))
        XCTAssertEqual(questions.first?.options.map(\.label), ["calm", "angry"])
        XCTAssertEqual(questions.first?.instructions, "")
    }

    func testJSONLeavesOutWhatIsEmpty() throws {
        var noul = Question(key: "is_spam", kind: .noul)
        var choice = Question(key: "tone", kind: .choice)
        choice.options[1].text = "angry words"
        noul.options[0].text = "bulk mail"
        var score = Question(key: "urgency", kind: .score)
        score.instructions = "How urgent?"
        let json = Question.json([noul, choice, score])
        XCTAssertEqual(String(decoding: json, as: UTF8.self), #"""
        {"is_spam":{"type":"noul","criteria":{"true":"bulk mail"}},"tone":{"type":"choice","criteria":{"option_1":null,"option_2":"angry words"}},"urgency":{"type":"score","instructions":"How urgent?","criteria":["low","medium","high"]}}
        """#)
    }

    func testChangingTheKindResetsTheOptions() {
        var question = Question(key: "q", kind: .choice)
        question.options.append(.init(label: "third"))
        question.change(to: .noul)
        XCTAssertEqual(question.kind, .noul)
        XCTAssertEqual(question.options.map(\.label), ["true", "false"])
        question.change(to: .noul)
        XCTAssertEqual(question.options.count, 2)
    }

    func testDuplicateKeys() {
        let questions = [Question(key: "a", kind: .noul), Question(key: "b", kind: .noul), Question(key: "a", kind: .score)]
        XCTAssertEqual(Question.duplicateKeys(questions), ["a"])
        XCTAssertEqual(Question.duplicateKeys(Array(questions.prefix(2))), [])
    }

    func testRawTextShowsTheEnginesNumbers() {
        XCTAssertEqual(Answer(type: "choice", choice: "billing", score: nil, noul: nil, confidence: 0.7781, probabilities: nil).rawText,
                       "billing · confidence 0.78")
        XCTAssertEqual(Answer(type: "score", choice: nil, score: 1.1982, noul: nil, confidence: 0.3418, probabilities: nil).rawText,
                       "1.20 · confidence 0.34")
        XCTAssertEqual(Answer(type: "noul", choice: nil, score: nil, noul: 0.9127, confidence: nil, probabilities: nil).rawText,
                       "0.91")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:KararTests/QuestionTests`. Expected: build error, `Question` unknown.

- [ ] **Step 3: Implement**

Create `Karar/Question.swift`:

```swift
import Foundation

/// One question as an advanced-mode card edits it (spec §3.2; schema in docs/api.md §5.2). Read
/// from a question set's JSON and written back in the same order.
struct Question: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case choice, score, noul
    }

    /// A row under the question. choice: a label and its description; score: a level's
    /// description in `text`, level 0 first; noul: always two, `true` and `false`.
    struct Option: Identifiable, Hashable, Sendable {
        var id = UUID()
        var label = ""
        var text = ""
    }

    var id = UUID()              // the card's identity; survives edits of `key`
    var key: String              // the question id in the request, e.g. `is_urgent`
    var kind: Kind
    var instructions = ""
    var options: [Option]

    init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
        options = Self.template(kind)
    }

    static func template(_ kind: Kind) -> [Option] {
        switch kind {
        case .choice: [Option(label: "option_1"), Option(label: "option_2")]
        case .score: [Option(text: "low"), Option(text: "medium"), Option(text: "high")]
        case .noul: [Option(label: "true"), Option(label: "false")]
        }
    }

    /// A new type starts from that type's template.
    mutating func change(to kind: Kind) {
        guard kind != self.kind else { return }
        self.kind = kind
        options = Self.template(kind)
    }

    /// The questions of a question-set JSON object, in document order. Descriptions that are
    /// `null` become "". ponytail: a description that is a JSON object or array also becomes ""
    /// (no bundled preset has one, and the cards only edit text); keep its JSON text if that changes.
    static func parse(_ json: Data) -> [Question] {
        OrderedJSON.members(of: json).compactMap { key, value in
            let field = fields(of: value)
            guard let kind = field["type"].flatMap(string).flatMap(Kind.init(rawValue:)) else { return nil }
            var question = Question(key: key, kind: kind)
            question.instructions = field["instructions"].flatMap(string) ?? ""
            guard let criteria = field["criteria"] else { return question }
            let isArray = criteria.first { !(" \n\r\t".utf8.contains($0)) } == UInt8(ascii: "[")
            switch kind {
            case .choice where isArray:
                question.options = ((try? JSONDecoder().decode([String].self, from: criteria)) ?? []).map { Option(label: $0) }
            case .choice:
                question.options = OrderedJSON.members(of: criteria).map { Option(label: $0.key, text: string($0.value) ?? "") }
            case .score:
                question.options = ((try? JSONDecoder().decode([String?].self, from: criteria)) ?? []).map { Option(text: $0 ?? "") }
            case .noul:
                let texts = fields(of: criteria)
                question.options = [Option(label: "true", text: texts["true"].flatMap(string) ?? ""),
                                    Option(label: "false", text: texts["false"].flatMap(string) ?? "")]
            }
            return question
        }
    }

    /// The request's `questions` object, in card order. Empty instructions are left out (the model
    /// then reads the id, docs/api.md §5.2); an empty choice description is `null`, an empty noul
    /// description is left out.
    static func json(_ questions: [Question]) -> Data {
        object(questions.map { ($0.key, $0.json) })
    }

    /// Ids used by more than one question: such a set cannot be sent as a JSON object.
    static func duplicateKeys(_ questions: [Question]) -> Set<String> {
        Set(Dictionary(grouping: questions, by: \.key).filter { $0.value.count > 1 }.keys)
    }

    private var json: Data {
        var fields = [("type", Self.encode(kind.rawValue))]
        if !instructions.isEmpty { fields.append(("instructions", Self.encode(instructions))) }
        switch kind {
        case .choice:
            fields.append(("criteria", Self.object(options.map { ($0.label, $0.text.isEmpty ? Data("null".utf8) : Self.encode($0.text)) })))
        case .score:
            fields.append(("criteria", Data("[".utf8) + Data(options.map { Self.encode($0.text) }.joined(separator: Data(",".utf8))) + Data("]".utf8)))
        case .noul:
            let described = options.filter { !$0.text.isEmpty }
            if !described.isEmpty {
                fields.append(("criteria", Self.object(described.map { ($0.label, Self.encode($0.text)) })))
            }
        }
        return Self.object(fields)
    }

    private static func object(_ members: [(String, Data)]) -> Data {
        Data("{".utf8) + Data(members.map { encode($0.0) + Data(":".utf8) + $0.1 }.joined(separator: Data(",".utf8))) + Data("}".utf8)
    }

    private static func encode(_ string: String) -> Data {
        (try? JSONEncoder().encode(string)) ?? Data(#""""#.utf8)
    }

    private static func string(_ json: Data) -> String? {
        try? JSONDecoder().decode(String.self, from: json)
    }

    private static func fields(of json: Data) -> [String: Data] {
        Dictionary(OrderedJSON.members(of: json).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Answer {
    /// The value as the engine returned it, for the advanced cards (spec §3.2: raw value and
    /// confidence). noul has no confidence (docs/api.md §5.4).
    var rawText: String {
        switch type {
        case "noul": String(format: "%.2f", noul ?? 0)
        case "score": String(format: "%.2f · confidence %.2f", score ?? 0, confidence ?? 0)
        default: "\(choice ?? type) · " + String(format: "confidence %.2f", confidence ?? 0)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Karar/Question.swift KararTests/QuestionTests.swift
git commit -m "Add Question: the editable form of a question set, parsed and written in order"
```

---

### Task 4: `AppModel`: "My questions", question errors, request body, pins

**Files:**
- Modify: `Karar/AppModel.swift`
- Test: `KararTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `Question` (Task 3), `OllayaError.detail` / `Issue.questionID` (Task 1),
  `OllayaClient.decideBody` (existing, static).
- Produces (all `@MainActor` on `AppModel`):
  - `var questions: [Question]` (get/set; a set that changes anything makes the set custom and re-runs),
    `private(set) var isCustom: Bool`, `func useMyQuestions()`, `func addQuestion()`.
  - `private(set) var questionErrors: [String: String]` (question key → message).
  - `var requestBody: Data?` (the `/api/decide` body for the current input, or nil).
  - `struct Pin: Identifiable` (`text`, `model`, `setName`, `preset`, `questions: [Question]?`,
    `rows: [ResultRow]`, `title`), `private(set) var pins: [Pin]`, `func pin()`,
    `func restore(_: Pin)`, `func unpin(_: Pin)`.
  - `preset` keeps its type; `rows` now follow `questions`.

- [ ] **Step 1: Write the failing tests**

Add to `AppModelTests`:

```swift
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
        XCTAssertTrue(app.isCustom)
        XCTAssertEqual(app.questions.count, 4)
    }

    func testNothingToPinWithoutAnAnswer() {
        let app = makeApp(FakeOllaya())
        app.pin()
        XCTAssertTrue(app.pins.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:KararTests/AppModelTests`. Expected: build errors (`questions`, `pin`, … unknown).

- [ ] **Step 3: Implement**

In `Karar/AppModel.swift`:

Replace the `preset` property line with:

```swift
    /// The question set in use when `isCustom` is false. Choosing a preset (even the one on screen)
    /// leaves "My questions", which stay in memory for `useMyQuestions()`.
    var preset = Preset.all[0] { didSet { if preset != oldValue || isCustom { usePreset() } } }
    /// The questions in use, in order: the preset's, or "My questions" once any is edited (spec §3.2).
    var questions: [Question] {
        get { currentQuestions }
        set {
            guard newValue != currentQuestions else { return }
            currentQuestions = newValue
            isCustom = true
            run()
        }
    }
    private(set) var isCustom = false
    /// Validation messages by question id: from a 422's `detail[].loc` (spec §5), or a duplicate id.
    private(set) var questionErrors: [String: String] = [:]
    private(set) var pins: [Pin] = []
```

Add to the private stored properties (next to `private var task`):

```swift
    private var currentQuestions = Question.parse(Preset.all[0].questions)
    private var myQuestions: [Question]?   // kept while a preset is in use
```

Replace the `rows` property with:

```swift
    /// The current answers, in the questions' order.
    var rows: [ResultRow] {
        guard let result else { return [] }
        return currentQuestions.compactMap { q in result.answers[q.key].map { ResultRow(id: q.key, answer: $0) } }
    }

    /// The `/api/decide` body for the current input, for "Copy as curl".
    var requestBody: Data? {
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? OllayaClient.decideBody(model: model, state: text, questions: questionsJSON)
    }

    /// A preset is sent byte for byte; "My questions" are written in card order.
    private var questionsJSON: Data {
        isCustom ? Question.json(currentQuestions) : preset.questions
    }

    /// "My questions…" (spec §3.2): the set kept from before, or else a copy of the questions on screen.
    func useMyQuestions() {
        guard !isCustom else { return }
        if let myQuestions { currentQuestions = myQuestions }
        isCustom = true
        result = nil
        run()
    }

    func addQuestion() {
        var n = questions.count + 1
        while questions.contains(where: { $0.key == "question_\(n)" }) { n += 1 }
        questions.append(Question(key: "question_\(n)", kind: .noul))
    }

    private func usePreset() {
        if isCustom { myQuestions = currentQuestions }
        isCustom = false
        currentQuestions = Question.parse(preset.questions)
        result = nil
        run()
    }

    /// ⌘↩ (spec §3.2): keeps the input and its answers in the sidebar for this session.
    func pin() {
        guard let model, result != nil, !isUpdating else { return }
        pins.insert(Pin(text: text, model: model, setName: isCustom ? "My questions" : preset.name,
                        preset: preset, questions: isCustom ? currentQuestions : nil, rows: rows), at: 0)
    }

    /// Brings back a pin's model (if still installed), question set and text; the answers run again.
    func restore(_ pin: Pin) {
        if models.contains(where: { $0.name == pin.model }) { model = pin.model }
        if let questions = pin.questions {
            currentQuestions = questions
            isCustom = true
        } else {
            preset = pin.preset
        }
        text = pin.text
        run()
    }

    func unpin(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
    }
```

Replace `run()` and add `show(_:)`:

```swift
    /// Live results (spec §3.2): cancel the request in flight, wait for typing to pause, ask again.
    private func run() {
        task?.cancel()
        let duplicates = Question.duplicateKeys(currentQuestions)
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, duplicates.isEmpty else {
            task = nil
            isUpdating = false
            result = nil
            error = nil
            questionErrors = Dictionary(uniqueKeysWithValues: duplicates.map { ($0, "Another question has the same id.") })
            return
        }
        let text = text, questions = questionsJSON
        isUpdating = true
        task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let response = try await decide(model, text, questions)
                guard !Task.isCancelled else { return }
                result = response
                error = nil
                questionErrors = [:]
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                show(error)
            }
            isUpdating = false
        }
    }

    /// A 422's issues go to the question their `loc` names (spec §5); the rest, or any other error,
    /// is shown above the answers.
    private func show(_ error: Error) {
        let issues = (error as? OllayaError)?.detail ?? []
        var byQuestion: [String: String] = [:]
        for issue in issues {
            guard let id = issue.questionID else { continue }
            byQuestion[id] = byQuestion[id].map { $0 + "\n" + issue.msg } ?? issue.msg
        }
        questionErrors = byQuestion
        let other = issues.filter { $0.questionID == nil }.map(\.msg)
        self.error = issues.isEmpty ? error.localizedDescription : other.isEmpty ? nil : other.joined(separator: "\n")
    }
```

At the end of the file (outside the class) add:

```swift
/// A pinned input and its answers (spec §3.2; in memory only, v1).
struct Pin: Identifiable {
    let id = UUID()
    let text: String
    let model: String            // the model picked, e.g. `laya:latest`
    let setName: String          // "Support ticket", "My questions"
    let preset: Preset
    let questions: [Question]?   // "My questions" at the time; nil for a preset
    let rows: [ResultRow]

    /// The text's first line, for the sidebar.
    var title: String {
        text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`, including the existing
`testSwitchingQuestionSetRerunsWithItsQuestions` (a preset is still sent byte for byte) and
`testRowsFollowTheQuestionSetOrder`.

- [ ] **Step 5: Commit**

```bash
git add Karar/AppModel.swift KararTests/AppModelTests.swift
git commit -m "AppModel: My questions, question errors from 422, request body, pins"
```

---

### Task 5: Token counter, truncation warning, pins in the sidebar (UI)

**Files:**
- Modify: `Karar/Views/MainView.swift`
- Modify: `Karar/KararApp.swift` (DEBUG launch arguments)

**Interfaces:**
- Consumes: `DecideResponse.usage/stateTruncated` (Task 1), `AppModel.pins/pin()/restore(_:)/unpin(_:)`,
  `AppModel.questions` (Task 4), `Question.parse` (Task 3).
- Produces: `MainView.tokenCounter` (used again in Task 6's layout), `MainView.tokenHelp(tokens:questions:)`.

No unit test: view code. The controller runs the UI check.

- [ ] **Step 1: DEBUG launch arguments**

In `Karar/KararApp.swift`, at the end of `AppDelegate.init()` (after `super.init()`), add:

```swift
        #if DEBUG
        // UI checks without typing (no Accessibility): `-KararText "…"`, `-KararQuestions '{…}'`.
        if let text = UserDefaults.standard.string(forKey: "KararText") { app.text = text }
        if let json = UserDefaults.standard.string(forKey: "KararQuestions") { app.questions = Question.parse(Data(json.utf8)) }
        #endif
```

- [ ] **Step 2: Token counter under the editor**

In `MainView.detail`, replace the `VStack(spacing: 0) { editor … results }` block with:

```swift
                VStack(spacing: 0) {
                    editor
                        .padding([.horizontal, .top], 20)
                    // Fixed height: the counter appearing, changing or turning into the warning never moves the layout.
                    tokenCounter
                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .trailing)
                        .padding(.horizontal, 20)
                    Divider()
                    results
                }
```

Add to `MainView`:

```swift
    /// Spec §3.2: the engine's token count for the last answer, never an estimate; the warning in
    /// system orange when the text was cut (§5).
    @ViewBuilder private var tokenCounter: some View {
        if let result = app.result, let tokens = result.usage?.inputTokens {
            Group {
                if result.stateTruncated == true {
                    Label("Text too long for \(result.model): only the first part was read",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(tokens.formatted()) tokens")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .opacity(app.isUpdating ? 0.5 : 1)
            .help(Self.tokenHelp(tokens: tokens, questions: result.answers.count))
        }
    }

    static func tokenHelp(tokens: Int, questions: Int) -> String {
        "\(tokens.formatted()) tokens read: your text plus each question's instructions and options, "
            + "counted once per question (\(questions) \(questions == 1 ? "question" : "questions"))."
    }
```

- [ ] **Step 3: Pin button (⌘↩) and the Pinned section**

In `.toolbar`, after the Question set `ToolbarItem`, add:

```swift
            ToolbarItem {
                Button {
                    app.pin()
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.result == nil || app.isUpdating)
                .help("Pin the text and its answers to the sidebar (⌘↩)")
            }
```

In the sidebar `List`, after `Section("Models") { … }`, add:

```swift
                if !app.pins.isEmpty {
                    Section("Pinned") {
                        ForEach(app.pins) { pin in
                            Button {
                                app.restore(pin)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pin.title)
                                        .lineLimit(1)
                                    Text(verbatim: "\(pin.setName) · \(pin.model)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help(pin.rows.map { "\($0.label): \($0.answer)" }.joined(separator: "\n"))
                            .contextMenu {
                                Button("Remove") { app.unpin(pin) }
                            }
                        }
                    }
                }
```

- [ ] **Step 4: Build and run the tests**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Karar/Views/MainView.swift Karar/KararApp.swift
git commit -m "Token counter and truncation warning under the editor; pin answers with Cmd-Return"
```

- [ ] **Step 6 (controller): UI check**

Light and dark, each with `-KararText` set to the sample ticket (counter) and to the sample ticket
repeated 60 times (`laya` → `laya:en`: orange warning). Check that the counter is right-aligned
with the editor's edge, that the warning fits on one line at the minimum window width (720 pt), and
that nothing jumps when the counter appears. Ask the user to press ⌘↩ and click the pin while
capturing a frame per second.

---

### Task 6: Advanced mode: toggle, "My questions…", cards, inspector (UI)

**Files:**
- Create: `Karar/Views/QuestionCard.swift`
- Create: `Karar/Views/InspectorView.swift`
- Modify: `Karar/Views/MainView.swift`

**Interfaces:**
- Consumes: `Question`, `Question.Kind`, `Question.Option`, `change(to:)`, `Answer.rawText` (Task 3);
  `AppModel.questions/isCustom/useMyQuestions()/addQuestion()/questionErrors/requestBody` (Task 4);
  `DecideResponse.json/routing/evalDuration/usage` (Task 1); `OrderedJSON.pretty` (Task 2);
  `OllayaClient.local.curl(body:)` (Task 1); `MainView.tokenCounter` (Task 5).
- Produces: `QuestionCard(question: Binding<Question>, answer: Answer?, error: String?, remove: () -> Void)`,
  `InspectorView(app: AppModel)`.

No unit test: view code. The controller runs the UI check.

- [ ] **Step 1: The question card**

Create `Karar/Views/QuestionCard.swift`:

```swift
import SwiftUI

/// One question in advanced mode (spec §3.2): id, type, instructions and options, all editable,
/// with the raw answer. A validation error from the engine marks the card in system red (spec §5).
struct QuestionCard: View {
    @Binding var question: Question
    let answer: Answer?
    let error: String?
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("id", text: $question.key)
                    .font(.body.monospaced())
                    .frame(maxWidth: 220)
                Picker("Type", selection: Binding(get: { question.kind }, set: { question.change(to: $0) })) {
                    ForEach(Question.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 12)
                if let answer {
                    Text(answer.rawText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this question")
            }
            TextField("Instructions (when empty, the model reads the id)", text: $question.instructions, axis: .vertical)
                .lineLimit(1...4)
            options
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(error == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(.red), lineWidth: error == nil ? 1 : 2)
        }
    }

    @ViewBuilder private var options: some View {
        switch question.kind {
        case .choice:
            ForEach($question.options) { $option in
                HStack(spacing: 8) {
                    TextField("label", text: $option.label)
                        .font(.body.monospaced())
                        .frame(width: 160)
                    TextField("Description (optional)", text: $option.text)
                    removeButton(option)
                }
            }
            addButton("Add option") { question.options.append(.init(label: "option_\(question.options.count + 1)")) }
        case .score:
            ForEach($question.options) { $level in
                let index = question.options.firstIndex { $0.id == level.id } ?? 0
                HStack(spacing: 8) {
                    Text(verbatim: "\(index)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    TextField("Level \(index)", text: $level.text)
                    removeButton(level)
                }
            }
            addButton("Add level") { question.options.append(.init()) }
        case .noul:
            ForEach($question.options) { $option in
                HStack(spacing: 8) {
                    Text(option.label == "true" ? "True" : "False")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    TextField(option.label == "true" ? "When the statement holds (optional)" : "When it does not (optional)",
                              text: $option.text)
                }
            }
        }
    }

    private func removeButton(_ option: Question.Option) -> some View {
        Button {
            question.options.removeAll { $0.id == option.id }
        } label: {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove")
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
```

(Removing options below the engine's minimum is allowed on purpose: the engine's `422` then marks
the card, which is the path the acceptance criterion checks.)

- [ ] **Step 2: The inspector**

Create `Karar/Views/InspectorView.swift`:

```swift
import SwiftUI

/// Advanced mode's inspector (spec §3.2): which model answered and by which route, how long it
/// took, how many tokens it read, and the response itself.
struct InspectorView: View {
    let app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result = app.result {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        row("Model", result.model)
                        if let routing = result.routing {
                            GridRow {
                                label("Route")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routing.route)
                                    Text(routing.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        row("Total", Self.milliseconds(result.totalDuration))
                        if let eval = result.evalDuration { row("Eval", Self.milliseconds(eval)) }
                        if let tokens = result.usage?.inputTokens { row("Input tokens", tokens.formatted()) }
                    }
                } else {
                    Text("No response yet.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Copy JSON") {
                        if let result = app.result { Self.copy(OrderedJSON.pretty(result.json)) }
                    }
                    .disabled(app.result == nil)
                    Button("Copy as curl") {
                        if let body = app.requestBody { Self.copy(OllayaClient.local.curl(body: body)) }
                    }
                    .disabled(app.requestBody == nil)
                }
                if let result = app.result {
                    Text(OrderedJSON.pretty(result.json))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quinary, in: .rect(cornerRadius: 6))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            label(name)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    static func milliseconds(_ nanoseconds: Int64) -> String {
        String(format: "%.1f ms", Double(nanoseconds) / 1_000_000)
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
```

- [ ] **Step 3: `MainView`: toggle, "My questions…", cards, inspector**

Add to `MainView`'s properties:

```swift
    @AppStorage("advanced") private var advanced = false
```

Replace the Question set `ToolbarItem` with:

```swift
            ToolbarItem {
                Menu {
                    Picker("Question set", selection: Binding<Preset?>(
                        get: { app.isCustom ? nil : app.preset },
                        set: { choice in
                            if let choice {
                                app.preset = choice
                            } else {
                                app.useMyQuestions()
                                advanced = true
                            }
                        }
                    )) {
                        ForEach(Preset.all) { Text($0.name).tag(Optional($0)) }
                        Divider()
                        Text("My questions…").tag(Preset?.none)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(app.isCustom ? "My questions" : app.preset.name, systemImage: "list.bullet.rectangle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Question set")
            }
```

After the Pin `ToolbarItem` (Task 5), add:

```swift
            ToolbarItem {
                Toggle(isOn: $advanced) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .help("Edit the questions and inspect the response")
            }
```

In `detail`, change the `VStack` from Task 5 so its last line is `if advanced { cards } else { results }`
instead of `results`, and attach the inspector to that `VStack`:

```swift
                .inspector(isPresented: $advanced) {
                    InspectorView(app: app)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
                }
```

Replace `results` with the version below (the header moves into `answersHeader`, shared with the
cards), and add `cards` and `answersHeader`:

```swift
    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Answers appear here as you type.")
                        .foregroundStyle(.secondary)
                } else {
                    answersHeader
                    if let error = app.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    if !app.questionErrors.isEmpty {
                        Label("Some questions are not valid. Turn on Advanced to see which.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        ForEach(app.rows) { row in
                            GridRow {
                                Text(row.label).foregroundStyle(.secondary)
                                Text(row.answer).bold()
                                ProgressView(value: row.sureness)
                                    .frame(minWidth: 120, maxWidth: .infinity)
                                Text("\(Int((row.sureness * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                    .opacity(app.isUpdating ? 0.5 : 1)
                    .animation(.default, value: app.rows)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Advanced mode (spec §3.2): each question is an editable card with its raw answer.
    private var cards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                answersHeader
                if let error = app.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                ForEach($app.questions) { $question in
                    QuestionCard(question: $question,
                                 answer: app.result?.answers[question.key],
                                 error: app.questionErrors[question.key]) {
                        app.questions.removeAll { $0.id == question.id }
                    }
                }
                .opacity(app.isUpdating ? 0.85 : 1)
                Button {
                    app.addQuestion()
                } label: {
                    Label("Add question", systemImage: "plus")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var answersHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(advanced ? "Questions" : "Answers").font(.headline)
            Spacer()
            if app.isUpdating {
                ProgressView().controlSize(.small)
            } else if let result = app.result {
                Text(verbatim: "\(result.model) · \(result.totalDuration / 1_000_000) ms")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
```

- [ ] **Step 4: Build and run the tests**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Karar/Views
git commit -m "Advanced mode: question cards, My questions, inspector with Copy JSON and Copy as curl"
```

- [ ] **Step 6 (controller): UI check**

Light and dark, `-advanced YES`, with `-KararText` (sample ticket): cards for the triage preset and
the inspector. Then `-KararQuestions '{"urgency": {"type": "score", "instructions": "How urgent?", "criteria": ["Can wait"]}, "refund": {"type": "noul"}}'`:
the `urgency` card is red with the engine's message, `refund` is fine. Check the card layout at the
minimum window width with the inspector open (widen `minWidth` if the cards get cramped), option
rows aligned, no jumps while answers update.

---

### Task 7: Acceptance, docs, roadmap (controller, with the user)

**Files:**
- Modify: `docs/superpowers/plans/2026-09-24-karar-roadmap.md`

- [ ] **Step 1: Tests and a Release build**

Run the test command, then
`xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error:|\*\* '`.
Expected: both succeed.

- [ ] **Step 2: A custom question set built only in the UI returns answers**

Launch Karar (scratch store, no launch arguments). Ask the user to type a text, choose "My
questions…", remove the preset's cards, add two questions and edit their id, type, instructions
and options. Capture a frame per second while they work; check the answers arrive on the cards.

- [ ] **Step 3: An invalid set shows the error on the right card**

Ask the user to remove a score card's levels down to one. Expected: that card turns red with
"List should have at least 2 items after validation, not 1"; the others keep their answers.

- [ ] **Step 4: Copied curl works in Terminal**

Ask the user to click "Copy as curl" and paste it into Terminal (or run `pbpaste | zsh` from the
controller). Expected: a JSON response with the same answers as the inspector.

- [ ] **Step 5: Pins, counter, truncation**

Ask the user to press ⌘↩, then click the pin after changing the text. Launch once with the long
text (`-KararText`) to see the orange warning. Light and dark captures of every screen touched.

- [ ] **Step 6: Tick the roadmap and add notes**

In the roadmap, tick Phase 4 (`- [x]`) and add one-line notes under "Notes for later phases" for anything surprising.

- [ ] **Step 7: Commit**

```bash
git add docs
git commit -m "Phase 4 done: tick roadmap, add notes"
```
