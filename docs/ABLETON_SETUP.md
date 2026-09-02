# Ableton Live Setup

MK MIDI Crossfader can turn one physical MIDI fader or knob into a coordinated
multi-parameter control for Ableton Live. The native app receives one hardware
CC and sends separate CC messages through its virtual `MK Crossfader` MIDI
input. Each destination can move through a different range and direction.

This workflow uses Ableton Live's standard MIDI Map system. It does not require
Max for Live or the MK Crossfader VST3.

## Configure Ableton Live

1. Open MK MIDI Crossfader and select the physical MIDI controller.
2. In Ableton Live, open **Settings > Link, Tempo & MIDI**.
3. Find the input port named **MK Crossfader** and enable **Remote**.
4. Leave the app paused while creating or changing mappings.

## Create A Multi-Control Mapping

1. Add a target in MK MIDI Crossfader and select **Parameter**.
2. Set the target to **Range**.
3. In Ableton Live, enter MIDI Map mode with **Cmd+M**.
4. Select the destination parameter in Live.
5. Press **Send Learn** on the matching target in MK MIDI Crossfader.
6. Exit MIDI Map mode and repeat for each additional destination.
7. Set the target's **Left**, **Right**, **Shape**, and **Return Value**.
8. Move the physical fader once, activate the app, and test the complete travel.

Every target uses a separate output CC, so one incoming hardware movement can
control many independently configured Ableton mappings.

## Example Transition

A single physical fader could control:

| Target | Left | Right | Shape | Intended movement |
| --- | ---: | ---: | --- | --- |
| Auto Filter cutoff | 20% | 80% | Exponential | Opens later in the movement |
| Reverb send | 0% | 35% | Smooth | Adds space gradually |
| Delay feedback | 45% | 15% | Linear | Reduces feedback while the filter opens |
| Utility Gain | 100% | 85% | Smooth | Creates controlled headroom |

These percentages are MIDI output values. Ableton applies them through the Min
and Max range stored in its MIDI mapping, so the audible result also depends on
the destination parameter and its mapping range.

## Important Behaviour

- Use **Parameter**, not **Level**, for Ableton mappings. Parameter targets use
  the full MIDI range; Level targets are calibrated for Maschine's mixer.
- **Return Value** is sent when the app pauses, the target is removed or
  rerouted, the output changes, or the app quits normally.
- Return Value does not remember or restore the parameter value that Ableton
  had before activation.
- The app sends MIDI CC messages only. It does not use the Live API, discover
  parameters, change routing, or receive parameter feedback from Live.
- Ableton saves its MIDI mappings inside the Live Set. Save the Set after
  testing the mappings.
- A crash, forced quit, or power loss cannot send final Return Values. Keep a
  neutral recovery control available before performance use.

## Suitable Uses

- performance transitions across several tracks or effects;
- filter, send, feedback, and gain movements from one control;
- repeatable effect builds and breakdowns;
- inverse mappings where one parameter rises while another falls; and
- restricted parameter ranges that avoid unusable or unsafe extremes.
