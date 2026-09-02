#!/bin/zsh

set -euo pipefail

export COPYFILE_DISABLE=1

ROOT="${0:A:h:h}"
DIST_DIR="$ROOT/dist"
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw \
    -o - "$ROOT/macos-app/packaging/Info.plist")"
PLUGIN_VERSION="$(awk '/project\(MK_Crossfader VERSION/ { print $3 }' \
    "$ROOT/vst3/CMakeLists.txt")"
VERSION="${RELEASE_VERSION:-$APP_VERSION}"

if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]]; then
    print -u2 "The installer must be built from a clean Git checkout."
    exit 1
fi

if [[ "$APP_VERSION" != "$PLUGIN_VERSION" || "$VERSION" != "$APP_VERSION" ]]; then
    print -u2 "App, VST3, and installer versions must match."
    print -u2 "App: $APP_VERSION  VST3: $PLUGIN_VERSION  Installer: $VERSION"
    exit 1
fi

for tool in awk codesign cpio ditto git gzip lipo lsbom mkbom pkgbuild \
    pkgutil plutil productbuild shasum xattr; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print -u2 "Required tool not found: $tool"
        exit 1
    fi
done

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    CLEAN_BUILD=1 "$ROOT/scripts/verify-all.sh"
fi

APP="$ROOT/macos-app/build/MK MIDI Crossfader.app"
PLUGIN="$ROOT/vst3/build-universal/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3"
APP_BINARY="$APP/Contents/MacOS/MKMIDICrossfader"
PLUGIN_BINARY="$PLUGIN/Contents/MacOS/MK Crossfader"

if [[ ! -d "$APP" || ! -d "$PLUGIN" ]]; then
    print -u2 "Build products are missing. Run without SKIP_BUILD=1."
    exit 1
fi

lipo "$APP_BINARY" -verify_arch arm64 x86_64
lipo "$PLUGIN_BINARY" -verify_arch arm64 x86_64

APP_SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:-}"
INSTALLER_SIGNING_IDENTITY="${INSTALLER_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$APP_SIGNING_IDENTITY" || -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
    if [[ -z "$APP_SIGNING_IDENTITY" || -z "$INSTALLER_SIGNING_IDENTITY" ]]; then
        print -u2 "Both signing identities are required for a distributable installer."
        exit 1
    fi
    codesign --force --deep --options runtime --timestamp \
        --sign "$APP_SIGNING_IDENTITY" "$APP"
    codesign --force --deep --options runtime --timestamp \
        --sign "$APP_SIGNING_IDENTITY" "$PLUGIN"
fi
if [[ -n "$NOTARY_PROFILE" && -z "$INSTALLER_SIGNING_IDENTITY" ]]; then
    print -u2 "Notarisation requires Developer ID signed app, VST3, and installer."
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --deep --strict --verbose=2 "$PLUGIN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mk-crossfader-installer.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

APP_ROOT="$WORK/app-root"
PLUGIN_ROOT="$WORK/vst3-root"
DOCS_ROOT="$WORK/documents-root"
COMPONENTS="$WORK/components"
RESOURCES="$WORK/resources"
mkdir -p "$APP_ROOT/Applications"
mkdir -p "$PLUGIN_ROOT/Library/Audio/Plug-Ins/VST3"
mkdir -p "$DOCS_ROOT/Library/Application Support/MK Crossfader"
mkdir -p "$COMPONENTS" "$RESOURCES" "$DIST_DIR"

ditto "$APP" "$APP_ROOT/Applications/MK MIDI Crossfader.app"
ditto "$PLUGIN" "$PLUGIN_ROOT/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3"
cp "$ROOT/LICENSE" "$DOCS_ROOT/Library/Application Support/MK Crossfader/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" \
    "$DOCS_ROOT/Library/Application Support/MK Crossfader/THIRD_PARTY_NOTICES.md"
cp "$ROOT/docs/INSTALLATION.md" \
    "$DOCS_ROOT/Library/Application Support/MK Crossfader/INSTALLATION.md"

cp "$ROOT/installer/resources/"*.html "$RESOURCES/"
cp "$ROOT/LICENSE" "$RESOURCES/LICENSE.txt"
sed "s/@VERSION@/$VERSION/g" "$ROOT/installer/Distribution.xml.in" \
    > "$WORK/Distribution.xml"

xattr -cr "$APP_ROOT" "$PLUGIN_ROOT" "$DOCS_ROOT" "$RESOURCES"
chmod -R u+rwX,go+rX,go-w "$APP_ROOT" "$PLUGIN_ROOT" "$DOCS_ROOT" "$RESOURCES"

pkgbuild --root "$APP_ROOT" \
    --identifier com.mk-tools.crossfader.app \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENTS/MKCrossfaderApp.pkg"
pkgbuild --root "$PLUGIN_ROOT" \
    --identifier com.mk-tools.crossfader.vst3 \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENTS/MKCrossfaderVST3.pkg"
pkgbuild --root "$DOCS_ROOT" \
    --identifier com.mk-tools.crossfader.documents \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENTS/MKCrossfaderDocuments.pkg"

clean_component_payload() {
    local package="$1"
    local payload_root="$2"
    local name="${package:t:r}"
    local expanded="$WORK/$name-expanded"
    local cleaned="$WORK/$name-clean.pkg"
    local bom_list="$WORK/$name.bom-list"
    local package_info="$expanded/PackageInfo"
    local file_count

    pkgutil --expand "$package" "$expanded"
    lsbom "$expanded/Bom" \
        | awk -F '\t' '$1 !~ /(^|\/)\._/' > "$bom_list"
    mkbom -i "$bom_list" "$expanded/Bom"

    (
        cd "$payload_root"
        find . -print | LC_ALL=C sort \
            | cpio -o --format odc -R root:wheel \
            | gzip -9n > "$expanded/Payload"
    )

    file_count="$(wc -l < "$bom_list" | tr -d '[:space:]')"
    sed -E "s/numberOfFiles=\"[0-9]+\"/numberOfFiles=\"$file_count\"/" \
        "$package_info" > "$WORK/$name.PackageInfo"
    mv "$WORK/$name.PackageInfo" "$package_info"

    pkgutil --flatten "$expanded" "$cleaned"
    mv "$cleaned" "$package"
}

clean_component_payload "$COMPONENTS/MKCrossfaderApp.pkg" "$APP_ROOT"
clean_component_payload "$COMPONENTS/MKCrossfaderVST3.pkg" "$PLUGIN_ROOT"
clean_component_payload "$COMPONENTS/MKCrossfaderDocuments.pkg" "$DOCS_ROOT"

UNSIGNED_PACKAGE="$WORK/MK-Crossfader-$VERSION.pkg"
productbuild --distribution "$WORK/Distribution.xml" \
    --resources "$RESOURCES" \
    --package-path "$COMPONENTS" \
    "$UNSIGNED_PACKAGE"

if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
    OUTPUT_NAME="MK-Crossfader-$VERSION.pkg"
    productsign --sign "$INSTALLER_SIGNING_IDENTITY" \
        "$UNSIGNED_PACKAGE" "$DIST_DIR/$OUTPUT_NAME"
    pkgutil --check-signature "$DIST_DIR/$OUTPUT_NAME"
else
    OUTPUT_NAME="MK-Crossfader-$VERSION-local-test.pkg"
    cp "$UNSIGNED_PACKAGE" "$DIST_DIR/$OUTPUT_NAME"
    print "No Developer ID identities supplied; created a local-test installer."
fi

xattr -c "$DIST_DIR/$OUTPUT_NAME" 2>/dev/null || true

if [[ -n "$NOTARY_PROFILE" ]]; then
    for tool in spctl xcrun; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            print -u2 "Required notarisation tool not found: $tool"
            exit 1
        fi
    done

    NOTARY_RESULT="$DIST_DIR/MK-Crossfader-$VERSION-notary-result.json"
    xcrun notarytool submit "$DIST_DIR/$OUTPUT_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$NOTARY_RESULT"
    NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        print -u2 "Apple notarisation did not accept the installer: $NOTARY_STATUS"
        exit 1
    fi

    xcrun stapler staple "$DIST_DIR/$OUTPUT_NAME"
    xcrun stapler validate "$DIST_DIR/$OUTPUT_NAME"
    spctl --assess --type install --verbose=2 "$DIST_DIR/$OUTPUT_NAME"
elif [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
    print -u2 "The installer is signed but not notarised because NOTARY_PROFILE is empty."
fi

"$ROOT/scripts/audit-release.sh" "$DIST_DIR/$OUTPUT_NAME"

(
    cd "$DIST_DIR"
    shasum -a 256 "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)

print "$DIST_DIR/$OUTPUT_NAME"
print "$DIST_DIR/$OUTPUT_NAME.sha256"
if [[ -n "$NOTARY_PROFILE" ]]; then
    print "$NOTARY_RESULT"
fi
