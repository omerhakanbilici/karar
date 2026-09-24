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

- [ ] **Phase 3 — Models: download, delete, onboarding.**
  `POST /api/pull` NDJSON stream → `AsyncThrowingStream`, `DELETE /api/delete`, `Catalog.json`,
  "Download model…" sheet, onboarding flow (spec §3.1) shown when no model is installed, sample
  ticket prefilled after first download.
  *Acceptance:* on a machine with an empty model store (use `OLLAYA_MODELS` pointing to an empty
  dir), a new user goes from launch to a live result without the terminal; interrupted download
  resumes on Retry.

- [ ] **Phase 4 — Advanced mode.**
  Advanced toggle (`@AppStorage`), editable question cards (choice / score / noul, add / remove),
  "My questions…", `.inspector` with routing, timings, tokens, response JSON, Copy JSON, Copy as
  curl; `422` `detail[].loc` marks the failing card; `state_truncated` note; ⌘↩ pins results to the
  sidebar (in memory).
  *Acceptance:* a custom question set built only in the UI returns answers; an invalid one shows
  the error on the right card; copied curl works in Terminal.

- [ ] **Phase 5 — Polish: errors, About, icon.**
  All rows of spec §5 (error banner with Restart, port-in-use message, pull errors + Retry, deleted
  model fallback), About window (versions + licences, spec §3.3), app icon, empty states, keyboard
  shortcuts, light/dark check of every screen.
  *Acceptance:* each §5 situation reproduced by hand shows the specified UI.

- [ ] **Phase 6 — Release: DMG, CI, repo docs, publish.**
  `scripts/make-dmg.sh` (always `Karar.dmg`), `scripts/smoke.sh`, `.github/workflows/release.yml`
  (tag `v*` → fetch Ollaya → test → Release build → `Karar.dmg` → GitHub Release), `README.md`,
  `THIRD_PARTY.md`, screenshots (light + dark). **Ask the user before** creating the public GitHub
  repo `omerhakanbilici/karar`, pushing, and tagging `v0.1.0`.
  *Acceptance:* `releases/latest/download/Karar.dmg` downloads; the DMG installs on a clean user
  account via the "Open Anyway" flow.

- [ ] **Phase 7 — Website.**
  `site/index.html` + `style.css` per spec §8, `.github/workflows/pages.yml`. **Ask the user** to set
  Settings → Pages → Source = GitHub Actions.
  *Acceptance:* `https://omerhakanbilici.github.io/karar/` is live, the Download button fetches the
  DMG, both themes render correctly.

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
