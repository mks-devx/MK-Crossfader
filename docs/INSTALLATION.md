# Installation

Official binary releases are distributed through the
[Releases page](https://github.com/mks-devx/MK-Crossfader/releases). Download
the `.pkg` and matching `.pkg.sha256` file for the current version.

Close Maschine and any other plug-in hosts before installing. To verify a
download in Terminal, run the checksum command from the download folder:

```zsh
shasum -a 256 -c MK-Crossfader-<version>.pkg.sha256
```

Open the package and follow the installer. macOS asks for an administrator
password because the app and VST3 are installed system-wide. Public packages
are Developer ID signed, Apple-notarised, and contain no preinstall or
postinstall scripts.

## Installed Files

- `/Applications/MK MIDI Crossfader.app`
- `/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3`
- `/Library/Application Support/MK Crossfader`

The app and VST3 are independent products. Either can be used by itself; the
VST3 does not require the app to be installed or running, and the app does not
require the VST3.

## Build A Local-Test Installer

Maintainers can create one package containing both products:

```zsh
./scripts/build-installer.sh
```

The unsigned `local-test` package is only for validation on the Mac that built
it. Do not redistribute it or tell users to bypass Gatekeeper. A public package
must be Developer ID signed, notarised, and tested after browser download on a
clean supported Mac.

## MK MIDI Crossfader

After running `./macos-app/scripts/build-app.sh`:

```zsh
ditto "macos-app/build/MK MIDI Crossfader.app" \
  "/Applications/MK MIDI Crossfader.app"
```

Start the app before opening Maschine, then enable its virtual MIDI input.

## MK Crossfader VST3

After running `./vst3/scripts/build.sh`:

```zsh
mkdir -p "$HOME/Library/Audio/Plug-Ins/VST3"
ditto \
  "vst3/build-universal/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3" \
  "$HOME/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3"
```

Restart or rescan the host after installation. If replacing an earlier build,
close all plug-in hosts first and keep a backup of the previous bundle until
existing projects have opened correctly.

Do not bypass macOS security warnings for copies downloaded from unofficial
sources. Verify the checksum and obtain releases only from this repository.

## Uninstall

Close Maschine and other plug-in hosts, then remove the three installed paths
listed above. Removing the app does not delete its local macOS preferences.
