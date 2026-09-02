# MK Crossfader VST3

MK Crossfader is an independent macOS VST3 for linked crossfading across
multiple plug-in instances. It runs without MK MIDI Crossfader.

## Roles

- One `Controller` instance publishes the crossfader state for a session.
- Each `Target` instance reads one unique slot and applies local smoothed gain.

The Controller supports A to B, A+B to B, A+B to A, A+B to Floor, and Custom
Scene modes. Five curves and four minimum levels shape the transition. Custom
Scene gives every route explicit left and right endpoint gains.

Targets use 15 ms gain smoothing and do not move host mixer faders.

## Maschine Routing

1. Put one Controller on Master.
2. Map its Crossfader parameter to the physical fader.
3. Put a Target after the effects on every Group or Sound that should fade.
4. Keep all linked instances on the same session and give every Target a unique
   slot.
5. Name and assign routes in the Controller.

`UNITY` immediately returns linked Targets to 0.0 dB. Duplicate Controllers
and duplicate Target slots are reported as conflicts. A Target that loses its
Controller holds its last valid gain.

## Build

```zsh
./vst3/scripts/build.sh
```

The script builds a universal `arm64` and `x86_64` VST3, applies an ad-hoc
signature, and runs the DSP/state, cross-process, and JUCE host validation
tests. By default, CMake fetches JUCE 8.0.15. Set `JUCE_SOURCE_DIR` to reuse a
local JUCE checkout.

The output is under `vst3/build-universal/`. The bundle is suitable for local
testing, not public binary distribution, until Developer ID signing and Apple
notarisation are completed.

See [Maschine setup](../docs/MASCHINE_SETUP.md) and
[building](../docs/BUILDING.md).
