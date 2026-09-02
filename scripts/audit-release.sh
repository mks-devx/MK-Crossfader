#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
PACKAGE="${1:-}"

if [[ -z "$PACKAGE" || ! -f "$PACKAGE" ]]; then
    print -u2 "Usage: $0 /path/to/MK-Crossfader.pkg"
    exit 2
fi

SOURCE_PATTERN='(/Users/[^/[:space:]]+/|/Volumes/|-----BEGIN [A-Z ]*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,})'

print "== Tracked source privacy scan =="
if git -C "$ROOT" grep -nI -E "$SOURCE_PATTERN" -- . \
    ':(exclude)scripts/audit-release.sh'; then
    print -u2 "Private data was found in tracked source."
    exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mk-crossfader-audit.XXXXXX")"
EXPANDED="$TEMP_ROOT/expanded"
STRINGS_FILE="$TEMP_ROOT/executable-strings.txt"
trap 'rm -rf "$TEMP_ROOT"' EXIT

pkgutil --expand-full "$PACKAGE" "$EXPANDED"

print "== Installer structure =="
if [[ -n "$(find "$EXPANDED" -type d -name Scripts -print -quit)" ]]; then
    print -u2 "Unexpected installer scripts were found."
    exit 1
fi
if rg -n 'system\.run|<scripts|<preinstall|<postinstall' "$EXPANDED"; then
    print -u2 "Unexpected executable installer behaviour was found."
    exit 1
fi

APP="$(find "$EXPANDED" -type d -name 'MK MIDI Crossfader.app' -print -quit)"
PLUGIN="$(find "$EXPANDED" -type d -name 'MK Crossfader.vst3' -print -quit)"
if [[ -z "$APP" || -z "$PLUGIN" ]]; then
    print -u2 "The app or VST3 payload is missing."
    exit 1
fi

APP_BINARY="$APP/Contents/MacOS/MKMIDICrossfader"
PLUGIN_BINARY="$PLUGIN/Contents/MacOS/MK Crossfader"

print "== Bundle validation =="
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --deep --strict --verbose=2 "$PLUGIN"
lipo "$APP_BINARY" -verify_arch arm64 x86_64
lipo "$PLUGIN_BINARY" -verify_arch arm64 x86_64

while IFS= read -r plist; do
    plutil -lint "$plist"
done < <(find "$APP" "$PLUGIN" -type f -name '*.plist' -print)

print "== Executable privacy scan =="
strings -a "$APP_BINARY" > "$STRINGS_FILE"
strings -a "$PLUGIN_BINARY" >> "$STRINGS_FILE"

if rg -n "$SOURCE_PATTERN" "$STRINGS_FILE"; then
    print -u2 "Private data was found in an executable."
    exit 1
fi
print "== Project network-call scan =="
NETWORK_SOURCE_PATTERN='juce::(URL|WebInputStream|StreamingSocket|DatagramSocket|WebBrowserComponent|InterprocessConnection|InterprocessConnectionServer)|URLSession|NSURLConnection|CFNetwork|Network\.framework|::(socket|connect|recv|sendto)[[:space:]]*\('
if rg -n "$NETWORK_SOURCE_PATTERN" \
    "$ROOT/macos-app/Sources" "$ROOT/vst3/src"; then
    print -u2 "Unexpected network API usage was found in project source."
    exit 1
fi
if ! rg -q 'JUCE_WEB_BROWSER=0' "$ROOT/vst3/CMakeLists.txt" \
    || ! rg -q 'JUCE_USE_CURL=0' "$ROOT/vst3/CMakeLists.txt"; then
    print -u2 "The VST3 network feature guards are missing."
    exit 1
fi
if otool -L "$APP_BINARY" "$PLUGIN_BINARY" | rg 'libcurl'; then
    print -u2 "Unexpected cURL linkage was found."
    exit 1
fi

print "== Payload metadata scan =="
UNEXPECTED_XATTRS="$TEMP_ROOT/unexpected-xattrs.txt"
while IFS= read -r -d '' item; do
    while IFS= read -r attribute; do
        if [[ -n "$attribute" && "$attribute" != "com.apple.provenance" ]]; then
            print -r -- "$item: $attribute" >> "$UNEXPECTED_XATTRS"
        fi
    done < <(xattr "$item" 2>/dev/null || true)
done < <(find "$EXPANDED" -print0)
if [[ -s "$UNEXPECTED_XATTRS" ]]; then
    cat "$UNEXPECTED_XATTRS"
    print -u2 "Unexpected extended attributes remain in the installer."
    exit 1
fi
if [[ -n "$(find "$EXPANDED" \
    \( -name '.DS_Store' -o -name '.git' -o -name '*.dSYM' \) \
    -print -quit)" ]]; then
    print -u2 "Development-only metadata was found in the installer."
    exit 1
fi

for bom in "$EXPANDED"/*.pkg/Bom; do
    if lsbom -pf "$bom" | rg '(^|/)\._'; then
        print -u2 "AppleDouble metadata was found in the installer BOM."
        exit 1
    fi
    actual_count="$(lsbom -s "$bom" | wc -l | tr -d '[:space:]')"
    declared_count="$(sed -nE \
        's/.*numberOfFiles=\"([0-9]+)\".*/\1/p' "${bom:h}/PackageInfo")"
    if [[ "$actual_count" != "$declared_count" ]]; then
        print -u2 "Installer BOM and PackageInfo file counts do not match."
        exit 1
    fi
done

find "$EXPANDED" -type f -print0 | xargs -0 strings -a 2>/dev/null \
    | rg -n "$SOURCE_PATTERN" && {
        print -u2 "Private data was found in the installer payload."
        exit 1
    }

print "Release audit passed."
