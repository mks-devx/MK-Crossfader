# MK Crossfader Setup

## Install

Read [Installation](INSTALLATION.md) for macOS requirements, installer locations,
verification, and removal.

## Connect Your Host

- [Maschine 3 setup](MASCHINE_SETUP.md): MIDI mapping and VST3 Controller/Target routing.
- [Ableton Live setup](ABLETON_SETUP.md): MIDI multi-mapping and VST3 crossfading.

## Choose the Tool

The MIDI app maps one incoming MIDI CC to multiple output CCs. A/B and Range
targets can be combined, so the same fader or knob can crossfade levels while
moving a filter or another MIDI-learnable parameter.

The VST3 changes audio gain inside Target instances. It does not move host mixer
faders or control parameters in other plug-ins. Audio must reach each Target.
The MIDI app is not required for the VST3 to operate.

Return Value is the value sent when returning a MIDI mapping to its chosen
position. It does not remember the host's original value. Choose it for the
specific parameter; 100% is not a universally neutral setting.

When upgrading the VST3, close all hosts and update every linked instance to
the same version. Version 0.3.0 uses an updated internal link protocol and does
not link to instances from earlier versions still loaded in another host.
Saved role, session, slot and mapping settings remain compatible.

## Support and Updates

Setup guides, releases and public issue reports are available from the
[project repository](https://github.com/mks-devx/MK-Crossfader).
