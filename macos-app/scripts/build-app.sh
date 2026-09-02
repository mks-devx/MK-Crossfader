#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="MK MIDI Crossfader"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ARCHIVE="$BUILD_DIR/$APP_NAME.app.zip"
MODULE_CACHE="$ROOT_DIR/.build/module-cache"
ARM_SCRATCH="$ROOT_DIR/.build/release-arm64"
INTEL_SCRATCH="$ROOT_DIR/.build/release-x86_64"

cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
swift build -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM_SCRATCH"
ARM_BIN_DIR="$(swift build -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM_SCRATCH" \
    --show-bin-path)"

swift build -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$INTEL_SCRATCH"
INTEL_BIN_DIR="$(swift build -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$INTEL_SCRATCH" \
    --show-bin-path)"

rm -rf "$APP_DIR"
rm -f "$ARCHIVE"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
lipo -create \
    "$ARM_BIN_DIR/MKMIDICrossfader" \
    "$INTEL_BIN_DIR/MKMIDICrossfader" \
    -output "$APP_DIR/Contents/MacOS/MKMIDICrossfader"
cp "$ROOT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/packaging/Resources/MKCrossfader.icns" "$APP_DIR/Contents/Resources/MKCrossfader.icns"
cp "$ROOT_DIR/packaging/Resources/MKCrossfaderLogo.png" "$APP_DIR/Contents/Resources/MKCrossfaderLogo.png"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE"

print "$APP_DIR"
print "$ARCHIVE"
