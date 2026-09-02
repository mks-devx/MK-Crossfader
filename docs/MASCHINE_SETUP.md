# Maschine 3 Setup

Both workflows work with any MIDI controller that sends a standard, assignable
MIDI CC. No specific controller model is required.

MK Crossfader itself runs on the Mac. Maschine+ is supported as a controller
for Maschine 3 desktop software: switch Maschine+ to **Controller mode** and
keep the app or VST3 on the Mac. Neither product can be installed or loaded
inside Maschine+ in standalone mode.

Native Instruments does not support Maschine/Maschine Mikro MK1 or MK2 as
integrated controllers for Maschine 3. A device that can independently send a
standard MIDI CC may still drive the native app, but that is generic MIDI use,
not Maschine 3 hardware integration.

## Independent VST3

1. Add MK Crossfader to Master and set `Role` to `Controller`.
2. Select `Session 1`.
3. Map the Controller's `Crossfader` parameter to the physical fader through
   Maschine.
4. Add MK Crossfader as the last required insert on each Group or Sound that
   should fade.
5. Set those instances to `Target`, keep them on `Session 1`, and assign a
   unique Target Slot to every instance.
6. In the Controller, name each route and assign it to A, B, or Off.
7. Use `Custom Scene` only when a route needs explicit left and right endpoint
   gains.

The Master instance is a controller only; it does not fade the complete master
signal. Target instances apply gain locally while Maschine's mixer values stay
unchanged.

A Target works only when audio passes through its insert. That audio can come
from a loaded sample, loop, software instrument, or live input; the VST3 is not
limited to samples. It does not process MIDI or generate sound for an empty
Sound or Group.

Put a Target after the insert effects that should be included in its fade.
Effects or sends downstream of the Target may continue producing tails. A
silent or host-suspended Group can appear offline until Maschine processes
audio for it.

Use `UNITY` as the immediate recovery control. A duplicate Controller on one
session reports `CONTROLLER CONFLICT`; duplicate Target slots report
`TARGET SLOT CONFLICT` and remain at unity.

## MIDI Bridge App

1. Start MK MIDI Crossfader before Maschine.
2. Enable `MK Crossfader` under Maschine Preferences > MIDI > Input.
3. Select the physical controller and incoming CC in the app.
4. Add and name a target.
5. Put the matching Group, Sound, filter, send, or other parameter into
   Maschine MIDI Learn.
6. Press `Send Learn`, then assign the target to A, B, Range, or Off.
7. Repeat only for the controls needed by the performance and save the
   assignments in a dedicated Maschine template.

Use `Restore & Pause` before changing locked routing or closing the app.
Forced termination cannot send restore values, so retain a manual neutral
snapshot or recovery control.

Maschine can disable a virtual MIDI input when the app disappears. Start the
app before Maschine and avoid restarting it during a performance. If a restart
is unavoidable, verify that the virtual input is still enabled before resuming.

## Using Both

The two products can run together, but they are unrelated systems. Use both
only with a deliberate split, such as VST3 Group gains plus one app-controlled
filter. Otherwise, choose the workflow that needs the fewest moving parts.
