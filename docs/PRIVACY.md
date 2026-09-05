# Privacy

MK Crossfader has no analytics, telemetry, accounts, advertising, background
update service, or automatic network communication.

## MK MIDI Crossfader

The app reads the names and CoreMIDI identifiers of locally connected MIDI
devices so a controller can be selected. Configuration, target names, presets,
colours, and MIDI assignments are stored locally in macOS user defaults under
the app's bundle identifier. Nothing is uploaded.

The app does not record or transmit audio.

The app accesses the network only when the user selects **Check for Updates**.
That action sends HTTPS requests to GitHub's public Releases API containing a
standard app name and version user-agent. It does not send MIDI data, audio,
settings, target names, controller details, or a persistent identifier. GitHub
receives normal connection metadata such as the user's IP address. The app does
not check in the background or automatically download or install anything.

From 0.3.1, the updater reads up to ten release-list pages per manual check.
It checks installer and checksum attachment metadata without downloading those
files. Including testing prereleases is optional and does not enable background
checks or transmit extra personal information.

If **Launch at Login** is enabled, the app registers itself with macOS through
`SMAppService`. It does not install a helper process, background daemon, or
separate login item. Disabling the option unregisters the app from macOS login
items.

## MK Crossfader VST3

Plug-in parameters and route names are stored by the host as part of the
project or preset state. Controller and Target instances exchange current
values through local shared memory on the same computer. macOS uses per-user
POSIX shared memory; Windows uses a named mapping limited to the current login
session. Neither transport is a network service.

The plug-in processes audio in memory and does not write recordings or sample
content to disk. The VST3 never checks for updates and does not access the
network.

## Repository

The public source tree excludes machine-specific dependency paths, credentials,
private project records, generated build products, and personal contact
details. Report a privacy or security concern using the process in
[SECURITY.md](../SECURITY.md).
