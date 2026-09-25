# Phase 8 — Toolbar overflow (») fix

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [x]`.

**Goal:** no » in the toolbar in any frame when Advanced opens/closes, when the sidebar is hidden or
shown (Advanced on and off), and while resizing the window down; both SDKs (27 local, 26.5 runner),
light and dark. Then refresh the screenshots and release v0.1.3.

## Root cause (found in this session, with evidence)

The user's own region video (v0.1.2, 1050 pt window) shows the » only during animations: Advanced
opening, and showing the sidebar while Advanced is on. A throwaway probe (split view item frames +
`NSToolbarItem.isVisible` on every change, 240 Hz) plus a throwaway XCUITest (real clicks) showed:

- The » is always the **system sidebar toggle** (`toggleSidebar`) going into the overflow. With all
  of Karar's toolbar items removed except one, it still happens → options 2 and 4 of the roadmap
  (move Advanced out of the toolbar, fewer items) cannot fix it.
- When AppKit reveals the sidebar it treats the window's `contentMinSize` as the detail column's
  minimum and adds the sidebar (220 pt) on top. If the window is narrower than
  `contentMinSize + 220`, it should grow the window (it does, without animation: 720 → 940); the
  **animated** reveal never grows it, so the content split is laid out that much wider than the
  window and shifted left, and the toolbar's sidebar section loses the toggle to the overflow until
  the animation ends. Measured max detail width = window min + 220 every time (720→940,
  1050→1270, 1100→1320). Our min widths (`.frame(minWidth: advanced ? 1050 : 720)`) put the window
  at exactly that minimum, which is why only small windows show it. Setting the same minimum via
  AppKit (`contentMinSize`/`minSize`) reproduces it; `minWidth: 1` removes it.
- Opening `.inspector` makes AppKit collapse and re-reveal the sidebar (under XCUITest, and in the
  user's clicks), hitting the same rule.
- `.inspector` cannot simply lose its minimum: with the inspector open, a 950 pt window crashes
  ("…more Update Constraints in Window passes than there are views in the window",
  NSGenericException) — that is what the 1050 pt minimum was really preventing.

## Decision (with the user)

Option 3 + no minimum width: the inspector becomes a plain trailing column (fixed 320 pt, a
`Divider` before it) inside the detail, and the horizontal minimum width goes. The system sidebar
toggle and its animation stay. Very small windows squeeze or hide elements; the user accepts that
("the user enlarges the window"). Turning Advanced on still grows a narrow window to 1050 pt.

## Files

- Modify: `Karar/Views/MainView.swift` (column instead of `.inspector`, no `minWidth`, comments)
- Modify: `Karar/Views/InspectorView.swift` only if the column needs it (background/padding)
- Modify: `project.yml` (`MARKETING_VERSION` 0.1.3, `CURRENT_PROJECT_VERSION` 4) → `xcodegen generate`
- Overwrite: `docs/screenshots/{main,advanced}-{light,dark}.png`
- Modify: roadmap (tick Phase 8, link this plan, notes)
- Throwaway, never committed: `Karar/Probe.swift`, `KararUITests/ProbeUITests.swift`, the `KARAR_EXP`
  switches in `MainView.swift`

## Tasks

### Task 1: Implement
- [x] Replace `.inspector(isPresented:)` with `HStack(spacing: 0) { content; if advanced { Divider(); InspectorView(app:).frame(width: 320) } }`.
- [x] Drop the horizontal `minWidth` (keep `minHeight: 480`); keep `growWindowIfNeeded()` (1050 pt) so
      Advanced opens readable; rewrite the comments that talk about the inspector's width limits.
- [x] Check first launch without a saved frame still opens at a sensible size; add `.defaultSize`
      on the `Window` scene if not.
- [x] `xcodebuild … test` passes.

### Task 2: Verify (acceptance)
- [x] Probe + XCUITest, real clicks, both SDKs, light and dark, window 1050 and 720 (and 1400):
      Advanced on/off, Hide/Show Sidebar with Advanced on and off → zero states with a hidden
      toolbar item, detail never wider than the window.
- [x] Resize down by dragging the window edge (XCUITest) from 1400 to the smallest width with the
      sidebar shown, Advanced on and off; record at 60 fps; note the width where items start to
      overflow (legitimate, by the decision above).
- [x] Region videos → ffmpeg scene frames, no » in any frame; show the user.
- [x] Remove the throwaway code; build and test again.

### Task 3: Screenshots, release
- [x] Overwrite `docs/screenshots/main-{light,dark}.png` (Advanced off, sidebar shown) and
      `advanced-{light,dark}.png`, 2× from the built-in display, window activated, same framing as now.
- [x] Bump to 0.1.3 (build 4), `xcodegen generate`, tick the roadmap + notes, commit, push to `main`
      (no force-push; noreply email), tag `v0.1.3`, push the tag → `release.yml` publishes the DMG.
- [x] The user confirms on the released build.
