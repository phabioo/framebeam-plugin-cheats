# Roadmap

Status: planned, nothing implemented. Depends on FrameBeam plugin API v1 (0.11, planned); see https://github.com/phabioo/framebeam `docs/roadmap.md`.

## Planned

- Generic for all games supported by FrameBeam; cheat lists per game (user-provided; this repository ships no cheat lists for real games beyond synthetic examples).
- Applies codes through `memory.write` because Azahar's `retro_cheat_set` is empty; may use a core's `retro_cheat_set` where implemented.
- Safety: save snapshot before the first write, write queue, run log event "cheat used", run rule whether cheats are allowed.
- Starts after the SoulLink MVP.

Requires plugin API v1 (FrameBeam 0.11, planned) with `memory.write`.
