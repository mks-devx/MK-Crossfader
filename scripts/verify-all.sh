#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"

print "== MK MIDI Crossfader =="
swift test --package-path "$ROOT/macos-app"
"$ROOT/macos-app/scripts/build-app.sh"

print "== MK Crossfader VST3 =="
"$ROOT/vst3/scripts/build.sh"

print "Both current products built and passed their project test suites."
