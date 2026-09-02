# Privacy

MK Crossfader has no analytics, telemetry, accounts, advertising, update
service, or network communication.

## MK MIDI Crossfader

The app reads the names and CoreMIDI identifiers of locally connected MIDI
devices so a controller can be selected. Configuration, target names, presets,
colours, and MIDI assignments are stored locally in macOS user defaults under
the app's bundle identifier. Nothing is uploaded.

The app does not record or transmit audio.

If **Launch at Login** is enabled, the app registers itself with macOS through
`SMAppService`. It does not install a helper process, background daemon, or
separate login item. Disabling the option unregisters the app from macOS login
items.

## MK Crossfader VST3

Plug-in parameters and route names are stored by the host as part of the
project or preset state. Controller and Target instances exchange current
values through per-user shared memory on the same Mac. That shared memory is
not a network service and is not used after the processes stop.

The plug-in processes audio in memory and does not write recordings or sample
content to disk.

## Repository

The public source tree excludes machine-specific dependency paths, credentials,
private project records, generated build products, and personal contact
details. Report a privacy or security concern using the process in
[SECURITY.md](../SECURITY.md).
