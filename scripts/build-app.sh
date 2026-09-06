#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/dist/PDF Builder.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_SOURCE="$PROJECT_ROOT/Resources/AppIcon.png"
ICONSET="$PROJECT_ROOT/.build/AppIcon.iconset"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CODESIGN_FLAGS="${CODESIGN_FLAGS:---options runtime}"
source "$PROJECT_ROOT/scripts/swift-env.sh"

swift build \
    --package-path "$PROJECT_ROOT" \
    --configuration release \
    --product PDFBuilder \
    --disable-sandbox \
    --cache-path "$PROJECT_ROOT/.build/swiftpm-cache"

case "$APP_BUNDLE" in
    "$PROJECT_ROOT"/dist/*.app) ;;
    *) echo "Unexpected app path: $APP_BUNDLE" >&2; exit 1 ;;
esac

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 755 "$PROJECT_ROOT/.build/release/PDFBuilder" "$CONTENTS/MacOS/PDFBuilder"
install -m 644 "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$CONTENTS/Info.plist"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
swift "$PROJECT_ROOT/scripts/create-icns.swift" \
    "$ICONSET" \
    "$CONTENTS/Resources/AppIcon.icns"

read -r -a SIGN_FLAGS <<< "$CODESIGN_FLAGS"
codesign --force "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
echo "$APP_BUNDLE"
