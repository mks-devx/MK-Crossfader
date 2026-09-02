#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="$ROOT_DIR/packaging/Resources/MKCrossfaderLogo.png"
OUTPUT="$ROOT_DIR/packaging/Resources/MKCrossfader.icns"
RENDERER="$ROOT_DIR/scripts/render-icon.swift"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mk-crossfader-icon.XXXXXX")"
ICONSET="$WORK_DIR/MKCrossfader.iconset"
MODULE_CACHE="$ROOT_DIR/.build/icon-module-cache"

trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$ICONSET"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
    /usr/bin/xcrun swift "$RENDERER" \
    1024 "$SOURCE" \
    16 "$ICONSET/icon_16x16.png" \
    32 "$ICONSET/icon_16x16@2x.png" \
    32 "$ICONSET/icon_32x32.png" \
    64 "$ICONSET/icon_32x32@2x.png" \
    128 "$ICONSET/icon_128x128.png" \
    256 "$ICONSET/icon_128x128@2x.png" \
    256 "$ICONSET/icon_256x256.png" \
    512 "$ICONSET/icon_256x256@2x.png" \
    512 "$ICONSET/icon_512x512.png" \
    1024 "$ICONSET/icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
print "$OUTPUT"
