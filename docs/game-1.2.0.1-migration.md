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
- [x] 1. Set up `Game/1.2.0.1/Decompiled` as the new vanilla baseline:
   - `git init`, then commit it unchanged.
   - Symlink `mods-unpacked/Moolt-Lan_Coop`, `CLAUDE.md` and `docs` into it.
   - The old symlinks in `Game/1.1.15.4/Decompiled` were repointed (they were relative and dangling after the move).
- [x] 2. `tools/make_test_copy.sh`: `vanilla=$repo/../Game/1.2.0.1/Decompiled`, and drop the AT-sources merge (the DLCs are in the tree now).
   - `NO_DLC=1` became `DLCS=<ids>|none`. The project has the custom feature `gog`, so the copy runs as GOG: ownership is the marker file `<copy>/<id>.dlc`, which the script writes.
- [x] 3. `play2.sh` and `run12.sh`: the Godot path `../Godot` is unchanged (the second PC needs its own 1.2.0.1 tree for `run12.sh` when booted into Linux). The Windows test copy was rebuilt from `C:\Program Files\GOG Galaxy\Games\Brotato` (1.2.0.1, both markers).
- [x] 4. Update the paths and version in `CLAUDE.md`, `docs/testing.md` and `docs/brotato/*.md`, and the memory note for the Windows machine. README: at the release (Phase 4).
- [x] 5. `tools/lan_test_driver.gd`:
   - New enemy paths (`crash_zone/elites/rhino`, `crash_zone/basic/spitter`, `abyss/elites/giant`, `abyss/bosses/eel`), `items/all/00_base_game/...`.
   - DLC calls: `ProgressData.available_dlc_ids`, `ItemService.get_dlc_data_by_id`.
   - DLC item lists through `ItemService.update_data_list[*].item_set` instead of `dlc.items`.
   - Queue pushes as `SpawnRequest`.

## Phase 1: make it load and run (base game + Abyssal Terrors parity)
Hard breaks (script errors or a failed handshake):
- [x] 1. **DLC API** (`net/net_protocol.gd:102`, `net/run_builder.gd:42,150`):
   - Use `ProgressData.available_dlc_ids`.
   - Curse through `ItemService.get_dlc_data_by_id("abyssal_terrors")` when `"abyssal_terrors" in RunData.enabled_dlcs`, as in vanilla `base_shop.gd:~1050`.
   - Use `ItemService.can_item_be_cursed` instead of only `is_cursed` (it excludes meca and mutant items).
- [x] 2. **Moved icons:** the preload paths in `ui/ui_kit.gd:9`, `modes/lan_mode.gd:24`, `modes/boss/boss_mode.gd:23` and `extensions/main.gd:45` now point to `items/all/00_base_game/...`.
- [x] 3. **`extensions/projectiles/projectile.gd`:** `stop(from_screen_border: bool = false)` and pass the argument on.
- [x] 4. **The spawn pipeline uses `SpawnRequest`** (`global/spawn_request.gd`):
   - `extensions/global/entity_spawner.gd`: override `spawn_entity_birth(request)` and read `birth.request`.
   - `net/wave_sync.gd:~1078` `_client_birth`: build `SpawnRequest.new(type, null, pos)` plus `charmed_by`.
   - `modes/team_race/team_race_mode.gd:174-190`: use `entry.position` and a copied request.
   - `modes/send_back/send_back_mode.gd:78`: push a `SpawnRequest`.
- [x] 5. **New 4-slot arrays** (more than 4 players):
   - Grow `RunData.dino_egg_destroyed` (also after `_reset_per_wave_properties`), `main._displayed_consumables_picked_up` and `DebugService.perf_scenario_damage_added`.
   - Override `main._get_least_served_player_able_to_pick_up`, which hard-codes `[0,0,0,0]`.
- [x] 6. **`wave_sync._client_explosion`:** `player_index = -1` now reaches `RunData.get_player_effect` in `PlayerExplosion.start_explosion`. Give it a valid index and keep the fire-explosion path off on clients.
- [x] 7. **`Entity.despawn()`** emits `died` with `cleaning_up = true`, so `_on_host_entity_died` sends no die event. Send a die/remove event for despawns too.

Silent changes that affect every run:
- [x] 8. **`run_builder.apply_go`** (copied host Go logic) is stale against `base_shop.gd:393-418`:
   - Use `get_random_neutral_elite_id_hash_from_zone` and `RunData.current_wave = RunData.get_next_wave()`.
   - Add the lifeform-scanner `switch_next_elite_to_horde` loop.
- [x] 9. **`main._ready` rolls on every machine.** `RunData.apply_evolution_to_current_elite()` changes `elites_spawn` at random. Run it on the host only and send the result, or keep `elites_spawn` out of the digest until the next sync. `main._on_EndWaveTimer_timeout` also needs the new `_clear_displayed_consumables_ui()` / `set_process_input_where_defined` lines in the mod's copy.
- [x] 10. **Item pool and difficulty:** `RunData.reset()` now calls `ItemService.init_unlocked_pool()` with difficulty 0. After `apply_run`, re-init the pool, so items with a `minimum_difficulty` stay out.
- [x] 11. Title screen: the new `ItemSetButton` sits in `ButtonsLeft`. Fix the `_lan_fit_main_menu` height and the focus chain, and check with the driver's `title` role. (Checked: it fits as is, Quit ends at y 1024 of 1080 with Continue; no change.)

Found while testing Phase 1 (not in the audit):
- [x] `base_shop.gd` (vanilla) failed to parse when the mod loads it early: since 1.2.0.1 it infers a type from the `RunData` autoload, which has no type yet in mod `_init`. It is now installed in `mod_main._ready` (`READY_EXTENSIONS`); the shipped build loads it too.
- [x] The end screen's stat rows (`ui/menus/shop/stat_container.tscn`) got a `VBoxContainer` level: `extensions/ui/menus/run/end_run.gd` paths updated (script errors on every end screen before).
- [x] Test driver: a crate taken from the pool was connected twice (`picked_up` "already connected").
- [x] Engine `grab_focus` "!is_inside_tree()" in the shop (first seen with DLC_ITEMS=4): it comes from **vanilla**. Buying a weapon when every slot is taken merges it into one of the same kind (`buy_weapon` → `_combine_weapon`), and a deferred `grab_focus` then lands on a node that left the tree. Reproduced with the driver's `FULL_SLOTS` option in a session and in the `solo` role, which plays vanilla's solo flow without a session (2026-11-05). No script frame, doesn't mention the mod (the crash reporter ignores it), no effect on play.
- [x] Windows, shipped 1.2.0.1: the first `join` with a fresh APPDATA crashed natively once (exit 0xC0000005) after joining the lobby (2026-11-04). Not reproduced since: the rerun with that profile and two more joins with fresh profiles (2026-11-05) passed. Watch for it in manual tests; if it comes back, note what the player did.
- Team Race: the driver's `next_wave` digests differ by a pickup or two (gold/XP); they are logged a few seconds into the wave on each side. The run sync itself matched (no mismatch warning).

**Gate to Phase 2:** the regression set from `docs/testing.md` passes on 1.2.0.1 with `DLCS=none` and `DLCS=abyssal_terrors` (crash zone and abyss, AT bosses, curse, charm, pets), and the logs are clean.
Status 2026-11-04: the regression set passed in a copy with both DLCs: 30 cases, among them the crash zone and the Abyss, AT bosses, curse, charm, pets, `DLC_ITEMS` 0–6, Team Race and Send Back, 7 players. Also the title and lobby screenshots, a DLC-mismatch rejection, the shipped build (`quit`, `solo`), and host here + join on Windows (shipped). A copy with `DLCS=none` passed 2 waves too (no DLC sets, the remembered Abyss zone falls back to the crash zone). **Gate passed.**

## Phase 2: new base mechanics in lobby and run setup
- [x] 1. **Zones:** the lobby, settings page and `net_protocol.gd:212` list only zones with `dlc_id == ""` or `dlc_id in available_dlc_ids`, as in vanilla `zone_selection_button.gd`. Add the jungle as zone 2. `get_zone_data(id)` now looks up `my_id`. (Done: `LobbyRules.get_zones`. The jungle is selectable; Phase 3 items 1–4 are done too, so it plays, with the gaps of items 5–12.)
- [x] 2. **Item sets:**
   - The handshake also compares the active item sets (`ProgressData.active_update_data` ids), or the host's set applies to the run: `RunData.active_update_data_ids` already travels in the run state through `ProgressData.apply_run_update_data`.
   - `lobby_rules.gd` and `lobby.gd:356` refuse characters whose `required_item_set` is off (`ItemService.get_disabled_required_update`).
   - Recommendation: the host's selection rules, and clients only need to own the DLCs.
   - Done: the host's sets travel in `lobby_settings.item_sets` and apply on clients for the whole session (`LanNet._apply_host_item_sets`, own sets back in `_end_session`). Characters and starting weapons from a set that is off are left out of the lobby and refused by the host (the client gets the sets with its welcome). Driver: `ITEM_SETS_OFF=primal_dread`, `TRY_CHAR=character_droid` (with `EXPECT=2`).
- [x] 3. **Several starting weapons** (Survivor, `extra_starting_weapon_choices`): the lobby picks `1 + n` weapons, and `run_builder.gd:25-31` fills `extra_selected_weapons`. (Done: the lobby entry's `weapon_id` became `weapon_ids`, protocol version 25.)
- [x] 4. **Meca parts** (shop dismantle, meca upgrades): the shop merge carries `PlayerRunData.meca_parts`, and the in-wave snapshot carries meca parts (the HUD uses `meca_parts_changed`). Mutation fruit and meca parts icons go into `_things_to_process_player_containers`, so clients must see them too.
   - Done: the merge already carried them (the whole `PlayerRunData`); `meca_parts` is in the run digest now. Not in the snapshot: only the shop listens to `meca_parts_changed`, and the wave-end run brings the count. The icons go out as `EVENT_CRATE_TO_PROCESS`. Found on the way: clients couldn't resolve DLC consumables by id (`ItemService.consumables` has only fruit and crates), so Abyssal Terrors' poisoned fruit and all Primal Dread drops never showed on clients; `LanGame.get_consumable` looks in the DLC data too. Driver: `MECA_TEST=1`.

## Phase 3: Primal Dread in-wave sync (only with the DLC; ordered by impact)
Each item gets a driver scenario (`ZONE=2`, `SPAWN=…`, `BOSS=…`, `DLC_ITEMS`).

| Done | # | What | Problem on clients | Fix direction |
|---||---|---|---|---|
| [x] | 1 | **Holes** (jungle waves 4/10/16, `main._ready` → `_gpe_spawner.spawn_holes_full_scene()`; brachiosaurus foot stomps) | Random layout per machine. The holes are StaticBody obstacles, so movement and remote-player placement disagree | The host picks the layout and sends it with the wave start. Mid-wave holes go out as an event, and clients don't roll their own |
| [x] | 2 | **Evolved (meca/mutant) enemies** (`EvolutionSceneEffectBehavior` on host; `SpawnRequest.is_mutant/is_meca`) | No texture swap, outline or stat look | Add `is_mutant` / `is_meca` to `EVENT_SPAWN`. Clients apply texture and outline (new outline kinds in `_enemy_outlines`) |
| [x] | 3 | **GPE puddles** (acid, petrol, fire: `GPESpawner`, from evolved enemies, projectiles, burning deaths, molotov, fire trail) | Missing visuals. Client copies also spawn local puddles from `die()`/`stop()`/fire trail that hurt or burn inert copies | Block local GPE spawning on clients (extend `gpe_spawner.gd`). The host sends puddle spawn and free events with a net id, and clients show visual-only puddles |
| [x] | 4 | **Enemy time slow** (`EntityService.slow_enemy_time`: time shifter, pocket watch) | Enemies, bullets and animations at full speed; no overlay | Snapshot carries `enemy_time_factor`; clients apply it and show `ShiftTimeVisualEffect` |
| [x] | 5 | **Oviraptor/iguanodon** (`GoTowardsBorderOppositeMovementBehavior`: invisible until warning, then `despawn()`) | Invisible forever, never removed | Send visibility in the snapshot or an event. The despawn is covered by P1.7 |
| [x] | 6 | **Player bullets deflected by enemies** (pachycephalosaurus, ankylosaurus) and **boomerang** (velocity 0 at spawn, position-driven) | Client bullets fly straight on or sit still | Send a projectile redirect event, or send these projectiles' positions in the snapshot |
| [x] | 7 | **Brachiosaurus boss** (own state timer, tweened edge movement, pivots without `state_changed`, `EnemyLaser` following `_hitbox.from`, `BrachiosaurusFoot`) | Wrong spin direction, no lasers, no foot visuals, tween jitter | Dedicated handling: block the local timer and tweens, send pivots on its state change, send laser start/stop/angle, spawn the foot as an entity |
| [x] | 8 | **Player-side effects that run on clients**: fire trail (its puddles are blocked on clients since item 3), `release_spines_on_hit`, acid DoT (`update_acid_damage`), `_start_time_shift`, `on_weapon_wanted_to_spawn_structure` in `extensions/entities/units/player/player.gd` | Local spawns and damage that the host doesn't have (desync) | Turn them off on clients in the player extension, as the existing regen block does; the host's results arrive through the snapshot and events |
| [x] | 9 | **Group spawn markers** (`spawn_group_entity_birth`, `EntityGroupBirth`) | No warning marker | Hook `spawn_group_entity_birth` → `on_birth` for each position |
| [x] | 10 | **Hungry hungry dinosaur** eats fruit through `main.despawn_consumable` | Fruit stays on client floors | Send the existing item-removed event from the `despawn_consumable` override |
| [x] | 11 | **Archaeologist dig sites, poacher zones and marks** (scene effect behaviours, freed on clients) | Objectives invisible | Spawn and progress events for those objects |
| [x] | 12 | Cosmetic: velociraptor warning line, jump shadow and landing marker (dimetrodon, carnotaurus), T-rex facing and mouth anim, carbon bow textures, mosquitor and blood turret outlines, ammosaurus melee swings, jungle ground decoration (seed it from the host) | Missing or different visuals | Small events and snapshot flags; last |

Done for items 1–4 (2026-11-05, protocol version 26; driver `GPE_TEST=1` with `ZONE=2 START_WAVE=4`):
- 1: the layout is not sent but picked on every machine from `lobby_settings.wave_seed` (new random per run the host sends) and the wave (`extensions/global/gpe_spawner.gd`). It is one of 5 prepared scenes, so nothing else to send. Single holes: event 20. Whether clients ever run the brachiosaurus foot that stomps them is item 7.
- 2: the evolution happens inside the spawn, so it rides on `EVENT_SPAWN` (9th field); clients add the zone's own mutant/meca enemy effect behaviour (texture, outline), taken from `EvolutionSceneEffectBehavior` before the scene effect behaviours are freed.
- 3: events 18/19 with a puddle id. Clients get null from every `get_new_*_puddle_at_pos`, which also stops the fire trail's local puddles (part of item 8).
- 4: the snapshot header carries `enemy_time_factor` (f32, header 18 bytes).
- 5 (found in the manual test, 2026-11-05): snapshot entity flag 128 (hidden); clients also play the rustle and charge sounds and turn the copy along its path (the host's behaviour sets `rotation`). Driver: `SPAWN=res://entities/units/enemies/jungle/basic/oviraptor/oviraptor.tscn`, `log_gpe`'s `chargers`.
Items 6–11 and part of 12 (2026-11-05):
- 6: only the ankylosaurus calls `Projectile.deflect` (random side): the `projectile.gd` extension sends the new course (event 22). Light-saber deflects were already covered (vanilla stops the bullet and shoots a new one). Boomerangs: their weapon calls `start_flight(player, …)` with velocity 0, so the copy gets the flight (carrier, start, direction, reach; event 23) and flies it itself. Driver: `PROJ_TEST=1` (the host deflects one bullet a second; both log ids and angles), `ITEMS=weapon_boomerang_1`.
- 7: the brachiosaurus extension runs its state timer only on the host and reports each state (event 27, kind 0; pivots after state 1); clients don't tween it between edges (`stay_edges_of_map_movement_behavior.gd` extension), take shown/hidden and facing from the snapshot (flags 128 and 32), the mouth animation (kind 1) and the foot's sprites (kind 2, polled per tick). Its lasers (meca variant) and every meca jungle enemy's lasers get their shooter and target (event 28), so the copies follow the shooter and turn towards the target. The foot was already an entity. Driver: `BOSS=…/brachiosaurus.tscn WAVE_DURATION=50 DLC_LOG=3` (its first state comes 20 s after the spawn), `SPAWN_EVOLVE=meca` with `SPAWN=…/carnivorus_plant.tscn` for lasers; `log_gpe`'s `brachiosaurus` line.
- 8: nothing ran on clients that mattered: their players have no hurtbox, so time shift and spines only run on the host (results come as events and the snapshot), acid damage comes from the host's puddles, structures from weapon kills only on the host. Missing were the acid and petrol tints on players: snapshot player flags 2 and 4.
- 10: `main.despawn_consumable` override → event 21; the hungry hungry dinosaur's "eat" animation is synced like enemy animations.
- 11: dig sites and poacher zones are placed from the shared wave seed (`LanGame.begin_shared_random`, extensions of both scene effect behaviours). Only the host digs (`dig_site.gd` extension): event 24 on each digging/dug change with the progress; clients complete without the crate (the host drops it). Poacher zone moves (polled, event 25) and kill marks (event 26). Driver: `GPE_TEST=1 CHAR=character_archaeologist JOIN_ENV="CHAR=character_poacher"`.
- 12: the zone decoration (`generation_zone_manager.gd` extension, shared seed; `log_gpe`'s `decoration` hash). Warning lines (only `velociraptor++` has one; event 29, re-sent when the line turns) and jumps (dimetrodon, carnotaurus; event 30 at the start, clients play the shadow and landing marker over the jump's own duration) through the entity's `WarningChargingAttackBehavior` / `JumpAttackBehavior` nodes (index in subtree order). T-rex: facing through snapshot flag 32, mouth through event 27 kind 1 (the brachiosaurus' path). Percent-damage-taken outlines (blood turret, mosquitor; any colour) as event 31, the list of an enemy's outlines beyond the managed ones. Ammosaurus: its weapon's attacks as event 32 (the player weapon's swing/recoil path). Carbon bow: the host's next arrow (event 33, `carbon_bow.gd` extension) and the arrow's texture (event 34). Driver: `SPAWN=…/velociraptor++.tscn SPAWN_NEAR=1`, `BOSS=…/dimetrodon.tscn` or `…/tyranosaurus.tscn`, `ITEMS=item_ammosaurus,weapon_carbon_bow_1,item_bleeding_turret,item_mosquitor` with `WAVES=2 DLC_LOG=1`; `log_gpe`'s `visuals` line.
- Hole layouts are fixed scenes for vanilla's map sizes (`holes_old_scene` once `map_size` is nonzero); in the session's bigger arena they all lay in the top left (12 players: 6 holes within x 457–1226, y 142–851 of 2624×1984). Since 2026-11-05 the hole positions stretch by arena size / vanilla size (`gpe_spawner.gd`, `ZoneService.lan_vanilla_zone_size`). Other arena-size checks: the edge swarms, the oviraptor charges, the brachiosaurus (edges from the entity's own bounds), bullet hells (anchored to the zone, repeated over its size), dig sites, poacher zones, decoration and the fog (camera-relative) all follow the arena already. `log_gpe`'s `arena` line logs the arena and the holes' span.

Abyssal Terrors enemies (moved to `entities/units/enemies/abyss/`) and the old base enemies (`crash_zone/`) are mostly unchanged. The lung, stargazer, eel and anglerfish handling still matches, so they only need a regression run.

## Phase 4: release
- [ ] Manifest: `compatible_game_version: ["1.2.0.1"]`, `version_number` 2.0.0 (the protocol version went up to 25 in Phase 2; old clients are rejected by the game version anyway).
- [ ] Docs: `lan-coop-mod.md` (SpawnRequest, GPE, evolution, item sets), `lan-coop-plan.md` checklist, README.
- [ ] Full playtests: Linux plus Windows (GOG 1.2.0.1); jungle zone with Primal Dread for both; one peer without a DLC → reject message.

## Verification (per phase)
- `tools/make_test_copy.sh` from 1.2.0.1, then the driver's `quit` role (parse errors) and `title` role (menu layout).
- Phase 1: `host`/`join` with `WAVES=2`, `MODE=…` for team_race and send_back, `FAKES=6` (more than 4 players), and `ZONE=1` with `CURSE_TEST`/`CHARM_TEST`/`BOSS=abyss/bosses/eel`. Log check: no `SCRIPT ERROR` or `ERROR:` mentioning `mods-unpacked`. `log_run_check` digests match.
- Phase 3: `ZONE=2 START_WAVE=4` (holes), `SPAWN=…jungle/...`, the brachiosaurus and tyrannosaurus `BOSS=`, and `DLC_ITEMS` for Primal Dread items (the driver's item list from the item sets). Compare `log_sync` on both sides and take screenshots.
- After each feature, the user tests by hand in two windows; commit only after their OK.

## Proposed split into sessions
- [ ] 1. Phase 0 + Phase 1: the mod runs again on 1.2.0.1 without Primal Dread content. A release can follow straight away so players can use the base game and AT again.
- [x] 2. Phase 2: lobby, zones, item sets, extra weapons, meca parts.
- [x] 3. Phase 3 items 1–4 (holes, evolution, puddles, time slow): the jungle becomes playable.
- [x] 4. Phase 3 items 5–12: enemy and boss specifics, and polish.
