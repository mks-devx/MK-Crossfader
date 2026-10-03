# XYZ input — 0.4.0 preview

XYZ lets one touch control separate parameters through X, Y and Z. Each input is
an absolute 7-bit MIDI CC on one selected controller source. This is a generic
CC mapping workflow; controller hardware, factory profiles and actual device message
ordering have not been verified. No factory CC assignments are assumed.

## Set up inputs

1. Pause output and choose your controller in Settings.
2. Select **XYZ**. Use **Edit** on each axis to enter the channel (1–16) and CC
   (0–127) configured on your controller. Each axis needs a distinct
   channel/CC pair.
3. Alternatively, choose **MIDI Learn**, move only that axis and check the
   detected channel/CC. The first candidate stays selected even if other CCs
   arrive. Choose **Use for X/Y/Z** to confirm, **Try Again** to listen again,
   or **Cancel Learn** to preserve the previous mapping. If your controller
   emits several axes together, manual entry is more reliable.
4. For each target, choose **Type** (Level or Parameter), **Input** (X, Y or Z)
   and **Follow** (A, B, Range or Off). These are independent choices:
   Parameter can follow A or B just as Level can.
5. Configure target output CCs and use **Send Learn** to map them in your host.
   This sends a temporary mapping pulse even while paused; it is separate from
   learning the controller inputs. Set safe Return Values before mapping.
6. Send a fresh value on every axis used by a participating target, then enable
   **Active**. Unused axes can remain unbound. Input changes, source changes,
   preset loads and relaunches require fresh values again.

For a simple example, assign two Level targets to X with Follow A/B, a Parameter
filter target to Y with Range, and a Parameter effect target to Z with Range.
Level output stops at CC 95; Parameter spans CC 0–127. Y endpoints are labelled
Bottom/Top and Z endpoints Minimum/Maximum. Input direction depends on the
controller's configuration.

## Optional Touch Gate

Without a gate, the last value is held until the next CC arrives. A quiet stream
is not interpreted as a release. Z=0 is an ordinary pressure value.

If your controller can send a **dedicated CC** for touch, configure it under
**Advanced → Touch Gate**, using manual entry or confirmed learning. It must use
a channel/CC pair distinct from all axes and send:

- **1–127 on touch-on**, before fresh values for all axes used by targets.
- **0 on release**. Repeated positive values do not start a new touch.

Choose a per-target release policy:

- **Hold** leaves that target's last output unchanged on release.
- **Return Value** sends its configured Return Value once on release. This is a
  chosen MIDI value, not a value read back from your host.

Axis packets sent while released are ignored, including reset-to-zero packets.
On the next touch, output waits for every required axis and resumes together.
The controller must provide all those values after touch-on; devices with other
message ordering or unchanged axes omitted on a new touch need an appropriate
controller profile before using the gate.

**Active** stays on between touches; it can still be paused while released.
**Return & Pause** restores participating targets regardless of Hold/Return.
Disabling a gate with Return policies asks to change those policies to Hold.
A preset containing Return without a local gate keeps the policy and blocks XYZ
activation until a gate is configured or the affected policies are set to Hold.

## Single input and presets

Single is the default for existing settings. All targets follow X, using the
existing crossfade/range behaviour. Saved Y/Z choices and release policies are
retained but the gate is bypassed in Single. Existing presets load as Single;
new presets also save input mode, target axes and release policies. Controller
source and CC bindings are settings on this computer, not part of presets.

Invalid or newer-format input settings are kept intact and activation is blocked.
Use **Advanced → Reset Input Settings** only when you want to discard those input
settings. This keeps targets and saved presets and returns to unbound Single.

## Validation boundaries

This version handles one logical XYZ touch, not separate fingers, MPE, relative
encoders, 14-bit CC, pitch-bend input or four-corner scene morphing. Automated
simulated MIDI tests and native view checks cannot establish hardware timing,
DAW response or live-performance reliability. Rehearse touch/release, controller
reconnection, mapping and recovery with your actual controller and host before
performance use. No inactivity timer is used to guess a release.

The combined 0.4.0 preview aligns both component versions. XYZ is a native-app
feature; VST3 audio processing and saved-state format are unchanged from 0.3.1.
The 0.3.1 stable release remains available for established workflows.
