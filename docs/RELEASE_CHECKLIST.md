# Release Checklist

Source publication and binary distribution are separate release gates.

## Source Release

- Confirm the working tree and all reachable Git history contain no credentials,
  private paths, personal email addresses, or generated products.
- Confirm the licence and third-party notices match the JUCE version.
- Run `./scripts/verify-all.sh` from a clean checkout.
- Review the complete diff and dependency changes.
- Confirm GitHub Actions pass on the public commit.

## Binary Release

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

## Operational Validation

The release script must not finish unless signing, Apple notarisation, ticket
stapling, Gatekeeper assessment, checksums, and the final payload audit pass.
These automated gates do not replace a browser-download check on a clean Mac or
a physical controller rehearsal with the intended live template.
