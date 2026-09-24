# Karar — design

*Karar — a Mac app for Ollaya.* A native macOS app that bundles the [Ollaya](https://github.com/ollaya-dev/ollaya)
daemon, lets the user download decision models and try them against any text, with live,
calibrated answers.

Status: approved in brainstorming on 2026-09-24. Mockups: `.superpowers/brainstorm/` (not committed).

## 1. What Ollaya gives us

- A single binary (`ollaya`, Rust, Apache-2.0). `ollaya serve` runs a daemon on `127.0.0.1:11435`.
  macOS build: Apple silicon only (`ollaya-darwin-arm64.tgz`), ONNX Runtime + CoreML.
- Decision models never generate text. Input: a **state** (text or JSON) plus typed **questions**.
  Output per question, in one forward pass:
  - `choice` → label, `confidence`, `probabilities`
  - `score` → expected level (e.g. 1.76 of 0–3), `confidence`, `legend`, `probabilities`
  - `noul` → probability that a statement holds (yes/no)
- Models are stateless: no conversation, no follow-up. "Follow-up" = edit the text or the questions
  and run again.
- HTTP endpoints Karar uses (contract: Ollaya `docs/api.md`):

  | Endpoint | Use in Karar |
  |---|---|
  | `GET /` | liveness ("Ollaya is running") |
  | `GET /api/version` | show engine version in About |
  | `GET /api/tags` | installed models (sidebar, model picker) |
  | `POST /api/pull` | download with NDJSON progress (`status`, `digest`, `total`, `completed`) |
  | `DELETE /api/delete` | remove a model |
  | `POST /api/decide` | run questions; response adds `routing`, `total_duration`, `eval_duration`, `usage` |

- Built-in presets (question sets): `triage`, `email`, `guard`, `moderation`, `router`.
  They live in the Ollaya binary (`crates/ollaya/src/presets/*.json`), not in the HTTP API, so
  Karar ships its own copies of those JSON files (Apache-2.0, attributed in `THIRD_PARTY.md`).
- There is no HTTP endpoint that lists models available in the remote registry. Karar ships a small
  curated `Catalog.json` (name, one-line description, languages, license).

## 2. Scope of v1

In:
- Bundled Ollaya daemon, started and stopped by the app.
- First-run onboarding: welcome → pick first model → download with progress → main window.
- Main window with live results, presets, model picker, pinned results (session only).
- One **Advanced** toggle: editable questions + inspector (routing, timings, tokens, JSON, copy as curl).
- Model management: download, delete.
- English-only UI.
- Automatic light/dark appearance.
- Ad-hoc-signed DMG on GitHub Releases, built by GitHub Actions. The asset is always named
  `Karar.dmg` (no version in the file name), so
  `https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg` always points to
  the latest release.
- Project website in `site/`, published with GitHub Pages at `omerhakanbilici.github.io/karar` (§8).

Out (later, if needed): saved custom question sets, persistent history, `ollaya create` / Modelfiles,
Developer ID signing + notarization, auto-update, localization (Turkish or others), Intel Macs, App Store,
a custom domain for the website (added later with a `CNAME` file).

## 3. Screens

### 3.1 Onboarding (when no model is installed, e.g. on first launch)

1. **Welcome.** App icon, one sentence ("Ask typed questions about any text and get calibrated answers
   in milliseconds. Everything runs on this Mac."), a status line "Ollaya engine ready vX.Y.Z".
   No install step: the engine is inside the app. Button: Continue.
2. **Choose your first model.** Radio list from `Catalog.json`; `laya` preselected and marked
   Recommended (fast, 100+ languages). Each row: name, one-line description, size (from the manifest
   once known, "~" estimate from the catalog before), license. Button: Download.
3. **Downloading.** One progress bar per model the pull downloads (a router such as `laya` downloads
   its targets, `laya:en` and `laya:multilingual`, one bar each), with bytes, speed and ETA. Cancel.
   "Get started" enables once the pull reports `success` and the model is listed in `/api/tags`. It opens the main window with a sample support ticket in the
   text box and the *Support ticket* (`triage`) question set selected, so a result shows at once.

### 3.2 Main window

`NavigationSplitView`, single window.

- **Toolbar:** ① **Model** picker (installed models + "Download model…"); ② **Question set** picker
  (presets with human names: Support ticket = `triage`, Email = `email`, Safety = `guard`,
  Moderation = `moderation`, Routing = `router`; plus "My questions…" which turns Advanced on);
  ③ **Advanced** toggle button (state remembered in `@AppStorage`).
- **Sidebar:** Models (installed, loaded one marked) with "+ Download model…"; Pinned results.
- **Content:** a `TextEditor` for the state, then the results.
  - Token counter (simple and advanced mode): a small secondary label in the editor's bottom-right
    corner with `usage.input_tokens` from the last `/api/decide` response ("118 tokens"), never a
    character-based estimate. Models have small context windows (`laya:en`: 512 tokens for text,
    questions and options together) and long text is cut silently, so the editor must not suggest
    that any length works. The engine counts the text once per question, together with that
    question's instructions and options, and sums over the questions (measured in Phase 4), so a
    tooltip says so ("… counted once per question (5 questions)"). When the response has
    `state_truncated: true`, the counter becomes a warning in system orange: "Text too long for <model>: only the first part was read" (§5).
  - Simple mode: one row per question, human label, answer in words ("Yes"/"No", the choice
    label, "1.8 / 3"), a bar, a percentage.
  - Advanced mode: each question is an editable card (id, type, instructions, criteria) showing the
    raw value and confidence; "+ Add question".
- **Inspector** (Advanced only, `.inspector`): answering model, route, total/eval duration, input
  tokens, response JSON, Copy JSON, Copy as curl.
- **Live results:** every edit cancels the in-flight request, waits 300 ms, then calls `/api/decide`.
  ⌘↩ pins the current input + answers to the sidebar (in memory only in v1).

No Settings window in v1: there is nothing to configure yet.

### 3.3 About

Version, engine version, links, and the licences: Karar (Apache-2.0), Ollaya (Apache-2.0),
per-model licences.

## 4. Architecture

```
Karar.app
 ├─ SwiftUI views ──► AppModel (@Observable, @MainActor)
 │                      ├─ Daemon        start / adopt / stop `ollaya serve`
 │                      └─ OllayaClient  URLSession async/await → 127.0.0.1:11435
 └─ Contents/MacOS/ollaya   (bundled, pinned release)
```

- **Platform:** SwiftUI, macOS 14+ (for `@Observable` and `.inspector`), Apple silicon only.
  No third-party dependencies.
- **Daemon** (`Daemon.swift`):
  - On launch: `GET /` on 11435. If it answers "Ollaya is running", adopt that daemon (e.g. the
    user's CLI) and never stop it. If nothing listens, start the bundled binary with `Process`
    (`ollaya serve`), poll `GET /` until ready (timeout 10 s). If something else answers, report
    "port 11435 is in use by another program".
  - On quit: terminate only a daemon Karar started.
  - If a daemon Karar started exits unexpectedly: restart once automatically, then show the error
    banner.
  - Models stay in Ollaya's default store (`~/.ollaya`), shared with the CLI.
- **OllayaClient** (`OllayaClient.swift`): one method per endpoint in §1, Codable types
  mirroring `docs/api.md`. `pull` returns an `AsyncThrowingStream<PullProgress>` built from
  `URLSession.bytes(for:)` + `.lines`. Errors decode Ollaya's error body (`error`, `code`, `detail[].loc`).
- **Bundling Ollaya:** `scripts/fetch-ollaya.sh` downloads the pinned release
  (`OLLAYA_VERSION`, starting at `v0.3.2`) `ollaya-darwin-arm64.tgz`, checks it against
  `sha256sum.txt`, and places `ollaya` where an Xcode build phase copies it into
  `Contents/MacOS/`. The binary is not committed.
- **Identity & signing:** bundle ID `io.github.omerhakanbilici.karar`, fixed from day one.
  Hardened Runtime on from day one; the app and the nested `ollaya` are ad-hoc signed.
  No App Sandbox (Karar spawns a process and shares `~/.ollaya` with the CLI).
  Moving to Developer ID later = certificate + secrets + `codesign --options runtime`,
  `notarytool`, `stapler` steps in CI; no code changes.
- **Language:** English only, no String Catalog in v1. SwiftUI `Text("…")` literals are already
  localizable keys, so adding languages later is a String Catalog plus translations, no code rewrite.
- **Appearance:** system semantic colours only (`.primary`, `.secondary`, `.tint`, materials;
  system orange only for the truncation warning in §3.2, system red only for a question card
  with a validation error in §5);
  no custom palette, so light/dark follows macOS automatically.

## 5. Error handling

| Situation | What the user sees |
|---|---|
| Bundled daemon fails to start / crashes twice | Banner at the top of the window: message + Restart |
| Port 11435 used by something that is not Ollaya | Banner: port in use, how to free it |
| Pull fails before streaming (404, 502) | Inline error on the model row + Retry |
| Pull fails mid-stream (`DIGEST_MISMATCH`, `STORAGE_ERROR`, network) | Same; Ollaya resumes from where it stopped on Retry |
| Selected model was deleted outside the app | Picker falls back to empty, shows "Download model…" |
| `422` validation error on custom questions | The card named by `detail[].loc` is marked red with `msg` |
| `state_truncated: true` | The editor's token counter (§3.2) turns into an orange warning: "Text too long for <model>: only the first part was read" |

## 6. Testing

- `KararTests` (XCTest):
  - decode every JSON example from Ollaya `docs/api.md` used by Karar (decide, tags, pull lines, errors);
  - pull progress parsing from recorded NDJSON;
  - Daemon decision logic (adopt / start / port busy) against a stubbed liveness check.
- `scripts/smoke.sh`: real engine, local only: start bundled `ollaya serve`, `pull laya:en`,
  one `decide`, check the answer shape.
- Manual checklist before each release: first run on a clean user account, light/dark, Gatekeeper "Open Anyway" flow on the DMG.

## 7. Repository and open-source hygiene

Public repo `github.com/omerhakanbilici/karar`.

```
karar/
  Karar.xcodeproj
  Karar/        KararApp.swift, AppModel.swift, Daemon.swift, OllayaClient.swift,
                Views/, Catalog.json, Presets/*.json, Assets.xcassets
  KararTests/
  scripts/      fetch-ollaya.sh, make-dmg.sh, smoke.sh
  .github/workflows/release.yml   (tag v* → fetch Ollaya → build → Karar.dmg → GitHub Release)
  .github/workflows/pages.yml     (push to main touching site/** → actions/deploy-pages)
  site/         index.html, style.css, screenshots (see §8)
  LICENSE       Apache-2.0
  NOTICE        "Includes Ollaya (https://github.com/ollaya-dev/ollaya), Apache-2.0"
  THIRD_PARTY.md  Ollaya licence text, bundled preset files, model licences
  README.md     what it is, screenshots (light + dark), install from DMG incl. Gatekeeper
                "Open Anyway" steps, build from source, licences
```

- Name: "Karar" is ours; "Ollaya" is used only descriptively ("a Mac app for Ollaya"), per
  Apache-2.0 §6. README states Karar is not affiliated with the Ollaya project.
- Model weights are never redistributed by Karar; Ollaya downloads them from the authors'
  Hugging Face repositories.

## 8. Website

`site/` in this repo, published by GitHub Pages at `https://omerhakanbilici.github.io/karar/`.

- Plain `index.html` + `style.css`, no framework, no build step, no JavaScript needed.
- English only. Light/dark follows `prefers-color-scheme` automatically.
- Content, top to bottom:
  1. Name, tagline ("Karar — a Mac app for Ollaya") and a one-paragraph intro.
  2. A large **Download for Mac** button →
     `https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg`, with
     "Apple silicon · macOS 14+" underneath and an **All releases** link to `/releases`.
  3. Screenshots of the main window, light and dark, via `<picture>` with a
     `prefers-color-scheme` source, so each visitor sees the one that matches their theme.
  4. **First launch** steps for Gatekeeper: open the DMG, drag Karar to Applications, open it, then
     System Settings → Privacy & Security → **Open Anyway**.
  5. Footer: Apache-2.0, "Built on Ollaya (Apache-2.0). Not affiliated with the Ollaya project.",
     links to the repo and to ollaya.dev.
- `.github/workflows/pages.yml`: on push to `main` with changes under `site/**` (plus
  `workflow_dispatch`), `actions/upload-pages-artifact` with `path: site` then
  `actions/deploy-pages`. Permissions: `pages: write`, `id-token: write`.
- One-time repo setting: Settings → Pages → Source = **GitHub Actions**.
- The download link only works once the first release exists. The release workflow must upload
  the DMG under exactly `Karar.dmg`.

## 9. Open risks

1. Ollaya's macOS minimum version is undocumented upstream; check with `vtool -show-build` on the
   pinned binary and set the deployment target to the higher of that and 14.0.
2. Ollaya ships several releases per day; pinning + checksum protects us, but API drift is possible
   between pins. Bumping `OLLAYA_VERSION` requires running `smoke.sh`.
3. Real latency on Apple silicon (CPU/CoreML) is unmeasured; 300 ms debounce assumes < ~150 ms per call.
