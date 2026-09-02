# Building

## Requirements

- macOS with Xcode command-line tools
- Swift 6 toolchain for the app
- CMake 3.22 or later for the VST3
- Git and internet access for the default JUCE download

The VST3 build pins JUCE 8.0.15. Set `JUCE_SOURCE_DIR` to a compatible local
checkout if the dependency should not be downloaded.

## Verify Both Products

From the repository root:

```zsh
./scripts/verify-all.sh
```

This runs the Swift tests, builds the app, builds the universal VST3, signs both
products ad hoc, and runs the VST3 project tests. It does not install anything.

## App Only

```zsh
swift test --package-path macos-app
./macos-app/scripts/build-app.sh
```

Outputs:

- `macos-app/build/MK MIDI Crossfader.app`
- `macos-app/build/MK MIDI Crossfader.app.zip`

The checked-in icon is used for normal builds. Icon regeneration is a separate
maintainer action:

```zsh
./macos-app/scripts/build-icon.sh
```

## VST3 Only

```zsh
./vst3/scripts/build.sh
```

Output:

`vst3/build-universal/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3`

To use an existing JUCE checkout:

```zsh
JUCE_SOURCE_DIR=/path/to/JUCE ./vst3/scripts/build.sh
```

The VST3 test suite covers DSP and saved state, communication across separate
processes, and loading in a JUCE VST3 host.

## Signing

Local builds use an ad-hoc signature so they can be tested on the machine that
built them. Ad-hoc signing is not a substitute for Developer ID signing and
Apple notarisation. Follow the [release checklist](RELEASE_CHECKLIST.md) before
publishing binary downloads.
