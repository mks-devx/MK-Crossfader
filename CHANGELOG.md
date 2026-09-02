# Changelog

## Unreleased

### Documentation

- Clarified that MK Crossfader was created primarily for live performance with
  Maschine 3 on macOS and Maschine+ hardware in Controller mode.
- Separated the Ableton Live MIDI multi-control and VST3 audio crossfading
  workflows more clearly.
- Improved setup, installer, support, compatibility, and recovery wording.
- Reorganised the main README around workflow selection, interface previews,
  installation, compatibility, and live-use guidance.

## 2026-09-03 - 0.2.9

### MK MIDI Crossfader

- Documented and manually verified Ableton Live multi-control: one physical
  fader or knob can drive several independently shaped MIDI Learn targets.
- Clarified Return Value behaviour and general MIDI Learn compatibility.
- Refined public copy, screenshots, and repository structure.

### MK Crossfader VST3

- Fixed editor interaction so role and other settings remain clickable in the
  host plug-in window.
- Added regression coverage for editor interaction.
- Documented and manually verified Controller/Target routing in Ableton Live.

### Packaging

- Bumped the app, VST3, and combined installer to 0.2.9.
- Retained the Developer ID signing, Apple notarisation, stapling, checksum,
  payload audit, and public-history privacy gates.

## 2026-09-02 - Initial Public Release

### MK MIDI Crossfader 0.2.8

- Native CoreMIDI bridge with A/B, layered, paired, and per-target Range modes.
- Curves, minimum levels, Return Value behaviour, MIDI Learn, colours, and user
  presets.
- Startup pause, mapping safeguards, controller refresh, and regression tests.
- Persistent menu-bar access, an optional Dock icon, and optional Launch at
  Login registration through macOS.
- New monochrome route-mark identity and linked creator credit.

### MK Crossfader VST3 0.2.8

- Independent Controller and Target roles with eight shared-memory sessions.
- A/B, layered, paired, and Custom Scene modes with local smoothed gain.
- Conflict detection, exact unity recovery, saved-state support, and host tests.

### Packaging

- Added a combined macOS installer pipeline for the app, VST3, licence,
  notices, and installation documentation, without preinstall or postinstall
  scripts.
- Added automated release privacy, metadata, architecture, signature, and
  network-API checks.
- Added the Developer ID signed and Apple-notarised 0.2.8 installer for the app,
  VST3, licence, notices, and setup documentation.
- Kept ad-hoc signed local-test binaries separate from public distribution.
