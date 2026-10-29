#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Jungo.app}"
OUTPUT_ZIP="${2:-$ROOT_DIR/dist/Jungo-macOS.zip}"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Release packaging requires macOS." >&2
  exit 1
fi
if [[ -z "$DEVELOPER_ID" || -z "$NOTARY_PROFILE" ]]; then
  echo "Set DEVELOPER_ID (Developer ID Application identity) and NOTARY_PROFILE (notarytool keychain profile)." >&2
  echo "See docs/DEVELOPMENT.md for setup." >&2
  exit 2
fi

mkdir -p "$(dirname "$APP_PATH")" "$(dirname "$OUTPUT_ZIP")"
SKIP_CODESIGN=1 "$ROOT_DIR/Scripts/build-app.sh" "$APP_PATH"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGING_DIR="$(mktemp -d -t jungo-notary)"
STAGING_ZIP="$STAGING_DIR/Jungo-notary.zip"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$STAGING_ZIP"
xcrun notarytool submit "$STAGING_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_ZIP"
echo "Notarized release archive: $OUTPUT_ZIP"
