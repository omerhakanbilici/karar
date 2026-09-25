# Karar roadmap

Spec: [`../specs/2026-09-24-karar-design.md`](../specs/2026-09-24-karar-design.md)

Karar is built in phases. **One phase per session.** Every phase ends with working, tested software
and a commit, so any session can start from a clean `main`.

## How a session works

1. Read `CLAUDE.md`, this file and the spec.
2. Take the first phase below that is not `[x]`.
3. If that phase has no plan file yet, write it with `superpowers:writing-plans`, based on the
   spec, this phase's goal and acceptance criteria, and **the code as it is now**. Save it as
   `docs/superpowers/plans/<date>-phase-N-<name>.md` and link it below. Commit.
4. Execute the plan (`superpowers:subagent-driven-development` or `superpowers:executing-plans`).
5. Check every acceptance criterion, tick the phase `[x]` here, add a one-line note under
   "Notes for later phases" if something surprised you, commit, stop.

Plans are written at the start of their phase, not all up front, so they match the real code.

## Phases

- [x] **Phase 1 — Foundation: the engine runs inside the app.**
  Plan: [`2026-09-24-phase-1-foundation.md`](2026-09-24-phase-1-foundation.md)
  Xcode project (XcodeGen), pinned Ollaya fetched and embedded, `OllayaClient` (liveness, version,
  tags), `Daemon` (adopt / start / restart once / stop), a window that shows engine status and
  installed models. LICENSE, NOTICE.
  *Acceptance:* `xcodebuild test` passes; launching Karar starts `ollaya serve` as a child;
  quitting Karar stops it; with a CLI `ollaya serve` already running, Karar adopts it and leaves it
  running on quit; a Release build is signed `adhoc,runtime`.

- [x] **Phase 2 — Decide: live results in the main window.**
  Plan: [`2026-09-24-phase-2-decide.md`](2026-09-24-phase-2-decide.md)
  `POST /api/decide` types + client method, bundled presets (`Presets/*.json`, copied from Ollaya
  `crates/ollaya/src/presets/` at the pinned version), `AppModel`, `NavigationSplitView` with
  sidebar (installed models), toolbar Model + Question set pickers, `TextEditor`, simple-mode result
  rows (spec §3.2), live updates (cancel in-flight, 300 ms debounce). Models are pulled with the
  CLI for now.
  *Acceptance:* typing updates the results; switching model or question set re-runs; latency on
  this Mac measured and written into "Notes" (spec §9 risk 3).

- [x] **Phase 3 — Models: download, delete, onboarding.**
  Plan: [`2026-09-24-phase-3-models.md`](2026-09-24-phase-3-models.md)
  `POST /api/pull` NDJSON stream → `AsyncThrowingStream`, `DELETE /api/delete`, `Catalog.json`,
  "Download model…" sheet, onboarding flow (spec §3.1) shown when no model is installed, sample
  ticket prefilled after first download.
  *Acceptance:* on a machine with an empty model store (use `OLLAYA_MODELS` pointing to an empty
  dir), a new user goes from launch to a live result without the terminal; interrupted download
  resumes on Retry.

- [x] **Phase 4 — Advanced mode.**
  Plan: [`2026-09-25-phase-4-advanced.md`](2026-09-25-phase-4-advanced.md)
  Advanced toggle (`@AppStorage`), editable question cards (choice / score / noul, add / remove),
  "My questions…", `.inspector` with routing, timings, tokens, response JSON, Copy JSON, Copy as
  curl; `422` `detail[].loc` marks the failing card; `state_truncated` note; ⌘↩ pins results to the
  sidebar (in memory).
  *Acceptance:* a custom question set built only in the UI returns answers; an invalid one shows
  the error on the right card; copied curl works in Terminal.

  *Also (user, Phase 3 session) — token counter and truncation warning (spec §3.2, §5), in simple
  mode too:* add `state_truncated` and `usage.input_tokens` to `DecideResponse`; a small secondary
  counter in the editor's bottom-right corner shows the last response's `usage.input_tokens`
  ("118 tokens"), never a character estimate; on `state_truncated: true` it turns into an orange
  warning "Text too long for <model>: only the first part was read" (replaces the old "Text was
  shortened" note). **Before planning, check on the real engine** (scratch `OLLAYA_MODELS`, never
  `~/.ollaya`): does `input_tokens` include the questions and options, and after truncation is it
  the original or the truncated length? Write the answer into Notes and design the counter on it.

- [ ] **Phase 5 — Polish: errors, About, icon.**
  Plan: [`2026-09-25-phase-5-polish.md`](2026-09-25-phase-5-polish.md)
  All rows of spec §5 (error banner with Restart, port-in-use message, pull errors + Retry, deleted
  model fallback), About window (versions + licences, spec §3.3), app icon, empty states, keyboard
  shortcuts, light/dark check of every screen.
  *Acceptance:* each §5 situation reproduced by hand shows the specified UI.

  *Also (user, Phase 4 session) — app icon:* a plain balance scale, slightly tilted (one pan a
  little lower), no sword or blindfold; white on an orange background. An original drawing, not an
  SF Symbol. Its orange need not match the in-app truncation warning's system orange.

- [ ] **Phase 6 — Release: DMG, CI, repo docs, publish.**
  `scripts/make-dmg.sh` (always `Karar.dmg`), `scripts/smoke.sh`, `.github/workflows/release.yml`
  (tag `v*` → fetch Ollaya → test → Release build → `Karar.dmg` → GitHub Release), `README.md`,
  `THIRD_PARTY.md`, screenshots (light + dark). **Ask the user before** creating the public GitHub
  repo `omerhakanbilici/karar`, pushing, and tagging `v0.1.0`.
  *Acceptance:* `releases/latest/download/Karar.dmg` downloads; the DMG installs on a clean user
  account via the "Open Anyway" flow.

  *Also (user, Phase 5 session) — UI tests (XCUITest):* add a `KararUITests` target to
  `project.yml` (`type: bundle.ui-testing`, synced folder; `xcodegen generate`, commit both). No
  third-party code: XCTest/XCUITest only, no Appium, ViewInspector or snapshot libraries. Add
  `.accessibilityIdentifier` to the views the tests select. Launch the app with
  `launchArguments`/`launchEnvironment`: the existing DEBUG arguments (`-KararText`,
  `-KararQuestions`, `-KararAppearance`, `-advanced`, `-ApplePersistenceIgnoreState YES`) and a
  scratch `OLLAYA_MODELS` (never `~/.ollaya`). A few smoke tests are enough:
  1. launch → main window;
  2. typing brings answer rows;
  3. ⌘↩ adds a pin to the sidebar;
  4. with port 11435 held by something that is not Ollaya, the banner shows;
  5. with an empty model store, onboarding opens.
  Attach window images to the test results with `XCUIElement.screenshot()` (light and dark); they
  can feed the README and site screenshots. Heavy cases (a real download, a cold load) stay in
  `scripts/smoke.sh` and the manual check. **Before planning, decide with the user:** (a) whether
  the UI tests run in CI (a GitHub macOS runner would have to download a model, ~800 MB) or only
  locally; (b) running them locally needs Automation mode / Accessibility enabled once
  (`automationmodetool`) — the user does that; never change the system setting yourself.

- [ ] **Phase 7 — Website.**
  `site/index.html` + `style.css` per spec §8, `.github/workflows/pages.yml`. **Ask the user** to set
  Settings → Pages → Source = GitHub Actions.
  *Acceptance:* `https://omerhakanbilici.github.io/karar/` is live, the Download button fetches the
  DMG, both themes render correctly.

## After v1 (not scheduled)

Ideas, not phases. Spec §2 lists auto-update as out of scope for v1.

- **Keeping the bundled Ollaya current.** The engine is pinned in `scripts/fetch-ollaya.sh`
  (`OLLAYA_VERSION` + `OLLAYA_SHA256`); a runtime update means a new Karar release. Karar never
  downloads an engine at run time: that would break the signed bundle and Hardened Runtime, and the
  API contract and `Catalog.json` are verified against one pinned tag. Upstream ships several
  releases a day, so bump only for a reason (a bug fix, a new model family, an API feature we need).
  Steps: update both values, diff upstream `docs/api.md` between the two tags (§12 versioning, §13
  compatibility), re-check `Catalog.json` against the new registry, run `xcodebuild test` and
  `scripts/smoke.sh`, then tag.
- **Idea: scheduled bump PR.** A weekly GitHub Actions job checks the latest `ollaya-dev/ollaya`
  release. If it is newer than the pin, it updates `fetch-ollaya.sh`, runs the tests and the smoke
  test, and opens a PR with the `api.md` diff attached. It never merges or tags on its own.
- **Idea: "new version available" note in Karar.** On launch, one GitHub Releases API call for
  `omerhakanbilici/karar`; if a newer release exists, a small note in the sidebar links to the DMG.
  No Sparkle (no third-party dependencies); installing stays manual. An LM Studio-style runtime
  page or Settings window only if there is ever more than this to configure.

## Notes for later phases

- Pinned Ollaya `v0.3.2` targets macOS 11.0 (`vtool -show-build`), ships ad-hoc signed, and ships
  `LICENSE`, `THIRD_PARTY_NOTICES`, `onnxruntime-ThirdPartyNotices.txt` in `share/doc/ollaya/`;
  deployment target stays 14.0 (spec §9 risk 1 resolved).
- `ollaya serve` exits cleanly on SIGTERM ("shutting down").
- Swift 6 / Xcode 27: `@State var x = Daemon(probe: { … })` fails ("default argument cannot be both
  main actor-isolated and @concurrent"). The engine lifecycle now lives in `AppDelegate`
  (`@NSApplicationDelegateAdaptor`, start in `applicationDidFinishLaunching`, stop in
  `applicationWillTerminate`) with a single `Window` scene; Phase 2's `AppModel` should take the
  `Daemon` from there, never start it from a view.
- The nested `ollaya` is re-signed in the embed script with `--options runtime` and runs fine under
  Hardened Runtime. Add `--timestamp` when moving to Developer ID.
- The CLI daemon on this Mac (`/usr/local/bin/ollaya`) is also 0.3.2. Since Phase 2 the sidebar caption
  warns when the running engine's `/api/version` differs from `Contents/Resources/Ollaya/VERSION`.
- Open for later: `liveness()` maps a 1 s `.timedOut` to `.other` (false "port in use", Phase 5);
  `StatusView` swallows `tags()` errors as "No models yet"; `ollaya.log` grows without rotation;
  `testConcurrentStartsLaunchOnlyOnce` doesn't exercise the in-flight half of the guard (fake probe
  never suspends).
- UI checks: Screen Recording is granted, so capture only Karar's window (never the full screen):
  window id from `CGWindowListCopyWindowInfo` (owner "Karar", layer 0, widest), then
  `screencapture -x -o -l <id>`. Typing into the app still needs the user (no Accessibility).
- Latency (spec §9 risk 3), M1 Pro, CLI daemon 0.3.2, warm, median of 5, same English ticket:
  5-question presets take 0.90–1.27 s on `laya:en` (and `laya`, which routes English to it) and
  0.36–0.47 s on `laya:multilingual`; time is linear in the question count (~250 ms/question on
  `laya:en`, ~90 ms on multilingual). A cold model adds 2.5–3.3 s (load), which also happens after
  the default 5 m `keep_alive` expires. So results arrive 0.4–1.3 s after typing pauses, not the
  < 150 ms the spec assumed; the 300 ms debounce + cancel still works, with a spinner and dimmed rows.
  Cancelling a request that is already running does not stop its forward pass (api.md §10), so a
  burst of edits can wait for one extra pass. Consider a longer `keep_alive` or a preload on model
  selection if cold starts annoy (Phase 5).
- Presets: question order matters and JSONDecoder loses key order, so `Preset.topLevelKeys` scans it
  and the request body splices the preset bytes verbatim. `DecideResponse` must be decoded without
  `.convertFromSnakeCase` (it would rename `is_urgent` in `answers`).
- Deferred from Phase 2 reviews: `Answer.legend` is `[String: String]?`, but score levels may be
  objects/arrays in custom questions (Phase 4); a stale error stays after an automatic engine
  restart until the next edit (Phase 5); concurrent `refreshModels()` calls can finish out of order,
  and "No models yet" flashes before the first refresh (Phase 3); the engine version is read in
  `MainView`, not through `AppModel`.
- Phase 3: the Ollaya v0.3.2 registry serves 9 models Karar lists in `Catalog.json` (sizes are
  manifest totals; on this Mac both fp16 and fp32 graphs download). Resume after an interrupted pull
  shows as a jump: the blob's first line says `completed: 0`, the next the bytes already on disk;
  `Download` takes the first non-zero value as the baseline so speed stays honest. Speed is an
  average since the first byte, so idle gaps between a router's parts lower it a little.
- Phase 3: a pull that *joins* one already in flight (e.g. the CLI pulling the same name) may miss
  its `pulling manifest` line, so Karar's bars would stay at 0 until the pull ends. Rare; not handled.
- Phase 3, for Phase 5: `modelsLoaded` stays false if `/api/tags` keeps failing, which leaves the
  start-up spinner up with no error; a newest `refreshModels()` that fails also discards an older
  success. `isOnboarding` is not cleared if models appear from the CLI during onboarding.
- Phase 3: killing Karar with SIGTERM (`pkill`) skips `applicationWillTerminate` and orphans its
  `ollaya`; the next launch then adopts it. Quit with `osascript -e 'tell application id
  "io.github.omerhakanbilici.karar" to quit'` in scripts (it fails while a sheet is open). For UI
  checks: `-NSRequiresAquaSystemAppearance YES` forces light, `-AppleInterfaceStyle Dark` forces dark;
  `OLLAYA_MODELS=<dir>` in Karar's environment reaches the child daemon, so tests never touch
  `~/.ollaya`. The user's CLI daemon was not running during Phase 3; earlier "adopted" daemons were
  Karar-started ones left running.
- Phase 4, measured on the pinned engine (Karar's `vendor/ollaya` on `127.0.0.1:11436`, scratch
  `OLLAYA_MODELS`): `usage.input_tokens` is **not** the text's length. Each question is encoded
  separately as text + that question's instructions + its options + special tokens, and the counts
  are summed over the questions (same text, one noul question: 48; the same question twice: 96;
  adding option descriptions to a 2-option choice: 29 → 46; empty text: 32). After truncation it
  is the **truncated** length: every question is capped at the model's context
  (`model_info["laya.context_length"]` in `/api/show`: 512 for `laya:en`, 1,024 for
  `laya:multilingual`), so a cut-off text on `laya:en` reports exactly 512 per question (1,024 for
  two) with `state_truncated: true`; the original length is not reported anywhere. The router
  `laya` sends long English text to `laya:en` even though `laya:multilingual` would read twice as
  much. Decision (user): the counter shows the engine's number as is, and a tooltip explains that
  it counts the text once per question, with the questions' instructions and options.
- Phase 4: `/api/decide` answers compact JSON, and `JSONSerialization` pretty-printing both
  reorders keys and prints `0.3237` as `0.32369999999999999`, so the inspector re-indents the
  bytes instead. The `guard` preset's `topic` options have `null` descriptions.
- Phase 4: `.inspector` inside the NavigationSplitView detail aborts AppKit ("more Update
  Constraints in Window passes than there are views in the window") when the window is narrower
  than ~960–980 pt, whatever the detail shows. Karar keeps a 1050 pt window floor while Advanced is
  on and grows an open window before showing the inspector (one binding drives the Toggle and the
  inspector). Untried: `.inspector` on the NavigationSplitView itself, which might remove the floor.
- Phase 4: a `422` rejects the whole request, so while one card is red the others show no answer
  either. The inspector then says "No response yet."; the error is on the card.
- Phase 4, for UI checks: DEBUG builds take `-KararText "…"`, `-KararQuestions '{…}'` (read raw:
  the argument domain would parse `{…}` as a plist), `-KararAppearance dark|light` and `-advanced
  YES`; `-AppleInterfaceStyle Dark` does not force dark. Launch with `-ApplePersistenceIgnoreState
  YES` (after a crash the "reopen windows?" alert blocks quitting) and `"-NSWindow Frame main" "x y
  w h …"` for a window size. Captures fail while the screen is locked. `pbpaste` in a shell without
  `LANG` mangles non-ASCII (Karar's copied curl is fine).
- Deferred from Phase 4 reviews: a hand-typed duplicate choice label is sent as a duplicate JSON
  key (only "Add option" picks a free one); `growWindowIfNeeded()` doesn't cap the width on screens
  narrower than 1050 pt; new `JSONDecoder` per key in `OrderedJSON.members`.
- UI tests (Phase 6): XCUITest drives the real mouse and keyboard while it runs (don't use the Mac
  meanwhile) and does not work while the screen is locked.
- Phase 4: the `laya` router sent a Turkish ticket to `laya:multilingual` with the reason "Latin
  script but language looks like 'it'" (routing is right, language guess is not).
