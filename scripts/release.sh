#!/usr/bin/env bash
#
# Ainkrad release builder.
#
# Builds a Release Ainkrad.app, packages it as a .dmg, and — when Developer ID
# signing credentials are present — code-signs (hardened runtime), notarizes,
# and staples it so it opens without the Gatekeeper warning. Degrades
# gracefully: with no cert it still produces an installable (unsigned) .dmg.
#
# The same script runs locally and in CI (.github/workflows/release.yml just
# sets the env vars below from repo secrets and calls this with --publish).
#
# Usage:
#   scripts/release.sh                 # build (+sign/notarize if configured)
#   scripts/release.sh --publish       # also create/update the GitHub release
#   VERSION=0.2.0 scripts/release.sh   # override the version (default: project.yml)
#
# Signing / notarization (all optional — omit to build unsigned):
#   SIGN_IDENTITY      "Developer ID Application: Name (TEAMID)" — the codesign identity.
#   NOTARY_PROFILE     Name of a stored `notarytool store-credentials` profile.
#     …or, instead of a profile:
#   APPLE_ID           Apple ID email used for notarization.
#   APPLE_TEAM_ID      10-char Apple Developer Team ID.
#   APPLE_APP_PASSWORD App-specific password (appleid.apple.com → Sign-In & Security).
#
# Toolchain:
#   DEVELOPER_DIR      Overrides the Xcode used. Defaults to Xcode-beta if present
#                      (this project currently needs the macOS 27 beta SDK).
#
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

# --- toolchain -------------------------------------------------------------
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

# --- version ---------------------------------------------------------------
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
fi
if [[ -z "${VERSION:-}" ]]; then
  echo "error: could not determine VERSION (set MARKETING_VERSION in project.yml or pass VERSION=)" >&2
  exit 1
fi
TAG="v${VERSION}"
DIST="${REPO_ROOT}/dist"
BUILD="${DIST}/build"
APP_PATH="${BUILD}/Build/Products/Release/Ainkrad.app"
DMG="${DIST}/Ainkrad-${VERSION}.dmg"

echo "▸ Ainkrad ${VERSION} (${TAG})"
echo "  Xcode: ${DEVELOPER_DIR:-$(xcode-select -p)}"

# --- build -----------------------------------------------------------------
command -v xcodegen >/dev/null 2>&1 && { echo "▸ xcodegen generate"; xcodegen generate >/dev/null; }

rm -rf "$DIST"; mkdir -p "$DIST"
echo "▸ Building Release…"
xcodebuild -scheme Ainkrad -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD" build >/dev/null
[[ -d "$APP_PATH" ]] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || echo "  warning: built version ${BUILT_VERSION} != ${VERSION}"

# --- sign ------------------------------------------------------------------
SIGNED=false
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signing with: ${SIGN_IDENTITY}"
  # Inside-out: sign every nested dylib/framework first, then the app bundle,
  # each with the hardened runtime + a secure timestamp (both required for
  # notarization). --deep is intentionally avoided (Apple discourages it).
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" \( -name '*.dylib' -o -name '*.framework' \) -print0 2>/dev/null)
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"
  SIGNED=true
else
  echo "▸ No SIGN_IDENTITY — building UNSIGNED (users right-click → Open on first launch)."
fi

# --- package dmg -----------------------------------------------------------
echo "▸ Packaging ${DMG##*/}…"
STAGE="${DIST}/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Ainkrad ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# --- notarize + staple -----------------------------------------------------
NOTARIZED=false
if [[ "$SIGNED" == true ]]; then
  NOTARY_ARGS=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi
  if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    echo "▸ Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    echo "▸ Stapling ticket…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    NOTARIZED=true
  else
    echo "▸ Signed but no notary credentials — skipping notarization."
  fi
fi

echo "✓ Built: ${DMG}"
$SIGNED     && echo "  signed:     yes" || echo "  signed:     NO (unsigned)"
$NOTARIZED  && echo "  notarized:  yes" || echo "  notarized:  no"

# --- publish ---------------------------------------------------------------
if [[ "$PUBLISH" == true ]]; then
  command -v gh >/dev/null 2>&1 || { echo "error: --publish needs the gh CLI" >&2; exit 1; }
  ASSET="${DMG}#Ainkrad ${VERSION} (Apple Silicon).dmg"
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "▸ Release ${TAG} exists — uploading asset (clobber)…"
    gh release upload "$TAG" "$ASSET" --clobber
  else
    echo "▸ Creating release ${TAG}…"
    gh release create "$TAG" "$ASSET" \
      --title "Ainkrad ${VERSION}" \
      --generate-notes
  fi
  echo "✓ Published ${TAG}"
fi
