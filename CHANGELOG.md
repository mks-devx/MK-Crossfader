# Changelog

## 2026-09-02 - Initial Public Release

### MK MIDI Crossfader 0.2.8

- Native CoreMIDI bridge with A/B, layered, paired, and per-target Range modes.
- Curves, minimum levels, restore behaviour, MIDI Learn, colours, and user
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
