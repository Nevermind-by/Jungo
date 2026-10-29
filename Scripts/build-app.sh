#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Jungo"
APP_PATH="${1:-$ROOT_DIR/dist/Jungo.app}"
APP_VERSION="${JUNGO_VERSION:-0.1.0}"
BUILD_NUMBER="${JUNGO_BUILD_NUMBER:-1}"
EXECUTABLE="$ROOT_DIR/.build/release/$APP_NAME"
CONTENTS="$APP_PATH/Contents"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Jungo .app packaging requires macOS." >&2
  exit 1
fi

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "JUNGO_VERSION must use MAJOR.MINOR.PATCH format (for example 1.0.0)." >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "JUNGO_BUILD_NUMBER must be a positive integer." >&2
  exit 2
fi

swift build --package-path "$ROOT_DIR" -c release --product "$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Expected executable not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$EXECUTABLE" "$CONTENTS/MacOS/$APP_NAME"
swift "$ROOT_DIR/Scripts/generate-icon.swift" "$CONTENTS/Resources/AppIcon.icns"
chmod 755 "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleExecutable</key>
    <string>Jungo</string>
    <key>CFBundleIdentifier</key>
    <string>com.nevermind.jungo</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Jungo</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Jungo</string>
    <key>CFBundleDisplayName</key>
    <string>Jungo</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ "${SKIP_CODESIGN:-0}" != "1" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "Built app bundle: $APP_PATH"
echo "This is an ad-hoc signed development build, not a notarized release."
