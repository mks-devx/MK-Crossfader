#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
PACKAGE="${1:-}"

if [[ "$PACKAGE" != "--source-only" && ( -z "$PACKAGE" || ! -f "$PACKAGE" ) ]]; then
    print -u2 "Usage: $0 --source-only | /path/to/MK-Crossfader.pkg"
    exit 2
fi

SOURCE_PATTERN='([/]Users/[A-Za-z0-9._-]+/|[/]Volumes/|-----BEGIN [A-Z ]*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+|sk-(proj-)?[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,})'

print "== Source privacy scan =="
if git -C "$ROOT" grep --untracked --exclude-standard -lI -E "$SOURCE_PATTERN" -- .; then
    print -u2 "Private data was found in source."
    exit 1
else
    scan_status=$?
    if (( scan_status != 1 )); then
        print -u2 "Source privacy scan could not complete."
        exit "$scan_status"
    fi
fi

while IFS= read -r -d '' file; do
    [[ -e "$ROOT/$file" ]] || continue
    if print -r -- "$file" | grep -Eq '(^|/)(\.env($|\.)|id_(rsa|ed25519)($|\.)|[^/]+\.(pem|p12|pfx|key|mobileprovision)$|credentials?($|\.)|secrets?($|\.))'; then
        print -u2 "A sensitive filename is included in the source file set."
        exit 1
    fi
done < <(git -C "$ROOT" ls-files --cached --others --exclude-standard -z)

if [[ "$PACKAGE" == "--source-only" ]]; then
    print "Source privacy scan passed."
    exit 0
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mk-crossfader-audit.XXXXXX")"
EXPANDED="$TEMP_ROOT/expanded"
trap 'rm -rf "$TEMP_ROOT"' EXIT

# Keep matched values out of build logs, including when a release fails.
private_data_found() {
    local scan_status
    if rg -a -o --no-filename "$SOURCE_PATTERN" "$@" > "$TEMP_ROOT/private-matches"; then
        grep -v '^[/]Users/Shared/$' "$TEMP_ROOT/private-matches" > /dev/null
    else
        scan_status=$?
        if (( scan_status != 1 )); then
            print -u2 "Executable or payload privacy scan could not complete."
            exit "$scan_status"
        fi
        return 1
    fi
}

pkgutil --expand-full "$PACKAGE" "$EXPANDED"

print "== Archive container metadata =="
python3 "$ROOT/scripts/audit-installer-container.py" "$PACKAGE"

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

print "== Installed setup guides =="
DOCS="$EXPANDED/MKCrossfaderDocuments.pkg/Payload/Library/Application Support/MK Crossfader"
for guide in START_HERE INSTALLATION MASCHINE_SETUP ABLETON_SETUP; do
    if [[ ! -s "$DOCS/$guide.md" ]]; then
        print -u2 "Missing installed setup guide: $guide.md"
        exit 1
    fi
done
while IFS= read -r -d '' document; do
    case "${document:t}" in
        START_HERE.md|INSTALLATION.md|MASCHINE_SETUP.md|ABLETON_SETUP.md|LICENSE.txt|THIRD_PARTY_NOTICES.md) ;;
        *) print -u2 "An unexpected file was found in the installed documentation."; exit 1 ;;
    esac
done < <(find "$DOCS" -type f -print0)
while IFS= read -r link; do
    link="${link#\]\(}"
    link="${link%\)}"
    [[ "$link" == *:* || "$link" == \#* ]] && continue
    link="${link%%\#*}"
    if [[ ! -e "$DOCS/$link" ]]; then
        print -u2 "Broken installed documentation link: $link"
        exit 1
    fi
done < <(rg --no-filename -o '\]\([^)]*\)' "$DOCS" --glob '*.md')

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
if private_data_found "$APP_BINARY" "$PLUGIN_BINARY"; then
    print -u2 "Private data was found in an executable."
    exit 1
fi
print "== Project network-call scan =="
NETWORK_SOURCE_PATTERN='juce::(URL|WebInputStream|StreamingSocket|DatagramSocket|WebBrowserComponent|InterprocessConnection|InterprocessConnectionServer)|URLSession|NSURLConnection|CFNetwork|Network\.framework|::(socket|connect|recv|sendto)[[:space:]]*\('
if rg -n "$NETWORK_SOURCE_PATTERN" "$ROOT/vst3/src"; then
    print -u2 "Unexpected network API usage was found in the VST3 source."
    exit 1
fi
if rg -n "$NETWORK_SOURCE_PATTERN" "$ROOT/macos-app/Sources" \
    --glob '!AppUpdateChecker.swift'; then
    print -u2 "Unexpected network API usage was found in project source."
    exit 1
fi
UPDATE_CHECKER="$ROOT/macos-app/Sources/MKMIDICrossfader/AppUpdateChecker.swift"
EXPECTED_APP_NETWORK_URLS=$'https://api.github.com/repos/mks-devx/MK-Crossfader/releases/latest\nhttps://github.com/mks-devx/MK-Crossfader/releases'
ACTUAL_APP_NETWORK_URLS="$(rg -o 'https?://[^\"]+' "$UPDATE_CHECKER" \
    | LC_ALL=C sort -u)"
if [[ "$ACTUAL_APP_NETWORK_URLS" != "$EXPECTED_APP_NETWORK_URLS" ]]; then
    print -u2 "The manual update checker is not limited to the expected GitHub endpoints."
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

if private_data_found "$EXPANDED"; then
    print -u2 "Private data was found in the installer payload."
    exit 1
fi

print "Release audit passed."
