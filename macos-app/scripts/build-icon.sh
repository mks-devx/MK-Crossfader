#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="$ROOT_DIR/packaging/Resources/MKCrossfaderLogo.png"
OUTPUT="$ROOT_DIR/packaging/Resources/MKCrossfader.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mk-crossfader-icon.XXXXXX")"
ICONSET="$WORK_DIR/MKCrossfader.iconset"

trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$ICONSET"

make_icon() {
    local size="$1"
    local output="$2"
    /usr/bin/sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$output" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
print "$OUTPUT"
