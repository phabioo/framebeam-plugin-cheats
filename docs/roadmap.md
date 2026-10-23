# Roadmap

Status: planned, nothing implemented. Part of Uzume milestone 0.20 "Emulation", section "Cheats" ([Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md), design [`docs/design/uzume/cheats.md`](https://github.com/phabioo/uzume/blob/main/docs/design/uzume/cheats.md)).

## Before this plugin

These come first in Uzume and are not built here:

- Core cheats in the app (`retro_cheat_set`) and the Azahar fork connecting it to its Gateway engine.
- Run rule `rules.cheats` (owned by Uzume, not by a plugin), run log events, snapshot "Before cheats".
- Plugin API: permission `cheats`, `fb.cheats.formats()`, `fb.cheats.apply(list)`, `fb.cheats.clear()`, event `cheats.blocked`; `textarea` and `fb.ui.pick_file`; plugin user store `fb.store`.
- Cheat database on the server (libretro-database, downloaded at runtime).

## v0.1

- Generic for all games supported by Uzume; cheat lists per game (user-provided or from the server's cheat database; this repository ships no cheat lists for real games beyond synthetic examples).
- Codes go to the core through `fb.cheats.*`; `memory.write` only for raw codes a core cannot handle.
- Safety stays in Uzume: snapshot before the first cheat, run log, run rule whether cheats are allowed.
- i18n English and German; tests with synthetic data only.
