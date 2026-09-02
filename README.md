# MK Crossfader

<p align="center">
  <img src="macos-app/packaging/Resources/MKCrossfaderLogo.png" width="128" alt="MK Crossfader logo">
</p>

MK Crossfader is a free, open-source pair of macOS tools for expressive
crossfading in Maschine 3:

- **MK MIDI Crossfader** is a native menu-bar app that maps one physical MIDI
  fader to Maschine mixer levels or other MIDI-learnable parameters.
- **MK Crossfader VST3** is a self-contained plug-in that links one Controller
  instance to Target instances without changing Maschine's mixer faders.

The products are independent. The VST3 does not need the app, and the app does
not configure or communicate with the VST3.

> This repository currently provides source builds. Public Developer ID signed
> and notarised binaries are not available yet.

## Choose A Workflow

| Need | MIDI app | VST3 |
| --- | --- | --- |
| Crossfade without inserting a plug-in on every target | Yes | No |
| Keep Maschine mixer faders untouched | No | Yes |
| Control filters, sends, or other learned parameters | Yes | No |
| Run without a separate app | No | Yes |
| Exact plug-in unity at 0.0 dB | No | Yes |

Use one workflow per crossfader system. Combining them is possible, but only
makes sense when each has a separate job.

## Quick Start

For the independent VST3:

1. Add one MK Crossfader instance to Master and set it to **Controller**.
2. Map its Crossfader parameter to your physical fader through Maschine.
3. Add a **Target** instance after the effects on every Group or Sound you want
   to control.
4. Give each Target a unique slot in the same session.
5. Assign those routes to A, B, or Off in the Controller.

For the MIDI app:

1. Start MK MIDI Crossfader before Maschine.
2. Enable its virtual **MK Crossfader** MIDI input in Maschine.
3. Add a target, put the matching Maschine parameter into MIDI Learn, and press
   **Send Learn**.
4. Assign the target to A, B, Range, or Off.

See [Maschine setup](docs/MASCHINE_SETUP.md) for the complete routing and
recovery workflow.

## Requirements

- macOS 14 or later for MK MIDI Crossfader
- macOS 13 or later and a VST3 host for MK Crossfader VST3
- Maschine 3 desktop software for the documented workflow
- Xcode command-line tools and CMake 3.22 or later to build from source

These tools do not run on Maschine+ in standalone mode.

## Build And Test

```zsh
./scripts/verify-all.sh
```

The script builds and tests both products without installing them. JUCE 8.0.15
is fetched automatically for the VST3 unless `JUCE_SOURCE_DIR` points to an
existing checkout.

See [Building](docs/BUILDING.md) and [Installation](docs/INSTALLATION.md) for
individual commands and output locations.

## Live Use

Treat this as performance software, not a replacement for a recoverable mix
state. Test the exact project, controller, USB path, and host version before a
show. Keep a manual unity or neutral recovery control available. A crash, forced
termination, or power loss cannot restore the last MIDI-controlled value.

More detail is available in [Architecture](docs/ARCHITECTURE.md) and
[Privacy](docs/PRIVACY.md).

## Contributing

Bug reports and focused pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Security issues
should follow [SECURITY.md](SECURITY.md).

## Licence

MK Crossfader is released under the
[GNU Affero General Public License v3.0](LICENSE). The VST3 uses JUCE 8.0.15
under JUCE's AGPLv3 option. See [third-party notices](THIRD_PARTY_NOTICES.md).

Product names are used only to describe compatibility and workflow. This
project is independent and is not affiliated with or endorsed by the
manufacturers mentioned in the documentation. See [TRADEMARKS.md](TRADEMARKS.md).
