# Settings Overlay Panel — Design Spec

Date: 2026-07-03
Status: approved, implementing
Vault direction note: `WorkShop/Ainkrad/07 Design Concepts/Settings Overlay Panel — Direction.md`

## Goal

Settings stops being a tiled Block and becomes the third **summonable overlay
panel** (Launcher / Workspace Overview family), with a two-level settings tree:
Ainkrad-level (Appearance, App Icon) and per-app full control (Terminal:
Appearance + Behavior). All controls persist immediately and, where they affect
running UI, apply live.

## Decisions (approved)

1. **Summon:** `⌘,` opens the overlay; the ⌘K Launcher keeps a dedicated
   "Settings" action row that opens the same overlay. Settings is removed from
   the tile system.
2. **Navigation:** left grouped sidebar (AINKRAD / BUILT-IN APPS) + detail pane.
3. **Terminal depth:** full — Appearance (color scheme + font) and Behavior.
4. **App Icon:** picker decoupled from theme, with **Auto** = follow theme.
   Scoped to shipped assets: **Auto · Blue · Purple** (the two light-background
   icons remain future per the brand doc).

## Architecture

### Overlay & summon
- Remove `SettingsApp` from the registry app list (`AppEnvironment.bootstrap`).
- `AppEnvironment` gains `var isSettingsPresented = false`.
- `KeyboardShortcutMonitor`: `⌘,` toggles `isSettingsPresented` (closes the
  other overlays first, like the existing mutually-exclusive overlay handling).
- `LauncherStore` / `LauncherView`: a dedicated "Settings" system action row
  (not an app) that sets `isSettingsPresented = true` and dismisses the
  launcher.
- `RootView`: include `isSettingsPresented` in `isOverlayPresented` (blur), and
  render `SettingsOverlayView` with the same transition as the other overlays.

### SettingsOverlayView (new)
- Scrim (tap to dismiss) + centered panel; Esc dismisses; panel formula from
  the HUD component language (near-opaque background, accent-gradient stroke,
  glow + shadow).
- Panel layout: header (`ChevronMark` + "SETTINGS") · energy seam ·
  `HStack { sidebar; detail }`.
- **Sidebar:** grouped list — AINKRAD (Appearance, App Icon) and BUILT-IN APPS
  (Terminal). Selected row wears targeting brackets / accent treatment.
- **Detail:** switches on the selected section id.
- Reuses `SettingsSectionHeader`, the theme cards, and `NeonToggle` already
  built for the in-Block Settings.

### Ainkrad settings
- **Appearance:** existing theme cards (theme picker), moved into the overlay.
- **App Icon:** `GlobalSettings` gains `appIcon: AppIconChoice`
  (`auto | blue | purple`). Dock-icon resolution moves to a single resolver:
  choice `.auto` → follow current theme; otherwise the chosen variant.
  `ThemeManager.setTheme` only changes the Dock icon when the choice is `.auto`;
  a new `setAppIcon(_:)` applies + persists an explicit choice. The picker is a
  small grid (Auto / Blue / Purple) with the active one bracketed.

### Terminal settings
- **Behavior:** shell + working directory (existing resolution logic, restyled
  to HUD language). Cursor style included only if SwiftTerm supports it
  (verify during impl; drop if not).
- **Appearance (Phase B):** color scheme + font.
  - `TerminalSettings` extended: `colorScheme: TerminalColorSchemeID`
    (`matchTheme` default + a few named presets), `fontFamily: String?`,
    `fontSize: Double?`, and (if supported) `cursorStyle`.
  - `TerminalColorScheme` provides `background`, `foreground`, `cursor`, and a
    16-color ANSI palette per preset. `matchTheme` derives from the app theme
    (current behavior).
  - **`TerminalSettingsStore` (@Observable, @MainActor)** injected via
    `AppEnvironment`, wrapping load/save of `TerminalSettings`.
    `TerminalContainerView` observes it and re-applies colors + font in
    `updateNSView`, so every running terminal restyles live (same pattern the
    theme already uses via `ThemeManager`). Font applied as
    `view.font = NSFont(name:size:)`; colors via `nativeBackground/Foreground`,
    `caretColor`, and `installColors(_:)` for the ANSI palette.
  - `TerminalSessionFactory` continues to read shell/working-dir from settings;
    appearance is a pure view concern (no session restart needed).

## Persistence
- Immediate-persist everywhere; no Save button, no draft state.
- `GlobalSettings` (key `global-settings`) gains `appIcon`.
- `TerminalSettings` (key `terminal-settings`) gains appearance fields; decoding
  tolerates missing fields (nil → resolution defaults) so existing stored
  settings keep working.

## Testing (TDD)
- Registry no longer lists Settings (`allApps` == `[terminal]`); enabled apps
  unaffected otherwise.
- App-icon resolution: `.auto` follows theme; an explicit choice wins and is NOT
  overridden by a theme change; theme change with `.auto` moves the icon.
- `GlobalSettings` and `TerminalSettings` Codable round-trips including the new
  fields, and decode of an old payload missing the new fields.
- Terminal effective appearance resolution: `matchTheme` yields the theme's
  colors; a preset yields its own; font family/size resolution with nil →
  default.
- View layer (overlay chrome, sidebar, live restyle) verified by launching.

## Phasing
- **Phase A:** overlay shell + sidebar nav; remove Settings-as-Block; `⌘,` +
  Launcher entry; Ainkrad Appearance + App Icon (with decoupled icon
  resolution); Terminal Behavior moved into the overlay.
- **Phase B:** Terminal Appearance — `TerminalSettingsStore` live-apply, font,
  color-scheme presets.

## Non-goals (now)
- The two light-background app icons (future / tied to system appearance).
- Full per-ANSI-color custom editing (presets only).
- Settings for any app other than Terminal.
- Restoring running pane content across relaunch (unchanged; out of scope).
