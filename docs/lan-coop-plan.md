# Brotato LAN Co-op Mod (Moolt-Lan_Coop): Implementation Plan

## Context
Brotato 1.1.15.4 (Godot **3.7**, decompiled; ModLoader **6.3.0**, which has no hook system, only `install_script_extension` / `take_over_path`) ships local couch co-op for up to 4 players. The goal is a LAN mod with these features:
- up to 12 players, one per machine
- keyboard and gamepad support
- host/join by IP from a new "Multiplayer" main-menu button
- player names
- a lobby that lists every player, with character select and ready-up
- a larger arena
- more enemies as player count grows

To keep later chats small, a set of context docs about how Brotato is built is written first.

Decisions already made:
- **One player per PC.**
- **Each player does level-ups and shop on their own screen.** The host waits until all players are done.
- **Docs go in a `CLAUDE.md` index plus `docs/brotato/*.md` topic files.**

Core architecture (from exploration):
- **Host-authoritative state sync.** Lockstep is not possible: RNG is spread over 250+ call sites using global `randf`/`rand_range`, and physics is RigidBody2D.
- **The host runs the real game as a vanilla coop run with N players.**
- **Clients run `main.tscn` in "puppet mode".** They send their inputs and render snapshots.
- **Between waves, every peer runs the *solo* upgrade/shop UI on a 1-player RunData.** It then sends its `PlayerRunData` back to the host. This avoids the coop UIs, which are hardcoded to 4 slots.

---

## Step 0: Context docs (do first)
Create `CLAUDE.md` as a short index: the engine version, how to run, how mod extensions work, and pitfalls. It links to these topic files:

| File | Covers |
|---|---|
| `docs/brotato/architecture.md` | autoload list/order, boot flow (`pause.tscn` is the splash screen) → title → char select → weapon → difficulty → `main.tscn` → shop loop, `MenuData` scene paths |
| `docs/brotato/run-data.md` | `RunData.players_data`, `PlayerRunData` (`serialize`/`deserialize`), stats stored in the `effects` dict by `Keys.*_hash`, `get_state`/`resume_from_state`, signals |
| `docs/brotato/coop-and-input.md` | `CoopService.connected_players`, device remap (6/7), `<action>_<dev>` actions from `InputService._copy_device_actions`, `PlayerMovementBehavior`, `Utils.get_player_rjoy_vector`, FocusEmulator |
| `docs/brotato/main-loop.md` | `main.gd` wave lifecycle (`_ready` → `_on_WaveTimer_timeout` → `clean_up_room` → `_on_EndWaveTimer_timeout`), pooling, gold split, pause |
| `docs/brotato/spawning-and-zones.md` | WaveData/WaveGroupData/WaveUnitData, `WaveManager`, `EntitySpawner.on_group_spawn_timing_reached`, coop scaling factors, `ZoneService` arena size, camera |
| `docs/brotato/entities-and-combat.md` | Entity→Unit→Player/Enemy hierarchy, targeting, `WeaponService.spawn_projectile`, items/pickups, EntityService HP/damage factors |
| `docs/brotato/ui-menus.md` | `Menus.switch`, main menu buttons, `MyMenuButton`, page template (`menu_credits.gd`), shop/upgrade UIs, translations (`tr`, `Text.text`, runtime `Translation`) |
| `docs/brotato/hardcoded-4-players.md` | full list of 4-slot arrays and P1–P4 nodes (already collected) |
| `docs/brotato/modding.md` | ModLoader 6.3 API, extension rules (callbacks run at every inheritance level, no `class_name`, only autoloads after ModLoader can be extended), the crash-recovery trap that disables mods after any `ERROR:` in `mods-unpacked` |

Content comes from the three exploration reports, checked against the source as it is written.

---

## Mod layout: `mods-unpacked/Moolt-Lan_Coop/`
- **Fix `mod_main.gd` first.** `ext_dir` must be `get_unpacked_dir().plus_file("Moolt-Lan_Coop/extensions")`. The current `AUTHOR + "-" + MOD_NAME` resolves to a non-existent folder.
- `mod_main.gd` then does three things:
  1. installs the extensions
  2. registers runtime `Translation`s (en + de) for new keys such as `MENU_MULTIPLAYER`
  3. adds `LanNet` to `/root` with `call_deferred`
```
net/net_manager.gd     # /root/LanNet: ENet peer, peers, lobby state, RPCs, session flags (is_host/is_client/active)
net/net_protocol.gd    # message ids, version handshake, StreamPeerBuffer pack/unpack helpers
net/net_input.gd       # per-player latest input (move Vector2, aim Vector2, aim_mode) on host; local sampling on client
net/host_sync.gd       # child of main on host: assigns net ids, builds snapshots (20 Hz) + events
net/client_sync.gd     # child of main on client: applies snapshots, spawns/updates/frees puppets, interpolation
net/net_config.gd      # user://lan_coop.cfg: last name, last IP, port, scaling knobs
ui/multiplayer_menu.tscn/.gd  # name LineEdit, IP LineEdit, port, Host / Join / Back
ui/lobby.tscn/.gd              # player list, character grid, weapon pick, ready toggle, host: zone/difficulty/Start
ui/net_player_list.tscn/.gd    # in-wave compact HUD: name + HP bar per other player; "waiting for X" in shop
extensions/...                 # mirrored vanilla paths (below)
```

---

## Step 1: Networking core (`LanNet`)
- **Transport.** Godot 3 high-level multiplayer: `NetworkedMultiplayerENet`, `create_server(port=24567, max_clients=11)`, `create_client(ip, port)`, `get_tree().network_peer`. Every RPC goes through the `LanNet` node, which has the same path on all peers.
- **Handshake (client → host).** The client sends `{mod_version, game_version=ProgressData.VERSION, active DLC ids, name}`. The host rejects the client if the versions or DLC set differ, the lobby is full, or a run is already in progress. If accepted, the host assigns a `player_index` (host = 0) and broadcasts the lobby state.
- **Lobby state.** For each peer: `{peer_id, player_index, name, character_id, weapon_id, ready}`. The host also sets `zone` and `difficulty`.
- **Unlocks.** The host sends its unlocked character/weapon/item lists. For the session, clients use the host's lists:
  - temporarily override the `ProgressData.*_unlocked` arrays
  - block `ProgressData` saves while a session is active
  - restore the client's own lists on leave

  This keeps item pools the same on every machine.
- **Disconnects.**
  - Client drops in the lobby: remove it from the list.
  - Client drops during a wave: the host kills that player.
  - Client drops between waves: the host drops them from the merge.
  - Host drops: clients return to the title screen and see a popup.

## Step 2: Main menu entry
- **Extend `ui/menus/title_screen/title_screen_menus.gd`.** In `_ready()`:
  1. Instance `multiplayer_menu.tscn` and `lobby.tscn` as hidden children.
  2. Create a `Button` with the script `res://ui/menus/global/my_menu_button.gd` and text `MENU_MULTIPLAYER`.
  3. Insert it into `_main_menu.left_container` right after StartButton.
  4. Set its `focus_neighbour_left/right` to `ModsButton`.
  5. Wire it with `switch(_main_menu, mp_menu)`.
- **Pages.** Each page follows the `menu_credits.gd` pattern: an `init()` that grabs focus, `ui_cancel` goes back, and a `back_button_pressed` signal. Native Godot focus gives gamepad navigation.
- **Name and IP text entry.**
  - **Name:** a LineEdit with a default of "Player" plus a random number. The name is saved in `net_config`, so a gamepad-only player can skip typing.
  - **IP:** the last IP is remembered.
  - **Gamepad input:** add a small on-screen digit pad for the IP field.

## Step 3: Lobby
- **Layout.**
  - **Left:** list of all joined players. Each row shows name, colour, chosen character icon, and ready check.
  - **Right:** the local player's character grid.
    - Reuse the icon and lock logic from `ui/menus/run/base_selection.gd`: `ItemService.characters` filtered by unlocks.
    - Build a simple GridContainer of buttons instead of subclassing the 4-slot `CharacterSelection`.
  - **Below the grid:** a starting-weapon picker. It uses the character's starting weapons with the same filter as `weapon_selection.gd:90`.
  - **Host only:** zone and difficulty pickers, plus a Start button.
- **Ready logic.**
  - Changing character un-readies the player.
  - Start is enabled only when every player has a character and a weapon and is ready.
  - Every change is sent to the host, which re-broadcasts the lobby state.
- **Starting the run (host).**
  1. `RunData.reset()`, `set_player_count(n, true)`, `set_coop_run(true)`, set zone and difficulty.
  2. For each player: `add_character`, then `add_weapon/add_item(…, true)`.
  3. `add_starting_items_and_weapons()`, then apply difficulty effects to every player. Vanilla only applies them to player 0 (`difficulty_selection.gd`).
  4. Broadcast the serialized run state, then everyone does `change_scene(MenuData.game_scene)`.
- **Run-state serialization.** Use `PlayerRunData.serialize()` plus the global fields from `RunData.get_state()`. Mirror how `ProgressData` saves `saved_run_state`.

## Step 4: Lift the 4-player cap to 12
Scope: only code that runs in-wave on every machine, plus `RunData`. The coop shop, upgrade and char-select UIs are never used in net mode.
- **`CoopService`** (`singletons/coop_service.gd`):
  - `get_max_players()` returns 12 when `LanNet.active`.
  - `get_player_color()` uses a 12-colour palette.
  - `connected_players` gets one entry per player:
    - local player: device 7 (keyboard) or 6 (gamepad)
    - remote players: fake device ids 20+i
  - Re-apply the scaling knobs after `clear()`.
- **Resize the 4-slot arrays to 12** in extension `_init()`/`_ready()`. Reassign them after vanilla's member initialisers have run. The full list is in the exploration report:
  - `run_data.gd` (L30, L148-164, L193, L556 `locked_shop_items` inside `reset`, L606)
  - `main.gd` (L31-32, L48, L50, and `player_gold/player_xp` at L879-880, inside `on_gold_picked_up`)
  - `entity_spawner.gd` (L33, L40-41)
  - `utils.gd` (L60, L65-66)
  - `temp_stats.gd`, `linked_stats.gd`
  - `global/stats_manager.gd` (L10-11)
  - `popup_manager.gd` (L11-15)

  Arrays assigned inside functions need an override of that function. `main.on_gold_picked_up` is the riskiest; consider copying it into the extension.
- **HUD** (`main.gd` `_on_EntitySpawner_players_spawned`, L1361-1430).
  - The P1–P4 HUD nodes only exist up to 4.
  - In net mode, map the **local** player to the P1 HUD slot.
  - Hide P2–P4 and use `net_player_list` for everyone else.
  - Create the over-head `PlayerLifeBarContainer` for each player at runtime by duplicating the P1 node.
- **Spawn positions** (`entity_spawner.gd` `init`, L93-98): replace the 2×2 offset with a circle of radius `60 + 15*n` around the map centre.

## Step 5: Arena size and enemy scaling
- **Arena.** Extend `singletons/zone_service.gd` `set_current_zone(zone)`. In net mode, before calling `.set_current_zone(zone)`, scale `zone.width/height` by `sqrt(1 + 0.25*(n-1))` (default; configurable). That is about 1.94× linear at 12 players. `main.gd:159-161` passes the same object to the tile map, the map limits and the wave manager, so all of them pick it up.
  - The camera `_max_zoom` follows the bounds automatically.
  - **Clients set the camera's `targets = [local player]`** so it doesn't zoom out to fit 12 players.
- **Enemy count.** Vanilla already scales with `RunData.get_player_count()`:
  - +30% count per extra player
  - +30% HP and +8% damage per extra player (`coop_service.tscn:35-37`)
  - `max_enemies` cap +12.5% per extra player (`entity_spawner.gd:153`)
  - material compensation through `get_coop_materials_factor`
- **Mod changes to enemy scaling.**
  - Set `CoopService.additional_enemies_per_coop_player` and the related values from `net_config` on session start.
  - Extend `on_group_spawn_timing_reached` to raise the cap (e.g. `max_enemies * (1 + 0.25*(n-1))`), so the extra spawns aren't culled.
  - Lower the default HP scaling a little for large lobbies, because the arena is bigger.
  - Check performance with about 300 enemies.

## Step 6: In-wave sync
**Host** (extensions + `host_sync.gd`):
- **Remote input.**
  - Extend `entities/units/movement_behaviors/player_movement_behavior.gd` `get_movement()`:
    - remote player: return `LanNet.input.get_move(player_index)`
    - host's local player: use the unsuffixed solo actions, so both keyboard and gamepad work
  - Extend `utils.gd` `get_player_rjoy_vector(i)` and `is_manual_aim` the same way for aim.
- **Net ids.** Extend `entity_spawner.gd` `spawn_entity` and `main.gd` `spawn_gold`/`spawn_consumables`/`add_player_projectile`/`add_enemy_projectile` to assign `net_id`. Nodes are pooled, so ids are assigned on each (re)spawn.
- **Snapshot.** 20 Hz, unreliable_ordered, packed with `StreamPeerBuffer`. Contents:
  - wave `time_left`
  - per player: pos, flip, hp/max, gold, xp, level, dead
  - per enemy/neutral/structure/pet: id, type index, pos (int16), flip, hp ratio
- **Reliable events.**
  - entity spawn (scene path index) and death (`DieArgs` essentials)
  - projectile spawn (scene, pos, velocity, rotation; enemy and player)
  - gold/consumable spawn and pickup
  - `took_damage` (for floating text)
  - explosions
  - wave end / run won / run lost
- **Pause.** Extend `ui/menus/ingame/pause_menu.gd` so `pause()` shows the menu without `get_tree().paused`. Disable `pause_on_focus_lost` while a session is active.

**Client** (`client_sync.gd` + extensions):
- **Players.** Run vanilla `main._ready`, which spawns the N real players from the synced RunData, so weapons and visuals are correct. Right after, call `_wave_manager.set_physics_process(false)` and `_entity_spawner.set_physics_process(false)`.
- **Player puppets.**
  - Set every player body to kinematic mode and drive its position from snapshots (lerp toward the latest).
  - Turn off hurtboxes and pickup areas.
  - Extend `weapons/weapon.gd` `should_shoot()` to return false on clients. Projectiles come from host events.
- **Enemies.**
  - Instance them through `EntitySpawner.spawn_entity` with the same scene.
  - Then disable `set_physics_process`, set kinematic mode, and turn off hitboxes.
  - Drive position from snapshots.
  - On the death event, call `die()`.
- **Projectiles.** Spawn from events through the existing pools, with hitboxes disabled. They fly locally and are freed on hit events or timeout.
- **Pickups and wave state.**
  - Spawn and remove pickups from events. Extend `items/global/item.gd` `pickup()` to do nothing on clients.
  - Override the wave timer from snapshot `time_left`.
- **Local input.** Send `{move, aim, manual_aim}` every physics frame (unreliable). The local player is rendered from snapshots. On a LAN (<5 ms) this is fine; client-side prediction is optional polish later.

## Step 7: Between-wave flow (upgrades and shop per machine)
1. **Host, at wave end.** Extend `main.gd` `_on_EndWaveTimer_timeout`. In net mode, do **not** show `_coop_upgrades_ui`. Run `RunData.on_wave_end()`, then broadcast `wave_end` together with the full run state, including each player's `_upgrades_to_process` and `_consumables_to_process`.
2. **Every peer, host included, sets up a solo between-wave phase:**
   - stash the full `players_data`
   - set `RunData.players_data = [my_player_data]` and `set_coop_run(false)`
   - resolve the pending level-ups and consumables with the solo `_upgrades_ui` flow
   - go to the solo `shop.tscn` (extend `run_data.gd` `get_shop_scene_path` for net mode)
3. **Shop "Go" button.** Extend `ui/menus/shop/base_shop.gd`: instead of `change_scene(main)`, send `PlayerRunData.serialize()` to the host and show "Waiting for: …" through `net_player_list`.
4. **Host merge.** When all players are done, the host deserializes each player into `players_data[i]`, restores the coop run, increments the wave, broadcasts the run state, and everyone changes to `main.tscn`.
5. **Run end.** On run won or lost, every peer shows the solo end screen for its own player. "Back" leaves the session for clients. The host returns to the lobby.

## Step 8: Polish
- Floating names above players.
- Remote players' colours applied to the outline (`CoopService.change_stylebox_for_player`).
- Mod config knobs exposed in the manifest `config_schema`: arena factor, enemy count/HP factor, port.
- Avoid `push_error` from mod code. Any `ERROR:` in the log that mentions `mods-unpacked` makes the crash reporter disable mods on the next launch.

---

## Milestones
1. **Docs.** Step 0, plus the `mod_main` fix.
2. **Connect.** Menu button → host/join → lobby with names, characters, ready. Verify on 2 local instances.
3. **Sync.** Synced run start, then the host simulates and clients puppet players only, with no enemies.
4. **Full wave.** Enemies, projectiles, pickups, and wave end.
5. **Between waves.** Per-machine upgrades/shop and merge, so the loop runs for multiple waves.
6. **Scale.** 12-player caps, larger arena, enemy scaling, HUD list, disconnect handling, perf pass.

## Critical files to extend
`ui/menus/title_screen/title_screen_menus.gd`, `singletons/coop_service.gd`, `singletons/run_data.gd`, `singletons/zone_service.gd`, `singletons/utils.gd`, `singletons/temp_stats.gd`, `singletons/linked_stats.gd`, `global/entity_spawner.gd`, `global/stats_manager.gd`, `main.gd`, `entities/units/movement_behaviors/player_movement_behavior.gd`, `weapons/weapon.gd`, `items/global/item.gd`, `ui/menus/ingame/pause_menu.gd`, `ui/menus/shop/base_shop.gd`, `ui/menus/global/popup_manager.gd`.

## Verification
- **Local multi-instance testing.**
  - Run 2–4 game instances on one PC (Godot 3.7 editor "Run multiple instances", or the game exe with mod loading). Each instance needs a separate `user://` (`--user-data-dir` or a separate profile) so saves and config don't collide.
  - Host on 127.0.0.1.
  - Run with `-vvv` and watch `ModLoaderLog` output.
- **Per milestone:**
  - M2: names, characters and ready flags show up on every instance. Start is disabled until all players are ready.
  - M3/M4: client movement is visible on the host and the other way round. Enemies, hits, deaths and gold match. Killing the client process mid-wave doesn't crash the host.
  - M5: shops on different machines finish in any order. Bought items persist into the next wave on all peers (compare `RunData` dumps).
  - M6: use debug devices or headless dummy clients that send scripted random input to fill 12 slots. Check FPS and bandwidth with about 300 enemies, check the arena scales, and check spawn counts against the formula.
- **Also test** keyboard-only and gamepad-only on both host and client, including menu and lobby navigation.
