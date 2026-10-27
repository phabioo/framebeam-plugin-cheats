# Roadmap

Status: v0.1.0 implemented against the 0.20 API contract and tested with a fake `fb` only; the live check in Uzume starts when the app side (plan 0.20, package 5) is on main. Part of Uzume milestone 0.20 "Emulation", section "Cheats" ([Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md), design [`docs/design/uzume/cheats.md`](https://github.com/phabioo/uzume/blob/main/docs/design/uzume/cheats.md)).

## Before this plugin

These come first in Uzume and are not built here:

- Core cheats in the app (`retro_cheat_set`) and the Azahar fork connecting it to its Gateway engine.
- Run rule `rules.cheats` (owned by Uzume, not by a plugin), run log events, snapshot "Before cheats".
- Plugin API: permission `cheats`, `fb.cheats.formats()`, `fb.cheats.apply(list)`, `fb.cheats.clear()`, event `cheats.blocked`; `textarea` and `fb.ui.pick_file`; plugin user store `fb.store`.
- Cheat database on the server (libretro-database, downloaded at runtime).

## v0.1 (implemented)

- Generic for all games supported by Uzume; cheat lists per game (user-provided or from the server's cheat database; this repository ships no cheat lists for real games beyond synthetic examples).
- Codes go to the core through `fb.cheats.*`; `memory.write` only for raw codes a core cannot handle.
- Safety stays in Uzume: snapshot before the first cheat, run log, run rule whether cheats are allowed.
- i18n English and German; tests with synthetic data only.

Built in v0.1.0:

- Cheats tab (design 11a): header with "N ON", Add cheat, Cheat database, search, groups From the cheat database / Mine / Imported with counts, rows with name, format tag and toggle; formats the core cannot use (`fb.cheats.formats()`) stay listed, off, with "not supported by <core>"; notice and no toggles when a run rule blocks cheats; empty, no-match and after-reset states; a toast "<name> is on" with Turn off.
- Add / import dialog (11b) as the plugin's `screen` sheet: Enter code (name, format with Detect, multi-line code with per-line errors and a "looks like CodeBreaker" hint), Import file (`fb.ui.pick_file`; RetroArch `.cht`, Gateway `[Name]` and plain AR/GS `.txt`; preview with selectable rows; duplicate names get "(2)"), Cheat database (11c, `fb.cheats.database()`; states: none, off, offline, error).
- Formats `raw`, `gsa`, `cb`, `ar_gba`, `ar_ds`, `game_genie`, `gateway`: validation, detection by system, normalizing (`src/model/formats.lua`).
- Lists per game in `fb.store` key `cheats.<game code>` with revisions; on conflict both versions are merged by cheat id (deleted cheats stay deleted, a cheat changed on both sides is kept twice).
- Every toggle, edit and removal sends the full list of enabled supported cheats with `fb.cheats.apply`; hotkeys Ctrl+Alt+C (add) and Ctrl+Alt+X (all off).

Open for the live check (see the Uzume plan 0.20): exact `textarea` action naming, `fb.ui.pick_file` callback shape, `fb.cheats.database()` result shape is an assumption marked in the code; the consent dialog (11d), run rule screens (11e to 11g) and database setting (11h) belong to the app.
