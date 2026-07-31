#!/usr/bin/env bash
#
# Installs a user-provided Sword-Art-Online-style UI sound pack as Ainkrad
# sound OVERRIDES (AIN-108 follow-up), so the app's menu chimes match a
# specific 3rd-party pack the user has locally.
#
# These packs are typically COPYRIGHTED (anime/game audio) and MUST NOT be
# committed to this repo or bundled into public releases. This script only
# ever copies files into the user's own Ainkrad Home — the vault folder the
# app itself resolved (outside the repo, outside git, outside the release
# .dmg) — never into
# `Sources/Ainkrad/Resources/Sounds/` or any other tracked path. SoundEngine
# prefers a same-named override there over the bundled synth wav at
# runtime, and cleanly falls back to the bundled wav when an override is
# absent (see Sources/Ainkrad/Core/Sound/SoundEngine.swift).
#
# Respect the sound pack's copyright/license: keep it local, don't
# redistribute it, don't upload it anywhere this repo's history could pick
# it up.
#
# Usage:
#   scripts/install-sao-sounds.sh <source-folder>   # install overrides
#   scripts/install-sao-sounds.sh --clear           # revert to built-in sounds
#   scripts/install-sao-sounds.sh --help
#
# <source-folder> is expected to contain (at least some of) these files,
# named as in a typical SAO-style UI sound pack:
#   EnterMenu.wav        -> appLaunch.wav
#   ExitMenu.wav         -> appQuit.wav
#   MenuTick.wav         -> overlayOpen.wav
#   BackSound.wav        -> overlayClose.wav
#   ConfirmSound.wav     -> appOpen.wav
#   ExitMenu.wav         -> appClose.wav
#   MenuTick.wav         -> workspaceSwitch.wav
#   ConfirmSound.wav     -> focusMode.wav
#   AchievementSound.wav -> install.wav
#   BackSound.wav        -> uninstall.wav
#   MenuTick.wav         -> toggle.wav
#   ConfirmSound.wav     -> confirm.wav
#   BackSound.wav        -> error.wav
#
# Any mapping whose source file is missing is skipped with a warning — the
# rest still install, and Ainkrad falls back to its built-in synth wav for
# whatever wasn't overridden.

set -euo pipefail

# The sound override directory is `<Ainkrad Home>/Sounds`, and the ONLY
# authority on where the Home is, is the pointer the app writes at
# ~/Library/Application Support/Ainkrad/home.json. Guessing a location here
# would silently install into a directory the app never reads — exactly the
# failure that made this script's old hard-coded path lose people's overrides.
POINTER="$HOME/Library/Application Support/Ainkrad/home.json"

resolve_dest() {
  if [[ ! -f "$POINTER" ]]; then
    cat >&2 <<EOF
error: no Ainkrad Home is configured yet.

  Expected the pointer file at:
    $POINTER

  Launch Ainkrad once so it can create (or let you choose) your Ainkrad Home,
  then run this script again. This script will not guess a location.
EOF
    exit 1
  fi

  # `plutil` ships with macOS and parses JSON — no python/jq assumption.
  local home_path
  if ! home_path="$(plutil -extract path raw -o - -- "$POINTER" 2>/dev/null)"; then
    echo "error: could not read \"path\" from $POINTER (file corrupt?)." >&2
    echo "       Launch Ainkrad once to rewrite it, then retry." >&2
    exit 1
  fi
  if [[ -z "$home_path" ]]; then
    echo "error: $POINTER has an empty \"path\"." >&2
    exit 1
  fi
  if [[ ! -d "$home_path" ]]; then
    echo "error: the configured Ainkrad Home does not exist: $home_path" >&2
    echo "       Launch Ainkrad and reconnect your Home, then retry." >&2
    exit 1
  fi
  DEST="$home_path/Sounds"
}

usage() {
  cat <<'EOF'
Usage:
  install-sao-sounds.sh <source-folder>   Install overrides from <source-folder>
  install-sao-sounds.sh --clear           Remove overrides (revert to built-in sounds)
  install-sao-sounds.sh --help            Show this help

Copies a Sword-Art-Online-style UI sound pack into Ainkrad's sound override
directory, <Ainkrad Home>/Sounds. The Home is read from the app's pointer file
at ~/Library/Application Support/Ainkrad/home.json; if that does not exist yet,
launch Ainkrad once first — this script never guesses a location.
Nothing is ever copied into this git repo or into a release bundle — overrides
live only in the user's own Ainkrad Home, and copyrighted
sound packs must stay local (respect the pack's license; do not redistribute
it, and never add it to this repo).

Filename mapping (source -> Ainkrad event):
  EnterMenu.wav        -> appLaunch.wav
  ExitMenu.wav         -> appQuit.wav
  MenuTick.wav         -> overlayOpen.wav
  BackSound.wav        -> overlayClose.wav
  ConfirmSound.wav     -> appOpen.wav
  ExitMenu.wav         -> appClose.wav
  MenuTick.wav         -> workspaceSwitch.wav
  ConfirmSound.wav     -> focusMode.wav
  AchievementSound.wav -> install.wav
  BackSound.wav        -> uninstall.wav
  MenuTick.wav         -> toggle.wav
  ConfirmSound.wav     -> confirm.wav
  BackSound.wav        -> error.wav
EOF
}

# Ordered as "<source-filename>:<ainkrad-name>" so both bash 3 (macOS's
# default /bin/bash) and bash 4+ can iterate it without associative arrays.
MAPPINGS=(
  "EnterMenu.wav:appLaunch.wav"
  "ExitMenu.wav:appQuit.wav"
  "MenuTick.wav:overlayOpen.wav"
  "BackSound.wav:overlayClose.wav"
  "ConfirmSound.wav:appOpen.wav"
  "ExitMenu.wav:appClose.wav"
  "MenuTick.wav:workspaceSwitch.wav"
  "ConfirmSound.wav:focusMode.wav"
  "AchievementSound.wav:install.wav"
  "BackSound.wav:uninstall.wav"
  "MenuTick.wav:toggle.wav"
  "ConfirmSound.wav:confirm.wav"
  "BackSound.wav:error.wav"
)

clear_overrides() {
  resolve_dest
  local removed=0
  for mapping in "${MAPPINGS[@]}"; do
    local ainkrad_name="${mapping#*:}"
    local target="$DEST/$ainkrad_name"
    if [[ -f "$target" ]]; then
      rm -f "$target"
      echo "removed $ainkrad_name"
      removed=$((removed + 1))
    fi
  done
  echo "cleared $removed override(s) from $DEST"
  echo "Ainkrad will use its built-in synth sounds again."
}

install_overrides() {
  local src="$1"
  if [[ ! -d "$src" ]]; then
    echo "error: source folder not found: $src" >&2
    exit 1
  fi

  resolve_dest

  mkdir -p "$DEST"

  local installed=0 skipped=0
  for mapping in "${MAPPINGS[@]}"; do
    local source_name="${mapping%%:*}"
    local ainkrad_name="${mapping#*:}"
    local source_path="$src/$source_name"
    if [[ -f "$source_path" ]]; then
      cp "$source_path" "$DEST/$ainkrad_name"
      echo "installed $ainkrad_name <- $source_name"
      installed=$((installed + 1))
    else
      echo "warning: skipping $ainkrad_name — source file not found: $source_path" >&2
      skipped=$((skipped + 1))
    fi
  done

  echo "installed $installed override(s), skipped $skipped into:"
  echo "  $DEST"
  echo "Reminder: this pack stays local — it was NOT copied into the Ainkrad repo."
}

case "${1:-}" in
  --help|-h)
    usage
    ;;
  --clear)
    clear_overrides
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    install_overrides "$1"
    ;;
esac
