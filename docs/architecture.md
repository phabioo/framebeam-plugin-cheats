# Architecture

At a glance: the plugin keeps one cheat list per game in the plugin user store, shows it as the in-game tab "Cheats", and hands the enabled supported entries to Uzume with `fb.cheats.apply`. Uzume owns consent, the "Before cheats" copy, the run log and the run rule.

## Modules (`src/`, bundled into `plugin/main.lua`)

| Module | Job |
|---|---|
| `main` | Entry: creates and starts the controller. |
| `app.controller` | State, action routing (`fb.ui.on_action`), applying to the core, run rule, events, toasts, hotkeys, dialog flow. |
| `model.formats` | Pure: shapes, validation with error keys, detection, normalizing for `raw`, `gsa`, `cb`, `ar_gba`, `ar_ds`, `game_genie`, `gateway`. |
| `model.importer` | Pure: RetroArch `.cht` and text files (Gateway `[Name]`, plain AR/GS). |
| `model.draft` | Pure: analysis of the Enter code form (format, line errors, name). |
| `model.library` | Pure: entries, groups, names, search. |
| `model.sync` | Store key per game, normalizing, merge by cheat id, save with conflict handling. |
| `ui.panel` | The Cheats tab (design 11a). |
| `ui.dialog` | Add / import / database sheet (design 11b, 11c). |

## Contract used from Uzume

Binding contract: Uzume plan 0.20, "Verträge".

- `fb.cheats.formats()` (optional second result: core name), `apply(list)`, `clear()`, `database()`; event `fb.events.on("app", "cheats.blocked", fn)` with `reason` `run_rule` or `consent_denied`.
- `fb.store.get/put/conflicts`; key `cheats.<game code>` (fallback: hash, then title slug), value `{ v = 1, cheats = {...}, deleted = {id = true} }`.
- `textarea` block `{ id, value, lines, mono }` (change arrives as `on_action(<id>, text)`), `fb.ui.pick_file{ title, filters, max_bytes }` with callback `(content, info)`.
- Optional, used when present: `fb.ui.close("screen")`, `fb.run.current().rules.cheats` (needs the permission `run.state`; without it the run rule is learned from the event).

## Rules of the plugin

- A cheat that is on is sent in the full list at every change; the plugin never relies on the core remembering anything.
- A block by the run rule turns every cheat off in the stored list (the cheats stay listed) and shows the notice; it ends when `fb.run` shows the rule allowed or the person presses "Check again".
- Imported cheats are never turned on by the file's own enable flag.
