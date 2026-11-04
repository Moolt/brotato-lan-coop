# Migration to Brotato 1.2.0.1 (+ Primal Dread)

Work happens on the branch `game-1.2.0.1`. The tag `last-1.1.15.4` marks the last commit that supports 1.1.15.4 (Release 1.12.3). Tick items as they are done.

## Context
Brotato 1.2.0.1 shipped together with the Primal Dread DLC. The mod (1.12.3) was built against 1.1.15.4 + Abyssal Terrors. This was found by diffing `Game/1.1.15.4/Decompiled` against `Game/1.2.0.1/Decompiled` for every extended vanilla file and every vanilla API the mod uses, and by cataloguing the new in-wave mechanics.

**Verdict: the mod does not work on 1.2.0.1, even without any DLC.** Nobody can join: the handshake calls `ProgressData.get_active_dlc_ids()`, which was removed. Four scripts fail to load because the item icons they preload moved, and two extensions no longer match the vanilla function signatures, so they fail to parse. After those are fixed, the base game and Abyssal Terrors are expected to be mostly fine. Primal Dread adds a lot that runs only on the host, or randomly on each machine, and needs new sync.

### How DLCs ship now
- `Brotato.pck` (281 MB) is the same for everyone and contains the base game and both DLCs (`dlcs/dlc_1`, `dlcs/dlc_2`, plus DLC content in base folders: `zones/zone_3_jungle`, `entities/units/enemies/jungle`, `items/all/04_primal_dread`, …).
- Ownership: on GOG it is a marker file `<id>.dlc` next to the exe (`AbstractPlatform._has_dlc_marker`), and the DLC installers are about 6 MB (markers plus icons). On Steam it is `isDLCInstalled`. Someone without a DLC has the same pck and just no marker.
- `ProgressData.available_dlc_ids` holds the owned DLCs (`"primal_dread"`, `"abyssal_terrors"`). Zones carry a `dlc_id`. Items, characters and weapons come in **item sets** (`updates/item_sets/*.tres`) that players can switch off in a new main-menu page (`deactivated_update_data`). A run stores them in `RunData.active_update_data_ids`.
- ModLoader is still 6.3.0 and the autoloads are unchanged. The exe is the same 3.7.dev custom build, so the `Godot_v3.7-dev1` editor still fits.

## Decision
**Support only 1.2.0.1 from now on** (decided 2026-11-04). Steam and GOG update automatically, and code for both versions would double every spawn and DLC path. The old version stays in `Game/1.1.15.4` for reference. The handshake already rejects a different game version.

---

## Phase 0: workspace and tooling (no gameplay changes)
- [x] 0. Bookkeeping (first, before any code change):
   - Tag the current `master` commit (`eead844`, Release 1.12.3) as `last-1.1.15.4` (local, not pushed: a pushed tag may trigger the release CI).
   - Create the branch `game-1.2.0.1` from it; all work below happens there.
   - This file, linked from `CLAUDE.md` and `docs/lan-coop-plan.md`.
- [ ] 1. Set up `Game/1.2.0.1/Decompiled` as the new vanilla baseline:
   - `git init`, then commit it unchanged.
   - Symlink `mods-unpacked/Moolt-Lan_Coop`, `CLAUDE.md` and `docs` into it.
   - The old symlinks in `Game/1.1.15.4/Decompiled` are relative and now dangling; repoint them or leave them.
- [ ] 2. `tools/make_test_copy.sh`: `vanilla=$repo/../Game/1.2.0.1/Decompiled`, and drop the AT-sources merge (the DLCs are in the tree now).
   - `NO_DLC=1` becomes per-DLC ownership. The test copy runs on the Local platform, where ownership is `DebugService.owned_dlc_ids` (an export defaulting to both). Set it with `DLCS=abyssal_terrors,primal_dread|none` in the copy's `debug_service.tscn`, or through the driver.
- [ ] 3. `play2.sh` and `run12.sh`: change the Godot path to `../Godot` (unchanged location) and check the defaults. `win_run.ps1` and the Windows test copy: rebuild from `C:\Program Files\GOG Galaxy\Games\Brotato` (1.2.0.1, both markers).
- [ ] 4. Update the paths and version in `CLAUDE.md`, `docs/testing.md` and `docs/brotato/*.md`, and the memory note for the Windows machine.
- [ ] 5. `tools/lan_test_driver.gd`:
   - New enemy paths (`crash_zone/elites/rhino`, `crash_zone/basic/spitter`, `abyss/elites/giant`, `abyss/bosses/eel`), `items/all/00_base_game/...`.
   - DLC calls: `ProgressData.available_dlc_ids`, `ItemService.get_dlc_data_by_id`.
   - DLC item lists through `ItemService.update_data_list[*].item_set` instead of `dlc.items`.
   - Queue pushes as `SpawnRequest`.

## Phase 1: make it load and run (base game + Abyssal Terrors parity)
Hard breaks (script errors or a failed handshake):
- [ ] 1. **DLC API** (`net/net_protocol.gd:102`, `net/run_builder.gd:42,150`):
   - Use `ProgressData.available_dlc_ids`.
   - Curse through `ItemService.get_dlc_data_by_id("abyssal_terrors")` when `"abyssal_terrors" in RunData.enabled_dlcs`, as in vanilla `base_shop.gd:~1050`.
   - Use `ItemService.can_item_be_cursed` instead of only `is_cursed` (it excludes meca and mutant items).
- [ ] 2. **Moved icons:** the preload paths in `ui/ui_kit.gd:9`, `modes/lan_mode.gd:24`, `modes/boss/boss_mode.gd:23` and `extensions/main.gd:45` now point to `items/all/00_base_game/...`.
- [ ] 3. **`extensions/projectiles/projectile.gd`:** `stop(from_screen_border: bool = false)` and pass the argument on.
- [ ] 4. **The spawn pipeline uses `SpawnRequest`** (`global/spawn_request.gd`):
   - `extensions/global/entity_spawner.gd`: override `spawn_entity_birth(request)` and read `birth.request`.
   - `net/wave_sync.gd:~1078` `_client_birth`: build `SpawnRequest.new(type, null, pos)` plus `charmed_by`.
   - `modes/team_race/team_race_mode.gd:174-190`: use `entry.position` and a copied request.
   - `modes/send_back/send_back_mode.gd:78`: push a `SpawnRequest`.
- [ ] 5. **New 4-slot arrays** (more than 4 players):
   - Grow `RunData.dino_egg_destroyed` (also after `_reset_per_wave_properties`), `main._displayed_consumables_picked_up` and `DebugService.perf_scenario_damage_added`.
   - Override `main._get_least_served_player_able_to_pick_up`, which hard-codes `[0,0,0,0]`.
- [ ] 6. **`wave_sync._client_explosion`:** `player_index = -1` now reaches `RunData.get_player_effect` in `PlayerExplosion.start_explosion`. Give it a valid index and keep the fire-explosion path off on clients.
- [ ] 7. **`Entity.despawn()`** emits `died` with `cleaning_up = true`, so `_on_host_entity_died` sends no die event. Send a die/remove event for despawns too.

Silent changes that affect every run:
- [ ] 8. **`run_builder.apply_go`** (copied host Go logic) is stale against `base_shop.gd:393-418`:
   - Use `get_random_neutral_elite_id_hash_from_zone` and `RunData.current_wave = RunData.get_next_wave()`.
   - Add the lifeform-scanner `switch_next_elite_to_horde` loop.
- [ ] 9. **`main._ready` rolls on every machine.** `RunData.apply_evolution_to_current_elite()` changes `elites_spawn` at random. Run it on the host only and send the result, or keep `elites_spawn` out of the digest until the next sync. `main._on_EndWaveTimer_timeout` also needs the new `_clear_displayed_consumables_ui()` / `set_process_input_where_defined` lines in the mod's copy.
- [ ] 10. **Item pool and difficulty:** `RunData.reset()` now calls `ItemService.init_unlocked_pool()` with difficulty 0. After `apply_run`, re-init the pool, so items with a `minimum_difficulty` stay out.
- [ ] 11. Title screen: the new `ItemSetButton` sits in `ButtonsLeft`. Fix the `_lan_fit_main_menu` height and the focus chain, and check with the driver's `title` role.

**Gate to Phase 2:** the regression set from `docs/testing.md` passes on 1.2.0.1 with `DLCS=none` and `DLCS=abyssal_terrors` (crash zone and abyss, AT bosses, curse, charm, pets), and the logs are clean.

## Phase 2: new base mechanics in lobby and run setup
- [ ] 1. **Zones:** the lobby, settings page and `net_protocol.gd:212` list only zones with `dlc_id == ""` or `dlc_id in available_dlc_ids`, as in vanilla `zone_selection_button.gd`. Add the jungle as zone 2. `get_zone_data(id)` now looks up `my_id`.
- [ ] 2. **Item sets:**
   - The handshake also compares the active item sets (`ProgressData.active_update_data` ids), or the host's set applies to the run: `RunData.active_update_data_ids` already travels in the run state through `ProgressData.apply_run_update_data`.
   - `lobby_rules.gd` and `lobby.gd:356` refuse characters whose `required_item_set` is off (`ItemService.get_disabled_required_update`).
   - Recommendation: the host's selection rules, and clients only need to own the DLCs.
- [ ] 3. **Several starting weapons** (Survivor, `extra_starting_weapon_choices`): the lobby picks `1 + n` weapons, and `run_builder.gd:25-31` fills `extra_selected_weapons`.
- [ ] 4. **Meca parts** (shop dismantle, meca upgrades): the shop merge carries `PlayerRunData.meca_parts`, and the in-wave snapshot carries meca parts (the HUD uses `meca_parts_changed`). Mutation fruit and meca parts icons go into `_things_to_process_player_containers`, so clients must see them too.

## Phase 3: Primal Dread in-wave sync (only with the DLC; ordered by impact)
Each item gets a driver scenario (`ZONE=2`, `SPAWN=…`, `BOSS=…`, `DLC_ITEMS`).

| Done | # | What | Problem on clients | Fix direction |
|---||---|---|---|---|
| [ ] | 1 | **Holes** (jungle waves 4/10/16, `main._ready` → `_gpe_spawner.spawn_holes_full_scene()`; brachiosaurus foot stomps) | Random layout per machine. The holes are StaticBody obstacles, so movement and remote-player placement disagree | The host picks the layout and sends it with the wave start. Mid-wave holes go out as an event, and clients don't roll their own |
| [ ] | 2 | **Evolved (meca/mutant) enemies** (`EvolutionSceneEffectBehavior` on host; `SpawnRequest.is_mutant/is_meca`) | No texture swap, outline or stat look | Add `is_mutant` / `is_meca` to `EVENT_SPAWN`. Clients apply texture and outline (new outline kinds in `_enemy_outlines`) |
| [ ] | 3 | **GPE puddles** (acid, petrol, fire: `GPESpawner`, from evolved enemies, projectiles, burning deaths, molotov, fire trail) | Missing visuals. Client copies also spawn local puddles from `die()`/`stop()`/fire trail that hurt or burn inert copies | Block local GPE spawning on clients (extend `gpe_spawner.gd`). The host sends puddle spawn and free events with a net id, and clients show visual-only puddles |
| [ ] | 4 | **Enemy time slow** (`EntityService.slow_enemy_time`: time shifter, pocket watch) | Enemies, bullets and animations at full speed; no overlay | Snapshot carries `enemy_time_factor`; clients apply it and show `ShiftTimeVisualEffect` |
| [ ] | 5 | **Oviraptor/iguanodon** (`GoTowardsBorderOppositeMovementBehavior`: invisible until warning, then `despawn()`) | Invisible forever, never removed | Send visibility in the snapshot or an event. The despawn is covered by P1.7 |
| [ ] | 6 | **Player bullets deflected by enemies** (pachycephalosaurus, ankylosaurus) and **boomerang** (velocity 0 at spawn, position-driven) | Client bullets fly straight on or sit still | Send a projectile redirect event, or send these projectiles' positions in the snapshot |
| [ ] | 7 | **Brachiosaurus boss** (own state timer, tweened edge movement, pivots without `state_changed`, `EnemyLaser` following `_hitbox.from`, `BrachiosaurusFoot`) | Wrong spin direction, no lasers, no foot visuals, tween jitter | Dedicated handling: block the local timer and tweens, send pivots on its state change, send laser start/stop/angle, spawn the foot as an entity |
| [ ] | 8 | **Player-side effects that run on clients**: fire trail, `release_spines_on_hit`, acid DoT (`update_acid_damage`), `_start_time_shift`, `on_weapon_wanted_to_spawn_structure` in `extensions/entities/units/player/player.gd` | Local spawns and damage that the host doesn't have (desync) | Turn them off on clients in the player extension, as the existing regen block does; the host's results arrive through the snapshot and events |
| [ ] | 9 | **Group spawn markers** (`spawn_group_entity_birth`, `EntityGroupBirth`) | No warning marker | Hook `spawn_group_entity_birth` → `on_birth` for each position |
| [ ] | 10 | **Hungry hungry dinosaur** eats fruit through `main.despawn_consumable` | Fruit stays on client floors | Send the existing item-removed event from the `despawn_consumable` override |
| [ ] | 11 | **Archaeologist dig sites, poacher zones and marks** (scene effect behaviours, freed on clients) | Objectives invisible | Spawn and progress events for those objects |
| [ ] | 12 | Cosmetic: velociraptor warning line, jump shadow and landing marker (dimetrodon, carnotaurus), T-rex facing and mouth anim, carbon bow textures, mosquitor and blood turret outlines, ammosaurus melee swings, jungle ground decoration (seed it from the host) | Missing or different visuals | Small events and snapshot flags; last |

Abyssal Terrors enemies (moved to `entities/units/enemies/abyss/`) and the old base enemies (`crash_zone/`) are mostly unchanged. The lung, stargazer, eel and anglerfish handling still matches, so they only need a regression run.

## Phase 4: release
- [ ] Manifest: `compatible_game_version: ["1.2.0.1"]`, `version_number` 2.0.0 (the protocol version goes up; old clients are rejected by the game version anyway).
- [ ] Docs: `lan-coop-mod.md` (SpawnRequest, GPE, evolution, item sets), `lan-coop-plan.md` checklist, README.
- [ ] Full playtests: Linux plus Windows (GOG 1.2.0.1); jungle zone with Primal Dread for both; one peer without a DLC → reject message.

## Verification (per phase)
- `tools/make_test_copy.sh` from 1.2.0.1, then the driver's `quit` role (parse errors) and `title` role (menu layout).
- Phase 1: `host`/`join` with `WAVES=2`, `MODE=…` for team_race and send_back, `FAKES=6` (more than 4 players), and `ZONE=1` with `CURSE_TEST`/`CHARM_TEST`/`BOSS=abyss/bosses/eel`. Log check: no `SCRIPT ERROR` or `ERROR:` mentioning `mods-unpacked`. `log_run_check` digests match.
- Phase 3: `ZONE=2 START_WAVE=4` (holes), `SPAWN=…jungle/...`, the brachiosaurus and tyrannosaurus `BOSS=`, and `DLC_ITEMS` for Primal Dread items (the driver's item list from the item sets). Compare `log_sync` on both sides and take screenshots.
- After each feature, the user tests by hand in two windows; commit only after their OK.

## Proposed split into sessions
- [ ] 1. Phase 0 + Phase 1: the mod runs again on 1.2.0.1 without Primal Dread content. A release can follow straight away so players can use the base game and AT again.
- [ ] 2. Phase 2: lobby, zones, item sets, extra weapons, meca parts.
- [ ] 3. Phase 3 items 1–4 (holes, evolution, puddles, time slow): the jungle becomes playable.
- [ ] 4. Phase 3 items 5–12: enemy and boss specifics, and polish.
