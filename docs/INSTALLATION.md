# Installation

Official signed and notarised downloads are not available yet. The current
installation path is to build from source.

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
