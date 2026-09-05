# Release Checklist

Source publication and binary distribution are separate release gates.

## Source Release

- Confirm the working tree and all reachable Git history contain no credentials,
  private paths, personal email addresses, or generated products.
- Confirm the licence and third-party notices match the JUCE version.
- Run `./scripts/verify-all.sh` from a clean checkout.
- Review the complete diff and dependency changes.
- Run `ruby scripts/tests/ci-policy.rb`. Ordinary CI must remain build/test-only,
  with read-only permissions and no package or artifact uploads.
- Confirm GitHub Actions pass on the public commit.

For Windows VST3 changes, the Windows x64 compilation, process-link,
host-loading, and plug-in tests must all pass before sharing a preview artifact.

## macOS Binary Release

- Bump and align app, plug-in, and release versions.
- Build universal release artifacts from a clean tagged commit.
- Start with a clean VST3 build directory and confirm JUCE resolves inside that
  build rather than to an unrelated local checkout.
- Run `./scripts/audit-release.sh` against the final package and review its
  expanded payload manually.
- Confirm the package contains no preinstall or postinstall scripts.
- Run Swift tests, all CTest targets, and strict plug-in validation.
- Sign release artifacts with the correct Developer ID identity and hardened
  runtime settings.
- Audit the assembled installer payload before submitting it to Apple.
- Submit the distribution artifacts for Apple notarisation and verify the
  result.
- Download the artifacts through a browser on a clean supported Mac so
  quarantine and Gatekeeper are exercised.
- Verify app launch, VST3 discovery, saved-state recall, and Controller/Target
  communication in the supported host.
- Rehearse physical controller startup, hot-plug, Return Value handling,
  conflict states, and recovery behaviour with the intended live template.
- Publish SHA-256 checksums and accurate release notes.
- Include the project licence and applicable third-party notices with the
  downloadable artifacts.
- Keep the matching source tag publicly available under the project licence.

## Windows Community Preview

- Build the exact commit on the GitHub-hosted Windows x64 runner.
- Run the DSP, state, editor, cross-process, and JUCE host-loading tests.
- Review the exact archive against a file allowlist: the VST3 bundle, setup
  instructions, licence, and required third-party notices only. Exclude debug
  symbols, source/build folders, logs, credentials, and personal configuration.
- Inspect the actual binary and archive for private paths, credentials, personal
  metadata, and unexpected contents; macOS package checks do not validate a
  Windows archive.
- Obtain explicit approval for the reviewed archive before any artifact upload
  or release publication. Passing push/PR CI does not authorise distribution.
- Publish a SHA-256 checksum with the preview archive.
- State clearly that the native MIDI Control App is not included on Windows.
- State whether the archive is signed and describe expected Windows security
  warnings accurately.
- Collect successful and failed reports through the Windows preview issue form.
- Do not describe Maschine 3, Ableton Live, or Windows as verified until a
  tester confirms the complete Controller/Target workflow and project recall.
- Require a physical Windows and DAW validation pass before promoting Windows
  support out of preview.

## macOS Operational Validation

The release script must not finish unless signing, Apple notarisation, ticket
stapling, Gatekeeper assessment, checksums, and the final payload audit pass.
These automated gates do not replace a browser-download check on a clean Mac or
a physical controller rehearsal with the intended live template.
