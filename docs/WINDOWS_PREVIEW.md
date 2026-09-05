# Windows VST3 Community Preview

Windows support currently covers **MK Crossfader VST3 only**. The native MIDI
Control App remains a separate macOS application.

The Windows build targets 64-bit Windows 11 and is an experimental community
preview. A Windows CI build and test workflow is provided; its presence alone
does not establish that a particular build has passed. Check the workflow result
for the exact revision you download. Windows host testing by the maintainer has
not been completed in Maschine 3, Ableton Live, or on a physical Windows system.
Do not rely on it for a live performance until the exact
project and recovery workflow have been tested locally.

Ordinary CI does not publish preview downloads. Only a separately reviewed
archive explicitly attached to a GitHub Release is intended for distribution.
If no Windows archive is attached, build from source instead.

## Install

1. Close every VST3 host.
2. Extract `MK Crossfader.vst3` from the preview archive.
3. Copy the complete plug-in folder to:

   `C:\Program Files\Common Files\VST3`

4. Reopen the host and rescan VST3 plug-ins if necessary.

Windows Defender SmartScreen or Smart App Control may warn about or block an
unsigned community preview. Check the release notes for signing status. Do not turn
off Windows security protections to install it. Use the source and automated
build workflow instead if the binary is blocked.

## Test

Start with a disposable project:

1. Put one MK Crossfader instance on Master or Main and leave it as
   **Controller**.
2. Put Target instances after the audio source or effects on two tracks,
   Groups, or Sounds.
3. Use the same Session in every instance and a unique Target Slot for every
   Target.
4. Assign one route to A and one route to B in the Controller.
5. Move the plug-in Crossfader and confirm that Target gain changes smoothly
   while host mixer faders remain untouched.
6. Save, close, and reopen the project to verify role, session, slot, names,
   routes, and crossfader settings.

Also check duplicate Controller and duplicate Target Slot warnings, Unity
Override, plug-in removal, host rescan, and project reopening.

## Report Results

Use the
[Windows preview report](https://github.com/mks-devx/MK-Crossfader/issues/new?template=windows-preview.yml)
for both successful tests and failures. Include the exact MK Crossfader build,
Windows version, processor, host and host version, setup, and reproduction
steps. Remove personal information, licence details, private file paths, and
project content from screenshots or logs before attaching them.

The plug-in contains no telemetry, update checker, or network client. Linked
instances exchange crossfader state through local Windows shared memory only.

## Build From Source

Requirements:

- Windows 11 x64
- Visual Studio 2022 with Desktop development with C++
- CMake 3.22 or later
- Git and internet access for the default JUCE download

From PowerShell at the repository root:

```powershell
./vst3/scripts/build-windows.ps1
```

The script builds the VST3 and runs the DSP, state, editor, cross-process, and
JUCE host-loading tests. Set `JUCE_SOURCE_DIR` to use an existing JUCE 8.0.15
checkout.
