# Architecture

## MK MIDI Crossfader

The Swift app owns the physical MIDI input and creates one virtual CoreMIDI
source named `MK Crossfader`. It keeps a persistent menu-bar control and can
optionally appear in the Dock or register with macOS to launch at login. It
converts one absolute MIDI CC into a separate CC for every configured target.

This transport uses standard CoreMIDI and does not require Maschine. Any macOS
software that exposes the virtual source as an input and supports MIDI Learn
can receive the generated CC messages. The app does not inspect or directly
address objects inside the destination software.

Maschine 3 does not expose Groups or Sounds as addressable MIDI destinations.
Each app target therefore needs a one-time MIDI Learn assignment in the
Maschine template. Target names are labels for that mapping, not live Maschine
object references.

The app owns transition modes, curves, target ranges, Return Values, presets,
and visual colours. Level targets stop at Maschine's nearest safe unity step:
CC 95, approximately -0.1 dB. CC 96 is already above unity. Parameter targets
can use the full 0-127 MIDI range.

The app stores configuration locally in macOS user defaults. It has no network
service and sends no audio.

## MK Crossfader VST3

The JUCE VST3 contains both roles:

- A **Controller** publishes the selected session's crossfader state.
- Each **Target** reads one slot from that session and applies a smoothed local
  gain to its own audio.

Instances communicate through per-user POSIX shared memory on macOS and a
local-session named shared-memory mapping on Windows. There are eight isolated
sessions. Duplicate Controllers and duplicate Target slots are reported as
conflicts. Parameter IDs, plug-in identifiers, and the shared-memory protocol
are compatibility boundaries and should not be changed casually.

The VST3 changes only its own gain. It does not move the host's mixer faders.
Effects placed after a Target can continue producing tails after that Target is
closed. A Target processes audio, not MIDI, and has no audible effect unless an
audio signal passes through its plug-in instance.

## Product Boundary

- The app and VST3 do not share state, presets, MIDI mappings, or runtime code.
- App presets cannot configure VST3 instances.
- VST3 sessions are not visible to the app.
- Neither product rewrites Maschine routing.
- The native app can target other MIDI Learn software through CoreMIDI. The
  app and VST3 are both manually verified with Ableton Live on macOS, while
  Maschine 3 remains the primary documented hardware workflow.
- Both products run on macOS. The experimental Windows build contains only the
  VST3; the native MIDI Control App remains macOS-only. Neither product runs
  inside Maschine+ standalone.
- AU is not currently built or supported.

The app retains settings migration for its older target type so existing local
preferences can load safely. That compatibility path does not connect the app
to the current independent VST3.
