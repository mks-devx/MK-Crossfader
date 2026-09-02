<div align="center">
  <img src="macos-app/packaging/Resources/MKCrossfaderLogo.png" width="112" alt="MK Crossfader logo">
  <h1>MK Crossfader</h1>
  <p><strong>Audio crossfading and MIDI multi-mapping for live performance</strong></p>
  <p>
    Created for Maschine 3 on macOS with Maschine+ in Controller mode.<br>
    Also verified with Ableton Live and compatible macOS MIDI and VST3 hosts.
  </p>
  <p>
    <a href="https://github.com/mks-devx/MK-Crossfader/releases/latest"><img src="https://img.shields.io/github/v/release/mks-devx/MK-Crossfader?display_name=tag&amp;sort=semver&amp;style=flat-square&amp;color=555555" alt="Latest release"></a>
    <a href="https://github.com/mks-devx/MK-Crossfader/actions/workflows/ci.yml"><img src="https://github.com/mks-devx/MK-Crossfader/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/licence-AGPL--3.0-555555?style=flat-square" alt="AGPL-3.0 licence"></a>
  </p>
  <p>
    <a href="#download-and-install">Download</a> ·
    <a href="docs/MASCHINE_SETUP.md">Maschine Setup</a> ·
    <a href="docs/ABLETON_SETUP.md">Ableton Live Setup</a> ·
    <a href="#documentation">Documentation</a>
  </p>
</div>

---

MK Crossfader began as a focused way to perform transitions from Maschine+
hardware while running Maschine 3 on a Mac. A single physical fader or knob can
move several sounds or parameters together, with separate direction, range,
curve, and return behaviour for each destination.

The project provides two workflows:

| MIDI Control App | Audio Crossfader VST3 |
| --- | --- |
| Turns one incoming MIDI CC into multiple independently shaped CC outputs. | Links one Controller instance to multiple audio Target instances. |
| Controls levels, filters, sends, effects, and other MIDI-learnable parameters. | Applies smoothed audio gain while leaving the host's mixer faders untouched. |
| Works with Maschine 3, Ableton Live, and other macOS software that supports MIDI Learn. | Works with Maschine 3, Ableton Live, and other compatible macOS VST3 hosts. |

The installer includes both components. They can be used separately, and any
MIDI controller that sends an assignable MIDI CC can provide the physical
control.

> [!IMPORTANT]
> Maschine+ is supported as hardware in **Controller mode** while Maschine 3 and
> MK Crossfader run on the Mac. Neither component can be installed or loaded on
> Maschine+ in standalone mode.

## Choose A Workflow

| What You Want To Do | Use |
| --- | --- |
| Move several mapped levels, filters, sends, or effects from one hardware control | **MIDI Control App** |
| Build custom parameter movements with individual ranges and curves | **MIDI Control App** |
| Avoid inserting a plug-in on every destination | **MIDI Control App** |
| Crossfade several audio paths without moving their mixer faders | **Audio Crossfader VST3** |
| Keep an exact plug-in unity state at 0.0 dB | **Audio Crossfader VST3** |

Use one workflow for each crossfader system. Combining them is possible when
each has a separate, deliberate role.

## MIDI Control App

The native macOS app receives one MIDI CC and sends a separate CC for every
configured target through its virtual **MK Crossfader** MIDI port. Each target
can follow side A, side B, or a custom range.

In Ableton Live, one movement can open an Auto Filter through a restricted
range, raise a reverb send, reduce delay feedback in the opposite direction,
and trim Utility Gain. Live stores the MIDI mappings in the Live Set; the app
does not inspect the Set or read parameter values back from Live.

<p align="center">
  <img src="docs/images/mk-midi-crossfader-app.png" width="820" alt="MK MIDI Crossfader showing controller mapping, targets, and crossfade controls">
</p>

## Audio Crossfader VST3

One Controller publishes the crossfader state. Target instances receive that
state and apply local smoothed gain to the audio passing through them. This
keeps the host's mixer faders where you set them and lets effects placed before
each Target remain part of the sound.

<table>
  <tr>
    <td width="50%" align="center"><strong>Controller</strong></td>
    <td width="50%" align="center"><strong>Target</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/mk-crossfader-vst3.png" alt="MK Crossfader VST3 Controller showing crossfade modes and target routes"></td>
    <td><img src="docs/images/mk-crossfader-vst3-target.png" alt="MK Crossfader VST3 Target showing its session, target slot, connection state, and gain"></td>
  </tr>
</table>

Each Target is an audio effect. It works with samples, loops, software
instruments, and live input, but it cannot process MIDI or create sound on a
silent channel. A Controller on the Master or Main track distributes control
data without fading that track's audio.

## Download And Install

Download the current Developer ID signed and Apple-notarised installer from the
**[Releases page](https://github.com/mks-devx/MK-Crossfader/releases/latest)**.
No unsigned public binaries are distributed from this repository.

The package installs:

- **MK MIDI Crossfader** in `/Applications`
- **MK Crossfader VST3** in `/Library/Audio/Plug-Ins/VST3`
- the setup manual in `/Library/Application Support/MK Crossfader`

Close Maschine 3, Ableton Live, and other plug-in hosts before installation.
Follow the [installation guide](docs/INSTALLATION.md) for the complete process.

## Quick Start

### VST3 With Maschine 3

1. Add MK Crossfader to Master and set its role to **Controller**.
2. Map the Crossfader parameter to the physical fader through Maschine 3.
3. Add a **Target** after the effects on every Group or Sound that should fade.
4. Keep all instances in the same session and give every Target a unique slot.
5. Assign each route to A, B, or Off in the Controller.

The same structure works in Ableton Live: put the Controller on Master or Main,
then put a Target after the instrument, sample player, or effects on every audio
path that should join the crossfade.

### MIDI Multi-Mapping

1. Open MK MIDI Crossfader and select the physical MIDI controller.
2. Enable the virtual **MK Crossfader** port for MIDI mapping in the destination.
3. Add a **Parameter** target and activate MIDI Learn on the destination control.
4. Press **Send Learn**, then repeat for the remaining parameters.
5. Assign each target to A, B, Range, or Off and configure its movement.

In Ableton Live, enable **Remote** for the **MK Crossfader** input under
**Settings > Link, Tempo & MIDI**. The app does not require Max for Live.

## Compatibility

| Component | Requirement | Primary Use |
| --- | --- | --- |
| MK MIDI Crossfader | macOS 14 or later; CoreMIDI destination with MIDI Learn | Maschine 3, Ableton Live, and other MIDI-learnable macOS software |
| MK Crossfader VST3 | macOS 13 or later; compatible VST3 host | Maschine 3, Ableton Live, and other macOS VST3 hosts |
| Hardware control | Assignable MIDI CC | Maschine+ in Controller mode or another MIDI controller |

The Maschine-calibrated **Level** target requires Maschine 3. General
**Parameter** targets can be used with other destinations that expose controls
through MIDI Learn. This project does not add Maschine 3 support for legacy
hardware that Native Instruments no longer supports.

## Live Use

Treat MK Crossfader as performance software, not as a replacement for a
recoverable mix state. Before a show, test the exact project, controller, USB
path, host version, and recovery procedure you intend to use.

- Keep a manual unity or neutral recovery control available.
- The MIDI app cannot send configured Return Values after a crash, forced quit,
  or power loss.
- A VST3 Target that loses its Controller holds its last valid gain.

## Documentation

| Guide | Contents |
| --- | --- |
| [Installation](docs/INSTALLATION.md) | Signed package installation, locations, and removal |
| [Maschine Setup](docs/MASCHINE_SETUP.md) | Controller/Target routing, MIDI Learn, and recovery |
| [Ableton Live Setup](docs/ABLETON_SETUP.md) | MIDI multi-control and VST3 audio crossfading |
| [Architecture](docs/ARCHITECTURE.md) | Component boundaries, communication, and failure behaviour |
| [Privacy](docs/PRIVACY.md) | Local data, update checks, and network behaviour |
| [Building](docs/BUILDING.md) | Source builds and development requirements |
| [Support](SUPPORT.md) | Public support policy and bug-report requirements |

## Build And Test

Building from source requires Xcode command-line tools and CMake 3.22 or later.
Run the complete local verification suite with:

```zsh
./scripts/verify-all.sh
```

This builds and tests both components without installing them. The VST3 build
uses JUCE 8.0.15, fetched automatically unless `JUCE_SOURCE_DIR` points to a
local checkout. Every push and pull request also runs the macOS app tests, VST3
tests, universal build checks, and public-history privacy audit in GitHub
Actions.

## Support And Updates

Use [GitHub Issues](https://github.com/mks-devx/MK-Crossfader/issues) for setup
questions and reproducible bug reports so the answers remain public and
searchable. Please do not contact Mike through Instagram, email, or other
private channels for individual setup or troubleshooting.

Support is provided on a best-effort basis. Check the
[Releases page](https://github.com/mks-devx/MK-Crossfader/releases) or use the
macOS app's manual **Check for Updates** command. The app never checks,
downloads, or installs updates in the background, and the VST3 remains offline.

## Project

Created by [Mike Konstantinidis](https://konstantinidis.net/) while building his
own live set, then released as an open-source project for the community.

- Contributions: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security reports: [SECURITY.md](SECURITY.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Licence: [GNU Affero General Public License v3.0](LICENSE)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

Product names are used only to describe compatibility and workflow. MK
Crossfader is independent and is not affiliated with or endorsed by the
manufacturers mentioned in the documentation. See
[TRADEMARKS.md](TRADEMARKS.md).
