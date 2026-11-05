# Brotato (decompiled) + Moolt-Lan_Coop mod

Decompiled Brotato **1.2.0.1** (`ProgressData.VERSION`), with both DLCs (Abyssal Terrors, Primal Dread) in its sources. Engine **Godot 3.7** (custom build, GDScript 1, `config_version=4`). Use a Godot 3.x editor; never Godot 4 syntax.
Goal: a LAN multiplayer mod (up to 12 players, one per PC) in `mods-unpacked/Moolt-Lan_Coop/`. Goals, design decisions and the open-work checklists: [docs/lan-coop-plan.md](docs/lan-coop-plan.md). Tick items there as they are done and add new gaps or todos as they come up.
The mod as built (files, session flow, sync protocol, extensions, pitfalls): [docs/lan-coop-mod.md](docs/lan-coop-mod.md). Keep it in step with the code. Status: Steps 1–7 done (full runs on separate machines: waves, upgrades and shop per machine, end screens). Step 8 (polish: visuals, controls, menus, perf, tests) is in progress: its in-wave part is done (8a: off-screen arrows, skulls, mouse aim) except name overlap, and the lobby layout (8b). Step 9 collects feature additions; game modes (a mode layer and seven modes, [docs/lan-coop-modes.md](docs/lan-coop-modes.md)) are built but not playtested yet.

**In progress (branch `game-1.2.0.1`): porting to Brotato 1.2.0.1 and the Primal Dread DLC; 1.1.15.4 is no longer supported (last supported at tag `last-1.1.15.4`). Findings and checklist: [docs/game-1.2.0.1-migration.md](docs/game-1.2.0.1-migration.md).**

## Repo layout
Side by side under `brotato-multiplayer/`: `brotato-lan-coop/` (public, this file lives there) holds the mod, `CLAUDE.md` and `docs/`. `Game/` (local only, never published) holds each game version: `Game/<version>/Brotato/` the GOG install, `Game/<version>/Decompiled/` its decompiled project (GDRE). **`Game/1.2.0.1/Decompiled/` is the vanilla baseline**: the mod folder, `CLAUDE.md` and `docs/` are symlinked into it, so `res://mods-unpacked/Moolt-Lan_Coop/` resolves in the Godot editor. Commit mod changes in `brotato-lan-coop/`. `git status` in that `Decompiled/` should stay clean; any change there is an accidental vanilla edit (often an editor re-save of an open scene). `Game/1.1.15.4/` (with `BrotatoAbyssalTerrors_Decompiled/`) is the old version, for reference only. `Godot/` has the Godot 3.7 binary.
Since 1.2.0.1 the DLCs are inside the main `Brotato.pck` (`dlcs/dlc_1`, `dlcs/dlc_2`, and DLC content in base folders such as `zones/zone_3_jungle`, `entities/units/enemies/jungle`); owning one is a marker file `<id>.dlc` next to the exe on GOG, `isDLCInstalled` on Steam ([docs/brotato/architecture.md](docs/brotato/architecture.md)).

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
| The mod itself: LanNet, lobby, scaling, LanWaveSync events/snapshot, between-wave flow (solo view, shop, merge), game modes (hooks, state, each mode's rules), extension list, pitfalls | [docs/lan-coop-mod.md](docs/lan-coop-mod.md) |
| Game modes beyond co-op: ideas, effort, how to keep them isolated, order | [docs/lan-coop-modes.md](docs/lan-coop-modes.md) |
| Testing: throwaway game copy, test driver roles and options, regression set, log check | [docs/testing.md](docs/testing.md) |

Line numbers in the docs are approximate. Grep for the function name to find the exact line.
