#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/build-universal"

cmake_args=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
)

if [[ -n "${JUCE_SOURCE_DIR:-}" ]]; then
    if [[ ! -f "$JUCE_SOURCE_DIR/CMakeLists.txt" ]]; then
        print -u2 "JUCE_SOURCE_DIR does not contain a JUCE source checkout."
        exit 1
    fi
    cmake_args+=("-DFETCHCONTENT_SOURCE_DIR_JUCE=$JUCE_SOURCE_DIR")
fi

cmake -S "$ROOT" -B "$BUILD_DIR" "${cmake_args[@]}"
cmake --build "$BUILD_DIR" --config Release --parallel "${BUILD_JOBS:-4}"

PLUGIN="$BUILD_DIR/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3"
/usr/bin/xattr -cr "$PLUGIN"
/usr/bin/codesign --force --deep --sign - "$PLUGIN"
/usr/bin/xattr -cr "$PLUGIN"
codesign --verify --deep --strict --verbose=2 "$PLUGIN"
ctest --test-dir "$BUILD_DIR" --output-on-failure --timeout 45
print "$PLUGIN"
