# Changelog

## Unreleased

### MK MIDI Crossfader

- Fixed variable-length and batched MIDI input parsing, including partial
  controller messages and running status across callbacks.
- Cancelled pending Send Learn pulses safely when mappings, presets, routing,
  or activation change, and during normal termination.
- Made malformed release versions produce a recoverable update-check error.

- Increased the contrast of each Send Learn action and strengthened its icon so
  it remains easy to identify in dense target lists.
- Made the main MIDI Learn action visually distinct from secondary controls and
  clarified why it may be unavailable.
- Replaced mapping-changing built-in presets with additive A/B Crossfade Pair,
  Parameter Range, and Level Target actions.
- Kept saved presets separate as complete user-created configuration snapshots.

### MK Crossfader VST3

- Made ownership and heartbeat updates atomic and tied gain frames to their
  current owner, preventing stale-frame reuse during Controller replacement.
- Versioned the internal link protocol; linked instances must use the same
  version after upgrading. Saved plug-in state remains compatible.
- Added ownership, handover, clock-wrap and concurrent frame integrity tests.
- Made the Windows build script stop on failed native commands or a missing
  plug-in bundle.

- Added a Windows x64 shared-memory transport for linked Controller and Target
  instances.
- Added Windows compilation, process-link, host-loading, and plug-in test gates
  to continuous integration.

### Packaging

- Added source privacy preflight before signing, including untracked source
  files, and regression checks for private-path and credential detection.
- Included an offline setup index and the Maschine and Ableton setup manuals.
- Added an explicit unsigned local-test installer mode for uncommitted changes.
- Required signing and notarisation configuration before a release build can
  begin; incomplete release configuration no longer produces a package.

- Removed local Swift build paths from the release app executable before
  signing.
- Strengthened release auditing to inspect raw executable data for private
  paths, credentials, and inappropriate provenance metadata.

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
