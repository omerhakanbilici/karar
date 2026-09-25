# Karar

Native macOS app (SwiftUI) that bundles the Ollaya decision-model daemon. "Karar — a Mac app for Ollaya".

## Start here every session

- Spec: `docs/superpowers/specs/2026-09-24-karar-design.md`
- Roadmap + progress: `docs/superpowers/plans/2026-09-24-karar-roadmap.md`. Work on the first
  unticked phase only, following "How a session works" there. One phase per session.
- Ollaya's HTTP contract is upstream `docs/api.md` at the pinned tag:
  `https://github.com/ollaya-dev/ollaya/blob/v0.5.0/docs/api.md`

## Commands

```sh
scripts/fetch-ollaya.sh                      # once, and after bumping OLLAYA_VERSION
xcodegen generate                            # after editing project.yml
xcodebuild -project Karar.xcodeproj -scheme Karar -destination 'platform=macOS' -derivedDataPath build test
xcodebuild -project Karar.xcodeproj -scheme Karar -configuration Release -derivedDataPath build build
open build/Build/Products/Debug/Karar.app
```

## Rules

- `project.yml` is the source of truth for the Xcode project. Never hand-edit
  `Karar.xcodeproj/project.pbxproj`; edit `project.yml`, run `xcodegen generate`, commit both.
  Source folders are synced folders: new files under `Karar/` or `KararTests/` need no project change.
- No third-party Swift dependencies. SwiftUI + Foundation only; AppKit only where SwiftUI lacks it.
- System semantic colours only (no custom palette) so light/dark is automatic. The only
  exceptions are in spec §4: system orange (truncation warning), system red (invalid question card).
- UI is English only.
- `vendor/` (the downloaded Ollaya) is never committed.
- Bundle ID `io.github.omerhakanbilici.karar` never changes. Hardened Runtime stays on.
- "Ollaya" is only used descriptively; Karar is not affiliated with the Ollaya project.
- Anything outward-facing (creating the GitHub repo, pushing, tagging, releasing) needs the user's
  explicit OK in that session.
