# Phase 9 — Bump the bundled Ollaya to v0.7.1 (Apple GPU) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Karar v0.2.0 bundles Ollaya v0.7.1 with MLX's Metal kernels, so `laya` and
`nli:modernbert-large` answer on the Apple GPU (~7× faster). Existing installs move to the GPU on
their own, and the catalog gains `von`, `kev` and `decision`.

**Spec:** [`../specs/2026-09-26-ollaya-v0.7.1-design.md`](../specs/2026-09-26-ollaya-v0.7.1-design.md)
(section numbers below are that spec's unless they say "main spec").

**Architecture:**
- `scripts/fetch-ollaya.sh` fetches two archives. The "Embed Ollaya" build phase copies `ollaya`
  (as now) and `mlx.metallib` → `Contents/Resources/mlx_metal/`, where Ollaya's runner looks in an
  app bundle.
- `AppModel.connect()` starts a one-time background re-pull of installed GPU-capable models. The
  one-time flag is kept in `UserDefaults` per model store.
- No new HTTP client code: the API contract is unchanged except for cosmetics.

**Tech Stack:** SwiftUI + Foundation, XCTest, XcodeGen, POSIX sh, `jq`, `curl`.

## Global Constraints

- `project.yml` is the source of truth. Never hand-edit `Karar.xcodeproj/project.pbxproj`: edit
  `project.yml`, run `xcodegen generate`, commit both.
- No third-party Swift dependencies. System semantic colours only. UI is English only.
- `vendor/` is never committed.
- Bundle ID `io.github.omerhakanbilici.karar` never changes. Hardened Runtime stays on. **No new
  entitlements** on the app or on the nested `ollaya` (spec §3.2).
- llama.cpp (`lib/ollaya/llama/`) is **not** embedded (spec §3.3).
- Never touch `~/.ollaya`. Real-engine checks use a scratch model store (`OLLAYA_MODELS=<dir>`)
  and port 11436 (`OLLAYA_HOST=127.0.0.1:11436`), or Karar's own engine on 11435 with
  `OLLAYA_MODELS` in Karar's environment.
- Before launching Karar for checks, quit every running Karar, including `/Applications/Karar.app`.
  It holds 11435. Quit with
  `osascript -e 'tell application id "io.github.omerhakanbilici.karar" to quit'`, never `pkill`:
  SIGTERM orphans its `ollaya`.
- Commits:
  - author email `906295+omerhakanbilici@users.noreply.github.com`; check with
    `git log --format='%ae %ce' -1`;
  - end every message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Pushing, tagging and releasing need the user's explicit OK in this session (Task 6).
- UI checks capture only Karar's window (window id from `CGWindowListCopyWindowInfo`, owner
  "Karar", layer 0; `screencapture -x -o -l <id>`), light and dark.
- Pins:
  - Ollaya v0.7.1;
  - `ollaya-darwin-arm64.tgz` sha256 `e0b281036611f8a074e07ce553a57916bf49c48b609601adec03531ad821942c`;
  - `ollaya-darwin-arm64-mlx.tgz` sha256 `5a85d974ade710b9c3c201c73a96eb0bfdbf782d9bf0b0c970cd187f5e619e4f`.
- Karar version: `MARKETING_VERSION` 0.2.0, `CURRENT_PROJECT_VERSION` 5.

### Shared recipe: a scratch store that looks like an old install

Several tasks need a model store whose `laya` models were pulled before v0.7.1 (no `arch` layer).
Build it once per session (the pull downloads ~1.5 GB):

```sh
STORE=<scratchpad>/old-store        # any scratch dir; never ~/.ollaya
mkdir -p "$STORE"
OLLAYA_HOST=127.0.0.1:11436 OLLAYA_MODELS="$STORE" vendor/ollaya/bin/ollaya serve >/dev/null 2>&1 & pid=$!
until curl -fs -m 1 http://127.0.0.1:11436/ >/dev/null; do sleep 0.2; done
curl -fsN http://127.0.0.1:11436/api/pull -d '{"model":"laya"}' | tail -n 1     # {"status":"success"}
kill $pid; wait $pid
# Make it old: drop the arch layer from both targets' manifests (tested: the engine then runs them on the CPU).
for t in en multilingual; do
  m="$STORE/manifests/ollaya.dev/library/laya/$t"
  jq -c '.layers |= map(select(.mediaType != "application/vnd.ollaya.arch"))' "$m" > "$m.tmp" && mv "$m.tmp" "$m"
done
```

To reset it to "old" after a test re-pulled it, run the `for` loop again.

---

## Files

| File | Change | Task |
|---|---|---|
| `scripts/fetch-ollaya.sh` | v0.7.1, two archives | 1 |
| `project.yml`, `Karar.xcodeproj/project.pbxproj` | Embed script: metallib, notices; later version 0.2.0 | 1, 5 |
| `KararTests/AboutTests.swift` | metallib and MLX notices ship in the app | 1 |
| `scripts/smoke.sh` | `laya:en` must run on `metal` | 1 |
| `Karar/Views/AboutView.swift` | "MLX notices" row | 2 |
| `NOTICE`, `THIRD_PARTY.md`, `CLAUDE.md`, `Karar/Daemon.swift`, main spec | v0.7.1 pins, MLX, GGUF note | 2 |
| `Karar/AppModel.swift`, `KararTests/AppModelTests.swift` | GPU refresh | 3 |
| `Karar/Catalog.json`, `KararTests/CatalogTests.swift`, `THIRD_PARTY.md` | sizes, `von`, `kev`, `decision` | 4 |
| `README.md`, `site/index.html` | one sentence on GPU speed | 5 |
| `docs/screenshots/{main,advanced}-{light,dark}.png` | retaken, ms timings | 6 |
| `docs/superpowers/plans/2026-09-24-karar-roadmap.md` | Phase 9 tick and notes | 6 |

---

### Task 1: Engine v0.7.1 with MLX's kernels in the bundle

**Files:**
- Modify: `scripts/fetch-ollaya.sh` (whole file)
- Modify: `project.yml` (the `Embed Ollaya` `postCompileScripts` script), then regenerate `Karar.xcodeproj`
- Modify: `KararTests/AboutTests.swift` (`testTheLicenceTextsShipInTheApp`)
- Modify: `scripts/smoke.sh`

**Interfaces:**
- Produces: `Contents/Resources/mlx_metal/mlx.metallib` and
  `Contents/Resources/Ollaya/mlx-THIRD_PARTY_NOTICES` in `Karar.app`. Task 2's About row reads the
  second one.

- [ ] **Step 1: Write the failing test**

Replace `testTheLicenceTextsShipInTheApp` in `KararTests/AboutTests.swift` with:

```swift
    func testTheLicenceTextsShipInTheApp() {
        for (name, dir) in [("LICENSE", nil), ("NOTICE", nil), ("LICENSE", "Ollaya"),
                            ("THIRD_PARTY_NOTICES", "Ollaya"), ("onnxruntime-ThirdPartyNotices.txt", "Ollaya"),
                            ("mlx-THIRD_PARTY_NOTICES", "Ollaya")] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil, subdirectory: dir), "\(dir ?? "")/\(name)")
        }
    }

    /// The runner looks for MLX's kernels at <exe dir>/../Resources/mlx_metal/ in an app bundle;
    /// without them laya runs on the CPU (spec 2026-09-26 §3.2).
    func testMLXKernelsShipWhereTheRunnerLooks() {
        XCTAssertNotNil(Bundle.main.url(forResource: "mlx", withExtension: "metallib", subdirectory: "mlx_metal"))
    }
```

- [ ] **Step 2: Run it and see it fail**

Run: `xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test -only-testing:KararTests/AboutTests 2>&1 | tail -20`
Expected: FAIL. `Ollaya/mlx-THIRD_PARTY_NOTICES` and `testMLXKernelsShipWhereTheRunnerLooks` fail.

- [ ] **Step 3: Update `scripts/fetch-ollaya.sh`**

Replace the whole file with:

```sh
#!/bin/sh
# Downloads the pinned Ollaya release into vendor/ollaya and verifies its checksums: the engine,
# and MLX's Metal kernels, which let laya and nli:modernbert-large run on the Apple GPU.
set -eu
OLLAYA_VERSION=v0.7.1
OLLAYA_SHA256=e0b281036611f8a074e07ce553a57916bf49c48b609601adec03531ad821942c      # ollaya-darwin-arm64.tgz
OLLAYA_MLX_SHA256=5a85d974ade710b9c3c201c73a96eb0bfdbf782d9bf0b0c970cd187f5e619e4f  # ollaya-darwin-arm64-mlx.tgz

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/vendor/ollaya"
if [ -f "$dest/VERSION" ] && [ "$(cat "$dest/VERSION")" = "$OLLAYA_VERSION" ]; then
  echo "Ollaya $OLLAYA_VERSION already in vendor/ollaya"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/ollaya-dev/ollaya/releases/download/$OLLAYA_VERSION"
curl -fsSL -o "$tmp/ollaya.tgz" "$base/ollaya-darwin-arm64.tgz"
curl -fsSL -o "$tmp/mlx.tgz" "$base/ollaya-darwin-arm64-mlx.tgz"
printf '%s  %s\n%s  %s\n' "$OLLAYA_SHA256" "$tmp/ollaya.tgz" "$OLLAYA_MLX_SHA256" "$tmp/mlx.tgz" | shasum -a 256 -c -
rm -rf "$dest"
mkdir -p "$dest"
# Both archives share the prefix layout (bin/, lib/ollaya/, share/).
tar -xzf "$tmp/ollaya.tgz" -C "$dest"
tar -xzf "$tmp/mlx.tgz" -C "$dest"
echo "$OLLAYA_VERSION" > "$dest/VERSION"
echo "Ollaya $OLLAYA_VERSION ready in vendor/ollaya"
```

- [ ] **Step 4: Fetch and inspect**

Run: `scripts/fetch-ollaya.sh && vendor/ollaya/bin/ollaya --version; vtool -show-build vendor/ollaya/bin/ollaya | grep minos; ls vendor/ollaya/lib/ollaya/mlx_metal vendor/ollaya/share/doc/ollaya`

Expected:
- two `OK` lines from `shasum`;
- `client version is 0.7.1`;
- `minos 14.0`;
- `mlx_metal/` holds `FILES.sha256` and `mlx.metallib`;
- `share/doc/ollaya/` holds `LICENSE`, `THIRD_PARTY_NOTICES`, `llama.cpp-THIRD_PARTY_NOTICES`,
  `onnxruntime-ThirdPartyNotices.txt` and the `mlx_metal/` directory.

- [ ] **Step 5: Update the embed script in `project.yml`**

Replace the `script: |` body of the `Embed Ollaya` entry with:

```yaml
        script: |
          set -euo pipefail
          src="$SRCROOT/vendor/ollaya"
          [ -x "$src/bin/ollaya" ] && [ -f "$src/lib/ollaya/mlx_metal/mlx.metallib" ] \
            || { echo "error: run scripts/fetch-ollaya.sh first"; exit 1; }
          install -m 755 "$src/bin/ollaya" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/ollaya"
          codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime --identifier io.github.omerhakanbilici.karar.ollaya "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/ollaya"
          res="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
          # MLX's Metal kernels (the Apple GPU): the runner looks in <exe dir>/../Resources/mlx_metal/.
          mkdir -p "$res/mlx_metal" "$res/Ollaya"
          cp "$src/lib/ollaya/mlx_metal/mlx.metallib" "$res/mlx_metal/"
          # Named files, not a glob: share/doc/ollaya/ also holds directories, and llama.cpp's
          # notices stay out with llama.cpp itself (not embedded).
          for f in LICENSE THIRD_PARTY_NOTICES onnxruntime-ThirdPartyNotices.txt; do
            cp "$src/share/doc/ollaya/$f" "$res/Ollaya/"
          done
          cp "$src/share/doc/ollaya/mlx_metal/THIRD_PARTY_NOTICES" "$res/Ollaya/mlx-THIRD_PARTY_NOTICES"
          cp "$src/VERSION" "$res/Ollaya/VERSION"
          cp "$SRCROOT/LICENSE" "$SRCROOT/NOTICE" "$res/"
```

Keep `name: Embed Ollaya` and `basedOnDependencyAnalysis: false` as they are.

Then run: `xcodegen generate`.

- [ ] **Step 6: Run the tests and see them pass**

Run: `xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`, every test passing.

- [ ] **Step 7: Check the built bundle**

Run:

```sh
app=build/Build/Products/Debug/Karar.app
ls -la "$app/Contents/Resources/mlx_metal" "$app/Contents/Resources/Ollaya"
codesign -dv "$app/Contents/MacOS/ollaya" 2>&1 | grep flags
codesign -d --entitlements - "$app/Contents/MacOS/ollaya" 2>&1 | tail -3
codesign --verify --deep --strict "$app" && echo sealed
```

Expected:
- `mlx.metallib` is 135865440 bytes;
- `Ollaya/` holds `LICENSE`, `THIRD_PARTY_NOTICES`, `onnxruntime-ThirdPartyNotices.txt`,
  `mlx-THIRD_PARTY_NOTICES` and `VERSION` (`v0.7.1`);
- `flags=0x10002(adhoc,runtime)`;
- no entitlements on `ollaya`;
- the last line prints `sealed`.

- [ ] **Step 8: Add the GPU check to `scripts/smoke.sh`**

Change the header's first comment line from `… runs one decide with the triage question set, and
checks the answer's shape.` to:

```sh
# Real-engine smoke test (spec §6), local only: starts the ollaya inside a built Karar.app on
# 127.0.0.1:11436 with a scratch model store, pulls laya:en, runs one decide with the triage
# question set, and checks the answer's shape and that laya:en ran on the Apple GPU (metal).
```

Replace the last line (`echo "smoke test passed: …"`) with:

```sh
# The Apple GPU (spec 2026-09-26 §7): laya:en's manifest carries an arch layer, so it loads on
# MLX when the bundle holds Resources/mlx_metal/mlx.metallib. Guards the metallib's place.
device=$(curl -fs "http://$host/api/ps" | jq -r '.models[] | select(.name == "laya:en") | .device')
[ "$device" = metal ] || { echo "error: laya:en ran on '$device', not the Apple GPU (metal)" >&2; exit 1; }
echo "smoke test passed: $(jq -c '{model, intent: .answers.intent.choice, ms: (.total_duration / 1000000 | floor)}' "$tmp/decide.json") on $device"
```

- [ ] **Step 9: Run the smoke test on the Debug build, including the upgrade path**

Use the old-install store from the shared recipe. The smoke test's pull of `laya:en` is then the
re-pull that adds the `arch` layer.

Run: `KARAR_SMOKE_MODELS="$STORE" scripts/smoke.sh build/Build/Products/Debug/Karar.app`

Expected:
- `engine: {"version":"0.7.1"}`;
- `smoke test passed: {"model":"laya:en","intent":"refund","ms":…} on metal`;
- `ms` is the cold first request (roughly 1–2 s: load plus answer).

Then run the loop from the recipe again to make the store old.

- [ ] **Step 10: Record how Karar's engine treats a GGUF model (spec §3.3)**

Run:

```sh
OLLAYA_HOST=127.0.0.1:11436 OLLAYA_MODELS="$STORE" build/Build/Products/Debug/Karar.app/Contents/MacOS/ollaya serve >/dev/null 2>&1 & pid=$!
until curl -fs -m 1 http://127.0.0.1:11436/ >/dev/null; do sleep 0.2; done
curl -sN http://127.0.0.1:11436/api/pull -d '{"model":"winnow:e4b"}'; echo
kill $pid; wait $pid
du -sh "$STORE"
```

Expected (from upstream `scheduler.rs` `run_check`):
- an error before any download, saying
  `winnow:e4b runs on llama.cpp, and this installation of ollaya has no llama.cpp libraries (lib/ollaya/llama); nothing was downloaded`;
- `du` unchanged.

Copy the exact response into the Task 2 commit (main spec §1). If it downloads anything instead,
stop and tell the user.

- [ ] **Step 11: Commit**

```bash
git add scripts/fetch-ollaya.sh project.yml Karar.xcodeproj KararTests/AboutTests.swift scripts/smoke.sh
git commit -m "Bundle Ollaya v0.7.1 with MLX's Metal kernels (Apple GPU)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Licences, pins and the GGUF note

**Files:**
- Modify: `Karar/Views/AboutView.swift` (the Ollaya `licences(…)` list, around line 70)
- Modify: `NOTICE`, `THIRD_PARTY.md` (Ollaya and Question sets sections), `CLAUDE.md`
- Modify: `Karar/Daemon.swift` (doc comment of `bundledVersion`)
- Modify: `docs/superpowers/specs/2026-09-24-karar-design.md` (§1, §4, §9)

**Interfaces:**
- Consumes: `Ollaya/mlx-THIRD_PARTY_NOTICES` in the bundle (Task 1); the GGUF error text (Task 1, Step 10).

- [ ] **Step 1: About row**

In `AboutView.swift`, add the MLX row after the ONNX Runtime row:

```swift
                        Licence(owner: "Ollaya", title: "ONNX Runtime notices", name: "onnxruntime-ThirdPartyNotices.txt", subdirectory: "Ollaya"),
                        Licence(owner: "Ollaya", title: "MLX notices", name: "mlx-THIRD_PARTY_NOTICES", subdirectory: "Ollaya"),
```

- [ ] **Step 2: `NOTICE`**

Replace the Ollaya paragraph and the question-set paragraph with:

```
This product bundles Ollaya (https://github.com/ollaya-dev/ollaya) v0.7.1,
licensed under the Apache License, Version 2.0, including MLX (MIT). Ollaya's
own licence and third-party notices, and MLX's notices, ship inside the app at
Contents/Resources/Ollaya/.

The question sets in Karar/Presets/ are copied from Ollaya v0.7.1
(crates/ollaya-api/src/presets/), licensed under the Apache License, Version 2.0.
```

- [ ] **Step 3: `THIRD_PARTY.md`, the Ollaya and Question sets sections**

Replace the section from `## Ollaya` down to `## Models` (exclusive) with:

```markdown
## Ollaya

Karar.app contains the `ollaya` binary of [Ollaya](https://github.com/ollaya-dev/ollaya) v0.7.1
and MLX's Metal kernels from the same release (`ollaya-darwin-arm64.tgz` and
`ollaya-darwin-arm64-mlx.tgz` from the project's GitHub release, pinned by version and SHA-256 in
[`scripts/fetch-ollaya.sh`](scripts/fetch-ollaya.sh)). Karar only re-signs `ollaya` for the
Hardened Runtime. It does not include the llama.cpp libraries that the release also carries.
Ollaya is licensed under the Apache License 2.0, the same text as Karar's [LICENSE](LICENSE).

`ollaya` links ONNX Runtime 1.28.0 (MIT) and the components ONNX Runtime bundles. It also links
MLX 0.32.2 and mlx-c (MIT); MLX's build compiles in {fmt} and nlohmann/json (MIT) and includes
PocketFFT (BSD-3-Clause) and metal-cpp (Apache-2.0). MLX's kernels ship as
`Karar.app/Contents/Resources/mlx_metal/mlx.metallib`. The notices ship inside the app next to
Ollaya's licence, and Karar ▸ About Karar opens each of them:

- `Karar.app/Contents/Resources/Ollaya/LICENSE`
- `Karar.app/Contents/Resources/Ollaya/THIRD_PARTY_NOTICES`
- `Karar.app/Contents/Resources/Ollaya/onnxruntime-ThirdPartyNotices.txt`
- `Karar.app/Contents/Resources/Ollaya/mlx-THIRD_PARTY_NOTICES`

## Question sets

The five built-in question sets in [`Karar/Presets/`](Karar/Presets) (`triage`, `email`, `guard`,
`moderation`, `router`) are copied unchanged from Ollaya v0.7.1
(`crates/ollaya-api/src/presets/`), licensed under the Apache License 2.0.

```

- [ ] **Step 4: `CLAUDE.md` and `Daemon.swift`**

- `CLAUDE.md`: change
  `https://github.com/ollaya-dev/ollaya/blob/v0.5.0/docs/api.md` to
  `https://github.com/ollaya-dev/ollaya/blob/v0.7.1/docs/api.md`.
- `Karar/Daemon.swift`: change the doc comment
  `/// The pinned Ollaya version inside the app ("v0.5.0"), copied from vendor/ollaya/VERSION.` to
  `/// The pinned Ollaya version inside the app ("v0.7.1"), copied from vendor/ollaya/VERSION.`

- [ ] **Step 5: Main spec (`docs/superpowers/specs/2026-09-24-karar-design.md`)**

- §1: after the presets bullet (`- Built-in presets (question sets): …`), add:

  ```markdown
  - Ollaya v0.6.0 added a sixth preset, `agent`, whose state is JSON (`request`, `command`); Karar
    sends text and does not bundle it.
  - GGUF models (`winnow`) run on llama.cpp, which Karar does not bundle (ad-hoc signing plus
    library validation would need `disable-library-validation`). Karar's own engine refuses to pull
    them: "<exact text from Task 1, Step 10>". An adopted CLI or Ollaya.app engine runs them.
  ```

- §4 "Bundling Ollaya": replace the bullet with:

  ```markdown
  - **Bundling Ollaya:** `scripts/fetch-ollaya.sh` downloads the pinned release
    (`OLLAYA_VERSION`, `v0.3.2` at first, `v0.5.0` since Phase 6, `v0.7.1` since v0.2.0):
    `ollaya-darwin-arm64.tgz` and `ollaya-darwin-arm64-mlx.tgz`, each checked against its
    SHA-256. An Xcode build phase copies `ollaya` into `Contents/MacOS/` and MLX's `mlx.metallib`
    into `Contents/Resources/mlx_metal/`, where Ollaya's runner looks for it in an app bundle; with
    it, `laya` and `nli:modernbert-large` run on the Apple GPU. Neither file is committed.
  ```

- §9: risk 1 add `Resolved: v0.7.1 targets macOS 14.0, the same as Karar.`; risk 3 add
  `Measured with v0.7.1 on the Apple GPU (M1 Pro, warm, 5 questions): laya:en 166 ms,
  laya:multilingual 61 ms; a cold load adds ~1.0–1.3 s.`

- [ ] **Step 6: Build, test, look at About**

Run the full test command (as in Task 1, Step 6). Expected: `** TEST SUCCEEDED **`.

Then check the About window by hand:
- open `build/Build/Products/Debug/Karar.app` with `OLLAYA_MODELS="$STORE"` in its environment
  (`open -n --env OLLAYA_MODELS="$STORE" build/Build/Products/Debug/Karar.app`);
- open Karar ▸ About Karar and capture only its window, light and dark
  (`-KararAppearance dark|light`);
- confirm the Ollaya row reads `Ollaya v0.7.1, built in` and lists "MLX notices";
- clicking "MLX notices" opens the MLX text (ask the user to click if Accessibility is missing);
- quit with `osascript`.

- [ ] **Step 7: Commit**

```bash
git add Karar/Views/AboutView.swift NOTICE THIRD_PARTY.md CLAUDE.md Karar/Daemon.swift docs/superpowers/specs/2026-09-24-karar-design.md
git commit -m "Ollaya v0.7.1: MLX notices in About, pins, GGUF note

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Existing installs move to the GPU on their own

**Files:**
- Modify: `Karar/AppModel.swift` (stored properties, `init`, `connect()`, a new `refreshForGPU()`)
- Modify: `KararTests/AppModelTests.swift` (`makeApp`, new helper, six new tests)
- Modify: `docs/superpowers/specs/2026-09-26-ollaya-v0.7.1-design.md` §4 (the flag is per model store)

**Interfaces:**
- Produces:
  - `AppModel.init(…, load:, defaults: UserDefaults = .standard, gpuRefreshKey: String = AppModel.gpuRefreshKey(for: ProcessInfo.processInfo.environment), debounce:)`;
  - `let gpuRefreshKey: String`;
  - `static let gpuModels: Set<String>`;
  - `nonisolated static func gpuRefreshKey(for environment: [String: String]) -> String`;
  - `func refreshForGPU() async`.
  - `AppDelegate` needs no change: it uses the defaults.
- Why per store: every Karar build shares one defaults domain (dev builds, UI test runs,
  `/Applications/Karar.app`). A flag set by a test run on a scratch store must not stop the real
  app from refreshing `~/.ollaya`. Karar's own engine inherits Karar's `OLLAYA_MODELS`, so the key
  names the store it actually uses.

- [ ] **Step 1: Isolate `UserDefaults` in the tests**

In `AppModelTests`, replace `makeApp` and add a helper:

```swift
    /// A throwaway defaults domain: Karar's real domain is shared by every build on this Mac.
    private func scratchDefaults() -> UserDefaults {
        let name = "KararTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func makeApp(_ fake: FakeOllaya, defaults: UserDefaults? = nil) -> AppModel {
        let daemon = Daemon(probe: { .none }, launch: { _ in {} })
        let app = AppModel(daemon: daemon, decide: fake.decide, tags: fake.tags, version: fake.version,
                           pull: fake.pull, delete: fake.delete, load: fake.load,
                           defaults: defaults ?? scratchDefaults(), gpuRefreshKey: "gpuRefresh:test",
                           debounce: .milliseconds(50))
        app.model = "laya:en"
        return app
    }
```

- [ ] **Step 2: Write the failing tests**

Add to `AppModelTests`:

```swift
    func testConnectRePullsTheInstalledGPUModelsOneByOneThenPreloads() async {
        let fake = FakeOllaya()
        fake.installed = ["laya:latest", "laya:en", "gliclass:latest", "laya:multilingual"]
        let defaults = scratchDefaults()
        let app = makeApp(fake, defaults: defaults)
        await app.connect()
        await waitUntil { fake.pulls["laya:en"] != nil }
        XCTAssertEqual(Set(fake.pulls.keys), ["laya:en"], "one at a time, GPU models only")
        fake.pulls["laya:en"]?.finish()
        await waitUntil { fake.pulls["laya:multilingual"] != nil }
        XCTAssertFalse(defaults.bool(forKey: app.gpuRefreshKey), "not before every pull succeeded")
        fake.pulls["laya:multilingual"]?.finish()
        await waitUntil { defaults.bool(forKey: app.gpuRefreshKey) }
        XCTAssertEqual(Set(fake.pulls.keys), ["laya:en", "laya:multilingual"])
        // Picking laya:en in makeApp, connect(), then the refresh: the engine loads it again from
        // the new manifest, on the GPU.
        await waitUntil { fake.loads == ["laya:en", "laya:en", "laya:en"] }
    }

    func testTheGPURefreshRunsOncePerStore() async {
        let fake = FakeOllaya()
        let defaults = scratchDefaults()
        let app = makeApp(fake, defaults: defaults)
        defaults.set(true, forKey: app.gpuRefreshKey)
        await app.connect()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(fake.pulls.isEmpty)
    }

    func testAFailedGPURefreshIsRetriedAtTheNextConnect() async {
        let fake = FakeOllaya()                                // laya:en, laya:multilingual
        let defaults = scratchDefaults()
        let app = makeApp(fake, defaults: defaults)
        await app.connect()
        await waitUntil { fake.pulls["laya:en"] != nil }
        fake.pulls["laya:en"]?.finish(throwing: URLError(.notConnectedToInternet))
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(fake.pulls["laya:multilingual"], "stops at the first failure")
        XCTAssertFalse(defaults.bool(forKey: app.gpuRefreshKey))
        fake.pulls = [:]
        await app.connect()                                    // e.g. the engine restarted
        await waitUntil { fake.pulls["laya:en"] != nil }
    }

    func testNothingToRefreshStillSetsTheFlag() async {
        let fake = FakeOllaya()
        fake.installed = ["gliclass:latest"]
        let defaults = scratchDefaults()
        let app = makeApp(fake, defaults: defaults)
        await app.connect()
        await waitUntil { defaults.bool(forKey: app.gpuRefreshKey) }
        XCTAssertTrue(fake.pulls.isEmpty)
    }

    func testAFailedModelListLeavesTheGPURefreshForLater() async {
        let fake = FakeOllaya()
        fake.tagsFailure = URLError(.cannotConnectToHost)
        let defaults = scratchDefaults()
        let app = makeApp(fake, defaults: defaults)
        await app.connect()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(fake.pulls.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: app.gpuRefreshKey))
    }

    func testTheGPURefreshKeyNamesTheModelStore() {
        XCTAssertEqual(AppModel.gpuRefreshKey(for: [:]), "gpuRefresh:default")
        XCTAssertEqual(AppModel.gpuRefreshKey(for: ["OLLAYA_MODELS": "/tmp/m"]), "gpuRefresh:/tmp/m")
    }
```

- [ ] **Step 3: Run them and see them fail**

Run: `xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test -only-testing:KararTests/AppModelTests 2>&1 | tail -20`
Expected: build FAILS: `extra arguments 'defaults', 'gpuRefreshKey'` / `type 'AppModel' has no member 'gpuRefreshKey'`.

- [ ] **Step 4: Implement in `Karar/AppModel.swift`**

Stored properties: after `private var pullTasks: [String: Task<Void, Never>] = [:]` add:

```swift
    private let defaults: UserDefaults
    /// Where `refreshForGPU()` records that it is done, per model store.
    let gpuRefreshKey: String
    private var refreshingForGPU = false
```

`init`: add the two parameters before `debounce` and store them:

```swift
    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, version: @escaping Version,
         pull: @escaping Pull, delete: @escaping Delete, load: @escaping Load = { _ in },
         defaults: UserDefaults = .standard,
         gpuRefreshKey: String = AppModel.gpuRefreshKey(for: ProcessInfo.processInfo.environment),
         debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.version = version
        self.pull = pull
        self.deleteModel = delete
        self.load = load
        self.defaults = defaults
        self.gpuRefreshKey = gpuRefreshKey
        self.debounce = debounce
    }
```

`connect()`: add one line at the end:

```swift
    func connect() async {
        let before = model
        await refreshModels()
        engineVersion = (try? await version()) ?? ""
        if model == before {
            preload()
            run()
        }
        Task { await refreshForGPU() }
    }
```

New code, right after `connect()`:

```swift
    /// Models whose registry manifests gained an `arch` layer with Ollaya v0.7.1, which lets them
    /// run on the Apple GPU (MLX). Installs pulled before that lack the layer and stay on the CPU.
    static let gpuModels: Set<String> = ["laya:en", "laya:multilingual", "nli:modernbert-large"]

    /// One flag per model store: every Karar build on this Mac shares one defaults domain, and
    /// Karar's own engine uses Karar's `OLLAYA_MODELS`.
    nonisolated static func gpuRefreshKey(for environment: [String: String]) -> String {
        "gpuRefresh:" + (environment["OLLAYA_MODELS"] ?? "default")
    }

    /// Re-pulls the installed `gpuModels` once per model store (spec 2026-09-26 §4): the engine
    /// fetches only the missing layer, then loads the model on the GPU next time. Silent, with no
    /// download UI; a failure is retried at the next `connect()`.
    // ponytail: a model loaded on the CPU before this stays loaded until its keep_alive ends
    // (≤ 30 min, once per install); the engine can't unload the old runner by name.
    func refreshForGPU() async {
        guard !refreshingForGPU, modelsLoaded, modelsError == nil,
              !defaults.bool(forKey: gpuRefreshKey) else { return }
        refreshingForGPU = true
        defer { refreshingForGPU = false }
        let names = models.map(\.name).filter(Self.gpuModels.contains)
        do {
            for name in names {
                for try await _ in pull(name) {}
            }
        } catch {
            return
        }
        defaults.set(true, forKey: gpuRefreshKey)
        if !names.isEmpty { preload() }
    }
```

- [ ] **Step 5: Run the tests and see them pass**

Run the full test command (Task 1, Step 6). Expected: `** TEST SUCCEEDED **`: the six new tests
pass and so does every existing one. Existing tests that call `connect()` leave a refresh waiting
on a pull that the fake never finishes; that is expected and harmless.

- [ ] **Step 6: Spec §4 wording**

In `docs/superpowers/specs/2026-09-26-ollaya-v0.7.1-design.md` §4, change the start of the
"**Once:**" bullet from `Karar sets a \`UserDefaults\` flag` to:

`Karar sets a \`UserDefaults\` flag, keyed by the model store (\`gpuRefresh:<OLLAYA_MODELS or "default">\`, because every Karar build shares one defaults domain),`

- [ ] **Step 7: Commit**

```bash
git add Karar/AppModel.swift KararTests/AppModelTests.swift docs/superpowers/specs/2026-09-26-ollaya-v0.7.1-design.md
git commit -m "Move existing installs to the Apple GPU with a one-time silent re-pull

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Catalog: new sizes, von, kev, decision

**Files:**
- Modify: `Karar/Catalog.json`
- Modify: `KararTests/CatalogTests.swift` (`testBundlesTheCatalogWithLayaRecommendedFirst`)
- Modify: `THIRD_PARTY.md` (Models table)

**Interfaces:**
- Consumes: `CatalogEntry` (unchanged). `AboutView.modelLicences` picks up the new entries by
  itself; `AboutTests.testModelLicencesComeFromTheCatalog` still expects `["Apache-2.0", "MIT"]`.

- [ ] **Step 1: Write the failing test**

In `CatalogTests.testBundlesTheCatalogWithLayaRecommendedFirst`, replace the expected names:

```swift
        XCTAssertEqual(names, ["laya", "laya:multilingual", "laya:en", "laya:typed-decisions",
                               "nli:modernbert-large", "nli", "gliclass", "decider:0.8b", "decider",
                               "von", "kev", "decision"])
```

- [ ] **Step 2: Run it and see it fail**

Run: `xcodebuild … test -only-testing:KararTests/CatalogTests 2>&1 | tail -20` (full command as in Task 1, Step 2, with `CatalogTests`)
Expected: FAIL on the names.

- [ ] **Step 3: Re-check the registry sizes**

Sizes are manifest totals (config plus layers). Run:

```sh
A='Accept: application/vnd.oci.image.manifest.v1+json'
for m in laya:latest laya:multilingual laya:en nli:modernbert-large von:latest kev:latest decision:latest; do
  curl -fsSL -H "$A" "https://ollaya.dev/v2/library/${m%%:*}/manifests/${m##*:}" \
    | jq -r --arg m "$m" '"\($m) \((.config.size // 0) + ([.layers[].size] | add))"'
done
```

Expected (2026-09-26):

| Model | Size |
|---|---|
| `laya:latest` | 10730 |
| `laya:multilingual` | 684162752 |
| `laya:en` | 853636311 |
| `nli:modernbert-large` | 798926208 |
| `von:latest` | 1587952249 |
| `kev:latest` | 1822775186 |
| `decision:latest` | 1537148811 |

`laya` = 10730 + 853636311 + 684162752 = 1537809793. If any number differs, use the new one, and
recompute `laya`: `CatalogTests.testTheRouterIncludesItsTargetsInRouteOrder` checks that sum.

- [ ] **Step 4: Edit `Karar/Catalog.json`**

- Set `size` to `1537809793` for `laya`, `684162752` for `laya:multilingual`, `853636311` for
  `laya:en` and `798926208` for `nli:modernbert-large`.
- Append after the `decider` entry (licences and languages from upstream
  `convert/ollaya_convert/catalog.py` and `docs/families/*.md` at v0.7.1):

```json
  {"name": "von", "summary": "Victor Hugo Panisa's Von 1.1 on ModernBERT-large (395M parameters). Reads long text: 8,192 tokens.",
   "languages": "English", "license": "Apache-2.0", "size": 1587952249, "recommended": false, "includes": []},
  {"name": "kev", "summary": "Jared Palmer's Kev on Qwen3.5-0.8B. Reads 8,192 tokens; slower than Laya.",
   "languages": "English", "license": "Apache-2.0", "size": 1822775186, "recommended": false, "includes": []},
  {"name": "decision", "summary": "Decision 1.0 Eos by the vLLM Semantic Router contributors, on Qwen3.5-0.8B. Reads 16,384 tokens; slower than Laya.",
   "languages": "English, Chinese", "license": "Apache-2.0", "size": 1537148811, "recommended": false, "includes": []}
```

(Add a comma after the `decider` entry's closing brace.)

- [ ] **Step 5: Run the tests and see them pass**

Run the full test command. Expected: `** TEST SUCCEEDED **`, `AboutTests` included.

- [ ] **Step 6: Try every new model on the real engine**

Use a separate scratch store (`NEW=<scratchpad>/new-models`, ~5 GB) and Karar's bundled engine
on 11436. Per model:
- pull it;
- read its licence;
- run all five presets and one custom question set (a choice, a score and a noul);
- time five warm requests.

```sh
NEW=<scratchpad>/new-models; mkdir -p "$NEW"; H=127.0.0.1:11436
OLLAYA_HOST=$H OLLAYA_MODELS="$NEW" build/Build/Products/Debug/Karar.app/Contents/MacOS/ollaya serve > "$NEW.log" 2>&1 & pid=$!
until curl -fs -m 1 http://$H/ >/dev/null; do sleep 0.2; done
text="Hi, I was charged twice for my subscription this month. Please refund the second payment. I have been a customer for three years, but if this is not fixed by Friday I will cancel my account."
custom='{"topic":{"type":"choice","instructions":"What is the message about?","criteria":{"billing":"Payments, refunds","technical":"Something broken","other":"Anything else"}},"anger":{"type":"score","instructions":"How angry is the writer?","criteria":["Calm","Annoyed","Angry"]},"wants_refund":{"type":"noul","instructions":"The writer asks for money back."}}'
for m in von kev decision; do
  curl -fsN http://$H/api/pull -d "{\"model\":\"$m\"}" | tail -n 1                   # {"status":"success"}
  curl -fs http://$H/api/show -d "{\"model\":\"$m\"}" | jq -r '.license' | head -3
  for p in triage email guard moderation router; do
    jq -n --arg m "$m" --arg s "$text" --slurpfile q Karar/Presets/$p.json '{model:$m, state:$s, questions:$q[0]}' \
      | curl -fs http://$H/api/decide -d @- | jq -c --arg p "$p" '{p:$p, n:(.answers|length), ms:(.total_duration/1e6|floor), trunc:.state_truncated}'
  done
  jq -n --arg m "$m" --arg s "$text" --argjson q "$custom" '{model:$m, state:$s, questions:$q}' \
    | curl -fs http://$H/api/decide -d @- | jq -c '{custom:.answers|map_values(.choice // .score // .noul)}'
  for i in 1 2 3 4 5; do
    jq -n --arg m "$m" --arg s "$text" --slurpfile q Karar/Presets/triage.json '{model:$m, state:$s, questions:$q[0]}' \
      | curl -fs http://$H/api/decide -d @- | jq -r '.total_duration/1e6|floor'
  done | sort -n | sed -n 3p | sed "s/^/$m warm median ms: /"
  curl -fs http://$H/api/ps | jq -c --arg m "$m" '.models[] | select(.name | startswith($m)) | {name, device}'
done
kill $pid; wait $pid
```

Expected for each model:
- the pull ends in `success`;
- the licence text is Apache-2.0;
- each preset returns its question count (triage 5, email 5, guard 5, moderation 5, router 4) with
  no error;
- the custom set answers `topic` `billing` and `wants_refund` high;
- the device is `cpu`.

Write the warm medians down for the roadmap notes (Task 6). If a model errors, or its licence is
not Apache-2.0, stop and tell the user before committing. Keep `$NEW` for Task 6 if disk allows,
otherwise delete it.

Note: `/api/show`'s field for the licence is `license`. If it is absent, print the whole
`/api/show` response and read the licence from it; don't guess.

- [ ] **Step 7: `THIRD_PARTY.md` models table**

Append three rows to the Models table:

```markdown
| `von` | [wfzyx/von](https://huggingface.co/wfzyx/von) | Apache-2.0 |
| `kev` | [jaredpalmer/kev-0.8b](https://huggingface.co/jaredpalmer/kev-0.8b) on [Qwen/Qwen3.5-0.8B-Base](https://huggingface.co/Qwen/Qwen3.5-0.8B-Base) | Apache-2.0 |
| `decision` | [llm-semantic-router/Decision-1.0-Eos-0.8B](https://huggingface.co/llm-semantic-router/Decision-1.0-Eos-0.8B) | Apache-2.0 |
```

- [ ] **Step 8: Commit**

```bash
git add Karar/Catalog.json KararTests/CatalogTests.swift THIRD_PARTY.md
git commit -m "Catalog: sizes with the arch layer; add von, kev and decision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: v0.2.0: end-to-end refresh in the app, Release build, README and site

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: "0.2.0"`, `CURRENT_PROJECT_VERSION: "5"`), then regenerate `Karar.xcodeproj`
- Modify: `README.md` (intro paragraph, line 14–15), `site/index.html` (intro, lines 18–20)

- [ ] **Step 1: The refresh end to end in the real app (spec §7.5)**

With the old-install store from the recipe. It is still old after Task 1, Step 9; if unsure, run the recipe's `for` loop again first:

```sh
osascript -e 'tell application id "io.github.omerhakanbilici.karar" to quit' 2>/dev/null
defaults delete io.github.omerhakanbilici.karar "gpuRefresh:$STORE" 2>/dev/null
open -n --env OLLAYA_MODELS="$STORE" build/Build/Products/Debug/Karar.app --args -ApplePersistenceIgnoreState YES -KararText "I was charged twice. Please refund me."
sleep 15
defaults read io.github.omerhakanbilici.karar "gpuRefresh:$STORE"                 # 1
for t in en multilingual; do jq -r '[.layers[].mediaType | select(endswith(".arch"))] | length' "$STORE/manifests/ollaya.dev/library/laya/$t"; done   # 1, 1
curl -fs http://127.0.0.1:11435/api/ps | jq -c '[.models[] | {name, device}]'
```

Expected:
- the flag is `1`;
- both manifests have one arch layer;
- `/api/ps` lists the selected model on `metal`. The CPU runner from before the refresh may be
  listed too (the known ceiling).

Take a window capture: answers are on screen and the timing shows in ms after one more
answer. Then quit Karar, relaunch it the same way, wait 15 s, and confirm that no manifest file
changed (`stat -f %m` on both is the same as before the relaunch). Quit it again.

- [ ] **Step 2: README and site sentence**

- `README.md`: replace the two lines `Karar bundles the engine, downloads models for you, and re-runs the questions every time you` / `pause typing.` with:

  ```markdown
  Karar bundles the engine, downloads models for you, and re-runs the questions every time you
  pause typing. On the Apple GPU, `laya` answers in tens to hundreds of milliseconds.
  ```

- `site/index.html`: in the intro paragraph, after
  `downloads models for you and re-runs the questions every time you pause typing.`, add the
  sentence `On the Apple GPU, <code>laya</code> answers in tens to hundreds of milliseconds.`,
  before `Everything runs on your Mac.`

- [ ] **Step 3: Version 0.2.0**

In `project.yml` set `MARKETING_VERSION: "0.2.0"` and `CURRENT_PROJECT_VERSION: "5"`; run
`xcodegen generate`.

- [ ] **Step 4: Full tests, UI tests, Release build, DMG**

```sh
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test 2>&1 | tail -3
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build 2>&1 | tail -3
app=build/Build/Products/Release/Karar.app
codesign --verify --deep --strict "$app" && echo sealed
codesign -dv "$app/Contents/MacOS/ollaya" 2>&1 | grep flags                 # adhoc,runtime
vtool -show-build "$app/Contents/MacOS/ollaya" | grep minos                  # 14.0
ls -la "$app/Contents/Resources/mlx_metal/mlx.metallib"
KARAR_SMOKE_MODELS="$STORE" scripts/smoke.sh                                 # Release build; … on metal
scripts/make-dmg.sh                                                          # prints Karar.dmg (<size>)
```

Expected:
- both builds succeed;
- the bundle is `sealed`, `ollaya` is `adhoc,runtime` with `minos 14.0`;
- the metallib is present;
- the smoke test passes `on metal`;
- the DMG is about 60 MB. Note the exact size.

Then the UI tests, local only. The user must approve the Automation Mode prompt; quit every Karar
first:

`TEST_RUNNER_KARAR_UITEST_MODELS="$STORE" xcodebuild -project Karar.xcodeproj -scheme KararUITests -destination 'platform=macOS' -derivedDataPath build test 2>&1 | tail -5`

Expected: all 6 pass.

- [ ] **Step 5: Commit**

```bash
git add project.yml Karar.xcodeproj README.md site/index.html
git commit -m "v0.2.0: Ollaya v0.7.1 on the Apple GPU

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Screenshots, roadmap, the user's check, release

**Files:**
- Overwrite: `docs/screenshots/main-light.png`, `main-dark.png`, `advanced-light.png`, `advanced-dark.png`
- Modify: `docs/superpowers/plans/2026-09-24-karar-roadmap.md`

- [ ] **Step 1: Retake the four screenshots with ms timings (spec §7.8)**

Same framing as the current files (compare side by side before overwriting):
- 2× from the built-in display, window activated first (`osascript … to activate`);
- `main-*`: Advanced off, sidebar shown; `advanced-*`: Advanced on;
- the Release build, with a scratch store holding `laya` with the arch layer (the Task 5 store
  after the refresh);
- the sample ticket and the Support ticket set, as now.

The first answer includes the cold load (~1–1.3 s). Get one warm answer before each capture:
after the first answer, switch the question set away and back, or ask the user to type one
character. Check that the timing reads in ms. Capture light and dark
(`-KararAppearance light|dark`). Show the four images to the user and get an OK before
overwriting.

- [ ] **Step 2: Roadmap**

In `docs/superpowers/plans/2026-09-24-karar-roadmap.md`, tick Phase 9 (`- [x]`) and add under
"Notes for later phases":
- Ollaya v0.7.1 (DMG size, the new models' warm medians from Task 4, the GPU numbers);
- the GGUF refusal text;
- that library validation blocks ad-hoc llama.cpp dylibs;
- anything that surprised you.

- [ ] **Step 3: Commit, then ask the user**

```bash
git add docs/screenshots docs/superpowers/plans/2026-09-24-karar-roadmap.md
git commit -m "Phase 9 done: screenshots with GPU timings, roadmap notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Hand the user the Release `Karar.app` or `Karar.dmg` to try (their own `~/.ollaya`: the silent
refresh moves their `laya` to the GPU). **Only after their explicit OK in this session:**
1. check `git log --format='%ae %ce' | sort -u` (noreply only);
2. merge or push to `main` (no force-push);
3. tag `v0.2.0` and push the tag, so `release.yml` publishes `Karar.dmg`.

Then check that `releases/latest/download/Karar.dmg` is the new one.
