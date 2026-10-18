# Brotato (decompiled) + Moolt-Lan_Coop mod

Decompiled Brotato **1.1.15.4** (`ProgressData.VERSION`). Engine **Godot 3.7** (custom build, GDScript 1, `config_version=4`). Use a Godot 3.x editor; never Godot 4 syntax.
Goal: a LAN multiplayer mod (up to 12 players, one per PC) in `mods-unpacked/Moolt-Lan_Coop/`. Implementation plan and milestones: [docs/lan-coop-plan.md](docs/lan-coop-plan.md). Keep it updated as milestones complete or the design changes.
The mod as built (files, session flow, sync protocol, extensions, pitfalls): [docs/lan-coop-mod.md](docs/lan-coop-mod.md). Keep it in step with the code. Status: Steps 1–6 done (a full wave on separate machines); Step 7 (between-wave flow) in progress: 7a–7c done, next is 7d.

## Repo layout
Two repos side by side. `brotato-lan-coop/` (public, this file lives there) holds the mod, `CLAUDE.md` and `docs/`. `Decompiled/` (local only, never published) is the vanilla game; the mod folder, `CLAUDE.md` and `docs/` are symlinked into it, so `res://mods-unpacked/Moolt-Lan_Coop/` resolves in the Godot editor. Commit mod changes in `brotato-lan-coop/`. `git status` in `Decompiled/` should stay clean; any change there is an accidental vanilla edit (often an editor re-save of an open scene).

## Rules
- **Don't edit vanilla files.** Change behaviour through ModLoader script extensions in `mods-unpacked/Moolt-Lan_Coop/extensions/<mirrored vanilla path>.gd` (`extends "res://<vanilla>.gd"`).
- Code style follows the decompiled code: tabs, `var x: = ...`, `func f() -> void :`.
- Mod code must not raise `push_error` or script errors. Any `ERROR:` log line that mentions `mods-unpacked` makes the crash reporter disable mods on the next launch (see modding.md).

## Topic docs (read only the one you need)
| Question | File |
|---|---|
| Autoloads, boot flow, scene chain, where scene paths live | [docs/brotato/architecture.md](docs/brotato/architecture.md) |
| RunData / PlayerRunData, stats, (de)serialization, run state | [docs/brotato/run-data.md](docs/brotato/run-data.md) |
| Local coop, devices, per-player input actions, movement, aim, FocusEmulator | [docs/brotato/coop-and-input.md](docs/brotato/coop-and-input.md) |
| `main.gd` wave lifecycle, end of wave, pooling, gold, pause | [docs/brotato/main-loop.md](docs/brotato/main-loop.md) |
| Wave data, enemy spawning, coop scaling, arena size, camera | [docs/brotato/spawning-and-zones.md](docs/brotato/spawning-and-zones.md) |
| Entity/Unit/Player/Enemy, targeting, weapons, projectiles, pickups, RNG | [docs/brotato/entities-and-combat.md](docs/brotato/entities-and-combat.md) |
| Menus, main menu buttons, pages, shop/upgrade UIs, translations | [docs/brotato/ui-menus.md](docs/brotato/ui-menus.md) |
| Every hardcoded 4-player array / P1–P4 node | [docs/brotato/hardcoded-4-players.md](docs/brotato/hardcoded-4-players.md) |
| ModLoader 6.3.0 API, extension rules, pitfalls | [docs/brotato/modding.md](docs/brotato/modding.md) |
| The mod itself: LanNet, LanWaveSync events/snapshot, extension list | [docs/lan-coop-mod.md](docs/lan-coop-mod.md) |

Line numbers in the docs are approximate. Grep for the function name to find the exact line.
