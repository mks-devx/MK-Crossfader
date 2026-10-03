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

The combined installer requires **macOS 14 or later** and includes Apple Silicon
and Intel builds. Stable **0.3.1** is recommended for established workflows;
**0.4.0** is the XYZ testing preview. The VST3 can be built separately for macOS
13, but the combined installer and MIDI app require macOS 14.

For a published release, download its `.pkg` and matching
`.pkg.sha256` file from the
[Releases page](https://github.com/mks-devx/MK-Crossfader/releases).

If MK MIDI Crossfader is running, use **Return & Pause** while the destination
host is still open, then quit the MIDI app. Close Ableton Live, Maschine 3, and
all other plug-in hosts before installing. Keep a backup of any development
bundle you intend to replace.

If you previously installed a source-built VST3, inspect both the system-wide
and per-user locations listed below. Keep only one active copy before installing
the release; move the other bundle to a backup outside all plug-in scan folders.

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
Version 0.3.0 changed the internal VST3 link protocol. Close every host before
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

## Source-Built MK MIDI Crossfader

These development steps are separate from installing the published package.
You can open the built app directly from `macos-app/build` without replacing the
installed release. Quit any other copy first; development and installed copies
share the app's saved settings.

To replace the installed app intentionally, use **Return & Pause**, quit it,
and back up the existing bundle outside `/Applications` before copying. After
running `./macos-app/scripts/build-app.sh`:

```zsh
ditto "macos-app/build/MK MIDI Crossfader.app" \
  "/Applications/MK MIDI Crossfader.app"
```

Start the app before opening Maschine, then enable its virtual MIDI input.

## Source-Built MK Crossfader VST3

Close all plug-in hosts first. Inspect both possible installation locations:

- System-wide release: `/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3`
- Per-user development copy: `~/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3`

Both bundles use the same plug-in identity. Keep only one active copy to avoid
host-dependent discovery of an older or different build. Before using the
per-user location below, move any existing system-wide copy to a backup outside
all plug-in scan folders; back up an existing per-user copy before replacing it.
Keep backups until your existing projects open correctly. To return to the
release, close hosts and move the development copy out before reinstalling it.

After running `./vst3/scripts/build.sh`:

```zsh
mkdir -p "$HOME/Library/Audio/Plug-Ins/VST3"
ditto \
  "vst3/build-universal/MK_Crossfader_artefacts/Release/VST3/MK Crossfader.vst3" \
  "$HOME/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3"
```

Restart or rescan the host after installation and verify which version it loads.

Do not bypass macOS security warnings for copies downloaded from unofficial
sources. Verify the checksum and obtain releases only from this repository.

## Uninstall

Use **Return & Pause** while the destination host is still open, then quit
MK MIDI Crossfader and all plug-in hosts. Inspect the three system-wide paths
under **Installed Files** and, if you used the source-build instructions, also
`~/Library/Audio/Plug-Ins/VST3/MK Crossfader.vst3`. Remove only the copies you
installed, keeping a backup if you may need to restore them. A per-user copy
left behind can still be discovered by your host.

Rescan or restart the host afterward. Removing the app does not delete its local
macOS preferences. An app launched directly from a build folder also remains
there until you remove that development copy.
