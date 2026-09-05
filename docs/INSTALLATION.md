# Installation

Use the [Releases page](https://github.com/mks-devx/MK-Crossfader/releases) to
check current installer availability. Only the `.pkg` attachment is the macOS
installer; GitHub's source ZIP and TAR archives are not installable products.
For local source builds, see the online
[build guide](https://github.com/mks-devx/MK-Crossfader/blob/main/docs/BUILDING.md).

The combined installer is for macOS. The experimental
Windows 11 x64 VST3 has a separate
[community preview guide](https://github.com/mks-devx/MK-Crossfader/blob/main/docs/WINDOWS_PREVIEW.md) and is not included in the macOS
package.

## macOS

For a published release, download its `.pkg` and matching
`.pkg.sha256` file from the
[Releases page](https://github.com/mks-devx/MK-Crossfader/releases).

Close Ableton Live, Maschine 3, and any other plug-in hosts before installing.
To verify a download in Terminal, run the checksum command from the download
folder. Replace `VERSION` with the version number in the downloaded filename:

```zsh
shasum -a 256 -c "MK-Crossfader-VERSION.pkg.sha256"
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

Open `START_HERE.md` in the installed documentation folder for the
[Maschine setup](MASCHINE_SETUP.md) and [Ableton setup](ABLETON_SETUP.md) guides.
Version 0.3.0 updates the internal VST3 link protocol. Close every host before
upgrading and use the same version for all linked instances. Saved role,
session, slot and mapping settings remain compatible.

## Build A Local-Test Installer

Maintainers can create one package containing both products:

```zsh
./scripts/build-installer.sh --local-test
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

Close Ableton Live, Maschine 3, and other plug-in hosts, then remove the three
installed paths listed above. Removing the app does not delete its local macOS
preferences.
