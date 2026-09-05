# Contributing

Focused bug reports and pull requests are welcome.

## Before Opening A Pull Request

1. Describe the host, operating-system version, hardware controller, and exact
   failure or workflow.
2. Keep the app and VST3 independent.
3. Preserve plug-in parameter IDs, bundle identifiers, CoreMIDI identity, saved
   state, and shared-memory compatibility unless a migration is included.
4. Add or update focused tests for behavioural changes.
5. Run `./scripts/verify-all.sh` on macOS or
   `./vst3/scripts/build-windows.ps1` for Windows VST3 changes.
6. Keep generated apps, plug-ins, archives, build caches, logs, and private
   machine paths out of commits.

Normal builds must not install or replace products on the contributor's system.

By contributing, you agree that your contribution is licensed under the GNU
Affero General Public License v3.0.

For third-party builds and forks, see the
[names, logo and official-release policy](TRADEMARKS.md). AGPL-3.0 redistribution
rights remain unchanged; distinguish your build and support from the upstream
project.
