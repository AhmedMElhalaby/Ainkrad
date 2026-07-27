# Ainkrad (macOS app) — OpenCode guide

Native macOS SwiftUI app: an "Agentic OS" workspace for software engineers. The home screen
is a desktop-like OS surface (floating islands, window management), NOT a web-style app.
Ships as `.dmg` via GitHub releases. (Distinct from the Ainkrad Obsidian *vault* at
`/Users/ahmedmelhalaby/Ainkrad` — that's the knowledge base; this is the product.)

## Load first

- Project dashboard: `/Users/ahmedmelhalaby/Ainkrad/Projects/Ainkrad.md`
- Design docs & milestone plans: `docs/` in this repo and
  `/Users/ahmedmelhalaby/Ainkrad/WorkShop/Ainkrad/` (brand, concepts, milestone plans)
- Build: Xcode project generated from `project.yml` (XcodeGen); see `Makefile` and `scripts/`.
- Related repos: `AinkradAppKit`, `AinkradTerminal`, `AinkradPluginTemplate`, `island-layers`.

## Design language (hard requirements — violations get rejected)

- Looks like an OS, not a web app: seamless surfaces, NO separator lines, title bar unified
  with the window body (same color/opacity), traffic-lights inside the surface.
- Motion is first-class: layered/parallax live composition ("separated live layers, not one
  whole image moving"), hover states everywhere. Built-in apps (e.g. terminal) share the
  window's style.
- Deliver UI changes screen-by-screen with screenshots for approval.
- Before claiming a fix, verify adjacent behavior (animations, focus mode, resize) — fixing A
  while breaking B is the fastest way to lose trust here.

## Ground rules

- Feature branches off `development`; accepted milestone architecture is frozen.
- If two iterations on a visual issue don't converge, stop patching and propose a clean reset
  to a known-good state.
- Docs go to the Ainkrad vault, not this repo (repo `docs/` is for specs/plans only).
- End substantial sessions with `/save-session`.
