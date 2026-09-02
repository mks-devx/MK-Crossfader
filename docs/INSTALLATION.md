# Installation

Official signed and notarised downloads are not available yet. The current
installation path is to build from source.

## Combined Local-Test Installer

Maintainers can create one package containing both products:

```zsh
./scripts/build-installer.sh
```

The unsigned `local-test` package is only for validation on the Mac that built
it. Do not redistribute it or tell users to bypass Gatekeeper. A public package
must be Developer ID signed, notarised, and tested after browser download on a
clean supported Mac.

The combined installer writes only these locations and runs no installation
scripts:

- `/Applications/MK MIDI Crossfader.app`
- `/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3`
- `/Library/Application Support/MK Crossfader`

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

Do not bypass macOS security warnings for binary downloads from an untrusted
source. A future official release must be Developer ID signed, notarised, and
tested after downloading on a clean Mac.

## Uninstall

Close Maschine and other plug-in hosts, then remove the three installed paths
listed above. Removing the app does not delete its local macOS preferences.
