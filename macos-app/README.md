# MK MIDI Crossfader

MK MIDI Crossfader is a native macOS app created for coordinated live
transitions with Maschine 3 and Maschine+ hardware in Controller mode. Its
persistent menu-bar control converts one physical MIDI CC into separate control
values for parameters learned through the virtual `MK Crossfader` CoreMIDI
input.

## Compatibility

The app uses standard CoreMIDI rather than a Maschine-specific control
protocol. It can control other macOS software that accepts a virtual CoreMIDI
input and exposes parameters to MIDI Learn. Use `Parameter` targets for the
full 0-127 range. `Level` targets are specifically calibrated for Maschine's
mixer range and stop at CC 95.

Maschine 3 is the primary documented workflow. The app has also been manually
verified with Ableton Live 12.4.5 on macOS, where one physical control can move
several mapped parameters at once. Compatibility with other software depends on
its MIDI input and MIDI Learn implementation.

For Ableton Live, enable **Remote** for the virtual `MK Crossfader` input under
**Settings > Link, Tempo & MIDI**, then map each `Parameter` target through
Live's MIDI Map mode. One physical fader can then control several Live
parameters, with independent ranges and directions for every mapping. See the
[Ableton Live setup guide](../docs/ABLETON_SETUP.md) for a complete example.

## Features

- A/B crossfade, A+B to B, A+B to A, and paired fade modes
- Full Centre, Linear, Smooth, Wide Blend, and Fast Cut curves
- Kill, -24 dB, -18 dB, and -14 dB minimum levels
- Per-target Range morphing with independent endpoints and shape
- Up to 128 MIDI-learned targets
- Up to 16 complete user presets
- Additive A/B Crossfade Pair, Parameter Range, and Level Target quick actions
- Return & Pause, startup pause, target uniqueness checks, and controller
  hot-plug refresh
- Dock and app-switcher presence that can be disabled under **Advanced** while
  keeping the menu-bar control available
- Optional **Launch at Login** registration through macOS Service Management;
  no helper process or background daemon is installed
- Manual GitHub release checking with no background checks, automatic download,
  or automatic installation

Update checks require a published macOS installer and matching
checksum, skipping incomplete or withdrawn downloads. Stable releases are the
default; **Include testing prereleases** enables explicit preview discovery.
These update-check improvements are included from 0.3.1.

Quick actions add targets without changing existing mappings. Saved presets are
separate, complete snapshots of targets and crossfade settings.

### Built-in Presets

Version 0.3.1 restores two built-in choices alongside the quick actions:

- **Performance A/B:** active Level targets follow their A/B sides, using
  A to B mode, Full Centre and Kill. Parameter behaviours remain unchanged.
- **Scene Morph:** every active target uses Range between its existing Left
  and Right values, with Smooth as the global shape.

Both operate on existing targets, require paused output and ask for confirmation.
**Save Current & Apply** saves a complete snapshot first, when a user-preset slot
is available. **Apply** changes behaviour without creating a snapshot.
Neither changes MIDI CC assignments, target names, endpoints, custom shapes,
Return Values or Off targets. Both reset A/B mode, floor and direction switches;
Range targets using Global shape follow the new curve. No targets are added or
removed, and no saved presets are overwritten. A/B and Range can still be mixed
afterwards. Map the resulting MIDI outputs to the desired host parameters.

## Target Types

`Level` targets are capped at CC 95, Maschine's nearest safe step below unity.
`Parameter` targets can use the complete 0-127 range for filters, sends, and
other learned controls.

Each target can be assigned to A, B, Range, or Off. A and B follow the global
mode and curve. Range uses its own left value, right value, shape, and Return
Value. This is a configured MIDI value, not a value read back from the target.

## Build

From the repository root:

```zsh
swift test --package-path macos-app
./macos-app/scripts/build-app.sh
```

The app and zip archive are written to `macos-app/build/`. This source build is
ad-hoc signed for local testing. For normal installation, use the Developer ID
signed and Apple-notarised package from the repository's Releases page.

The checked-in icon is used by normal builds. Maintainers can regenerate it
with `./macos-app/scripts/build-icon.sh` using standard macOS tools.

## Safety

The app starts paused and waits for the physical fader's first position before
activation. Return actions are best-effort: a crash, forced termination, or
power loss cannot send a final MIDI message. Keep a neutral recovery control
in the Maschine template and validate physical hot-plug behaviour before live
use.

See [Maschine setup](../docs/MASCHINE_SETUP.md) and
[architecture](../docs/ARCHITECTURE.md).
