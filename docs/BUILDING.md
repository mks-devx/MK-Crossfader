# Building

## macOS Requirements

- macOS with Xcode command-line tools
- Swift 6 toolchain for the app
- CMake 3.22 or later for the VST3
- Git and internet access for the default JUCE download

The VST3 build pins JUCE 8.0.15. Set `JUCE_SOURCE_DIR` to a compatible local
checkout if the dependency should not be downloaded. Without that variable,
the build explicitly clears any cached local-source override.

## Windows VST3 Requirements

- Windows 11 x64
- Visual Studio 2022 with Desktop development with C++
- CMake 3.22 or later
- PowerShell and Git

## Verify Both macOS Products

From the repository root:

```zsh
./scripts/verify-all.sh
```

This runs the Swift tests, builds the universal app and VST3, signs both
products ad hoc, and runs the VST3 project tests. It does not install anything.
Close all audio hosts first: the VST3 integration tests use the real link
transport and must not run alongside a live Crossfader session.

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

## Combined Installer

The package contains the app, VST3, licence,
third-party notices, a setup index, and the installation, Maschine and Ableton
guides. The build performs a release privacy audit and writes a SHA-256 checksum
next to the package.

To validate uncommitted local changes without signing or notarisation:

```zsh
./scripts/build-installer.sh --local-test
```

This explicit mode refuses Developer ID identities and notarisation credentials.
It creates `dist/MK-Crossfader-0.3.0-local-test.pkg`. Normal release builds require
a clean checkout, both Developer ID identities, and a notarisation profile;
missing configuration stops the build instead of producing a partial release.
Source privacy preflight
runs before compilation/signing. `APP_BUILD_DIR`, `VST3_BUILD_DIR`, and `DIST_DIR`
can place local build products outside the normal output folders.

Run the preflight and its regression tests separately:

```zsh
./scripts/audit-release.sh --source-only
bash scripts/tests/privacy-preflight.sh
ruby scripts/tests/ci-policy.rb
python3 scripts/tests/installer-preflight.py
```

A distributable build requires both signing identities and notarisation:

```zsh
APP_SIGNING_IDENTITY="Developer ID Application: ..." \
INSTALLER_SIGNING_IDENTITY="Developer ID Installer: ..." \
NOTARY_PROFILE="private-keychain-profile" \
./scripts/build-installer.sh
```

With all three values supplied, the script requires Apple to accept the
submission, staples the notarisation ticket, validates the package with
Gatekeeper, audits the final payload, and then writes its checksum. Keep these
values in a private environment outside the repository.

## macOS VST3 Only

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
processes, ownership/handover races, and loading in a JUCE VST3 host. The 0.3.0
transport uses a new internal protocol; all linked instances must use the same
version. Close every host before upgrading. Saved plug-in state is unchanged.

## Windows VST3 Preview

Push and pull-request CI builds and tests the plug-in without packaging or
uploading downloadable artifacts. A passing CI run is not a preview release.
Binary distribution requires a separate review of the exact package contents,
privacy checks, checksum, and explicit publication approval.

```powershell
./vst3/scripts/build-windows.ps1
```

Output:

`vst3/build-windows/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3`

The Windows build runs the same DSP, saved-state, editor, cross-process, and
host-loading tests. It remains a community preview until it has also been
validated in supported Windows DAWs on physical Windows systems. See
[Windows VST3 Community Preview](WINDOWS_PREVIEW.md).

## macOS Signing

Local builds use an ad-hoc signature so they can be tested on the machine that
built them. Ad-hoc signing is not a substitute for Developer ID signing and
Apple notarisation. Follow the [release checklist](RELEASE_CHECKLIST.md) before
publishing binary downloads.
