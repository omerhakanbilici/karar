# Phase 7 — Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `https://omerhakanbilici.github.io/karar/` is live: a one-page site (spec §8) with a
Download button for `Karar.dmg`, the main window in the visitor's theme, and a "First launch"
section that shows both Gatekeeper screens.

**Architecture:** `site/index.html` + `site/style.css`, no JavaScript, no build step. App
screenshots are **not copied** into `site/`: `site/screenshots` is a symlink to
`../docs/screenshots`, so the README and the site read the same files, and
`actions/upload-pages-artifact` follows it (`tar --dereference --hard-dereference`, checked in its
`action.yml` at v5.0.0). Refreshing screenshots after Phase 8 = overwrite the PNGs in
`docs/screenshots/` and push to `main`; `pages.yml` also runs on `docs/screenshots/**`.
The app icon is exported once from `Karar/AppIcon.icon` into `site/icon.png` (it does not change in
Phase 8).

**Tech Stack:** HTML, CSS (`prefers-color-scheme`, `<picture>`), GitHub Actions
(`actions/checkout@v5`, `actions/upload-pages-artifact@v5`, `actions/deploy-pages@v5`), headless
Chrome for local screenshots, `ictool` for the icon.

## Global Constraints

- Plain `index.html` + `style.css`, no framework, no build step, no JavaScript needed. English only.
- Light/dark follows `prefers-color-scheme` automatically.
- Download URL exactly `https://github.com/omerhakanbilici/karar/releases/latest/download/Karar.dmg`,
  "Apple silicon · macOS 14+" underneath, **All releases** → `https://github.com/omerhakanbilici/karar/releases`.
- Footer: Apache-2.0, "Built on Ollaya (Apache-2.0). Not affiliated with the Ollaya project.",
  links to the repo and to ollaya.dev. "Ollaya" only descriptively.
- Main screenshot: Advanced off, sidebar shown, no » (`docs/screenshots/main-{light,dark}.png`
  are that state today).
- `pages.yml`: push to `main` touching `site/**` (plus `docs/screenshots/**` and itself) and
  `workflow_dispatch`; permissions `pages: write`, `id-token: write`.
- The user sets Settings → Pages → Source = GitHub Actions (ask when the workflow is ready).
- The user takes the "“Karar.app” Not Opened" screenshot: `docs/screenshots/not-opened.png`.
- Git email stays `906295+omerhakanbilici@users.noreply.github.com`. No force-push.

## Files

- Create: `site/index.html`, `site/style.css`, `site/icon.png`, `site/screenshots` (symlink),
  `.github/workflows/pages.yml`
- Add (from the user): `docs/screenshots/not-opened.png`
- Modify: `README.md` (dialog image in Install step 2), roadmap (tick, notes, Phase 8 refresh step)

---

### Task 1: The page

- [ ] **Step 1:** `ln -s ../docs/screenshots site/screenshots`; export the icon:
  `"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Karar/AppIcon.icon --export-image --output-file site/icon.png --platform macOS --rendition Default --width 256 --height 256 --scale 2`
  (check the flags with `ictool --help`).
- [ ] **Step 2:** `site/index.html`, top to bottom: icon + "Karar" + tagline + intro paragraph
  (README wording); Download button + "Apple silicon · macOS 14+" + All releases; `<picture>` with
  `screenshots/main-dark.png` for `(prefers-color-scheme: dark)` and `main-light.png` as `<img>`
  (`width="1100" height="700"`, the 2× images shown at 1×); "What Karar adds" list (README's);
  "First launch" as an `<ol>`: 1 open the DMG, drag Karar to Applications; 2 open Karar, macOS says
  "“Karar.app” Not Opened", click Done (+ `not-opened.png`); 3 System Settings → Privacy & Security
  → Open Anyway, confirm (+ `open-anyway.png`); footer per constraints. `<meta name="viewport">`,
  `<meta name="color-scheme" content="light dark">`, `<link rel="icon" href="icon.png">`.
- [ ] **Step 3:** `site/style.css`: `color-scheme: light dark`, `system-ui` font, CSS system colours
  (`Canvas`, `CanvasText`) plus Apple system blue for the button and links (`#007aff` light,
  `#0a84ff` dark), one centred column (`max-width` ~1100 px for the screenshot, ~680 px for text),
  `img { max-width: 100%; height: auto }`, Gatekeeper images at their natural width capped at
  ~460 px, one `@media (max-width: 600px)` block for smaller headings.
- [ ] **Step 4: Check locally:** serve `site/` (`python3 -m http.server -d site 8765`) and take
  headless Chrome screenshots at 1280 and 390 px wide, light and dark
  (`--force-dark-mode` / emulated media); every image loads (symlink works), no horizontal scroll
  at 390 px, button readable in both themes.
- [ ] **Step 5: Commit** "Add the website".

### Task 2: Deploy

- [ ] **Step 1:** `.github/workflows/pages.yml`:

```yaml
name: Pages

on:
  push:
    branches: [main]
    paths: ["site/**", "docs/screenshots/**", ".github/workflows/pages.yml"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v5
      # site/screenshots is a symlink to docs/screenshots; the artifact step dereferences it.
      - uses: actions/upload-pages-artifact@v5
        with:
          path: site
      - id: deployment
        uses: actions/deploy-pages@v5
```

- [ ] **Step 2:** README Install step 2 gets `docs/screenshots/not-opened.png`. Commit.
- [ ] **Step 3:** Ask the user to set Settings → Pages → Source = GitHub Actions; confirm with
  `gh api repos/omerhakanbilici/karar/pages --jq .build_type` (= `workflow`).
- [ ] **Step 4:** `git log --format='%ae %ce' origin/main..HEAD | sort -u` shows only the noreply
  address; `git push origin HEAD:main` (fast-forward, never force); watch the run with
  `gh run watch`.
- [ ] **Step 5: Acceptance:** `curl -sI https://omerhakanbilici.github.io/karar/` → 200;
  `curl -sI …/karar/screenshots/main-dark.png` → 200 (symlink made it into the artifact);
  `curl -sIL` on the Download href ends in 200 with the DMG's size; screenshots of the live site in
  light and dark, desktop and phone width, shown to the user.
- [ ] **Step 6:** Roadmap: tick Phase 7, notes, and in Phase 8's acceptance "refresh screenshots"
  = overwrite `docs/screenshots/*.png` (same names, same state: Advanced off, sidebar shown for
  `main-*`), push; README and site both update. Commit, push.
