# Uzume Plugin: Cheats

Cheat lists per game for Uzume, applied through the cores' own cheat engines.

Status: **v0.1.1**, built against the Uzume 0.20 plugin API contract (cheats tab, add/import dialog, cheat database, per-game lists in the plugin user store); v0.1.1 fixes the findings of the package 5 live check; needs Uzume 0.20 to run.

Requires Uzume 0.20 (core cheats and the `cheats` plugin permission; [Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md)). Part of [Uzume](https://github.com/phabioo/uzume); design: [`docs/design/uzume/cheats.md`](https://github.com/phabioo/uzume/blob/main/docs/design/uzume/cheats.md), plugin API: `docs/guides/plugin-api.md` there. Plan: [docs/roadmap.md](docs/roadmap.md).

Develop: sources are modules in `src/`; `lua5.4 tools/bundle.lua` generates the committed `plugin/main.lua` (`--check` fails when stale), `lua5.4 tests/run.lua` runs the tests, `python3 tools/package.py` builds the `.fbplugin` (a tag `vX.Y.Z` releases it). Layout: [docs/architecture.md](docs/architecture.md).

Every PR description needs a `## Changelog` section (see `.github/pull_request_template.md`); CI checks it with `tools/changelog.py`, and releases should build their notes from these sections.

License: GPL-3.0-or-later, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Contributions under the [CLA](CLA.md).

Pokémon and Nintendo are trademarks of their owners. This project is not affiliated with them and contains no game content.
