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
net/net_discovery.gd   # /root/LanNet/Discovery: host UDP beacon, client listener for the join page
ui/ui_kit.gd           # shared page building blocks (pages are built in code, no .tscn)
ui/multiplayer_menu.gd # name, Host game / Join game / Back
ui/join_menu.gd        # discovered games list, join by address
ui/lobby.gd            # player list, character grid, weapon pick, ready toggle, host: zone/difficulty/Start
ui/net_player_list.gd  # in-wave compact HUD: name + HP bar per other player; "waiting for X" in shop
extensions/...                 # mirrored vanilla paths (below)
```

---

## Step 1: Networking core (`LanNet`)
- **Transport.** Godot 3 high-level multiplayer: `NetworkedMultiplayerENet`, `create_server(port=24567, max_clients=11)`, `create_client(ip, port)`, `get_tree().network_peer`. Every RPC goes through the `LanNet` node, which has the same path on all peers.
- **Handshake (client → host).** The client sends `{mod_version, game_version=ProgressData.VERSION, active DLC ids, name}`. The host rejects the client if the versions or DLC set differ, the lobby is full, or a run is already in progress. If accepted, the host assigns a `player_index` (host = 0) and broadcasts the lobby state.
- **Lobby state.** For each peer: `{peer_id, player_index, name, character_id, weapon_id, ready}`. The host also sets `zone` and `difficulty`.
- **Unlocks.** During a session every peer, host included, has everything unlocked (`NetProtocol.get_multiplayer_unlocks()`, built from the loaded game data). This was originally "clients use the host's lists" and was changed after Step 3. Each peer:
  - temporarily overrides the `ProgressData.*_unlocked` arrays (`LanNet._apply_multiplayer_unlocks`, on `host()` and on the client's welcome)
  - blocks `ProgressData` saves while the session is active
  - restores its own lists on leave

  This keeps item pools the same on every machine, because the handshake already checks the game version and DLCs. Singleplayer progress is never touched.
- **Disconnects.**
  - Client drops in the lobby: remove it from the list.
  - Client drops during a wave: the host kills that player.
  - Client drops between waves: the host drops them from the merge.
  - Host drops: clients return to the title screen and see a popup.

**Status: done.** Files: `net/net_manager.gd`, `net/net_protocol.gd`, `net/net_config.gd`, `net/net_translations.gd`, `extensions/singletons/progress_data.gd`. Notes on what was built:
- **Public API** (`/root/LanNet`): `host(port)`, `join(ip, port)`, `leave()`, `set_player_name`, `set_local_player_info({character_id, weapon_id, ready})`, `set_lobby_settings({zone, difficulty})` (host), `set_run_in_progress(bool)` (host), `get_player(i)`, `get_local_player()`, `are_all_ready()`. Signals: `session_started(as_host)`, `session_ended(reason)`, `joined_lobby`, `lobby_changed`, `player_disconnected(player_index)`.
- **Reasons** are translation keys (`LAN_REJECT_*`, `LAN_MSG_*`). `last_end_reason` keeps the last one so the title screen (Step 2) can show the popup and clear it.
- **Saves** are blocked for host *and* clients while a session is active (`ProgressData.lan_coop_saves_blocked`), so a net run never lands in `saved_run_state`. Unlocks earned during a session are not saved.
- **Unlock override** covers `zones/characters/upgrades/consumables/weapons/items_unlocked`, not difficulties (all difficulties are selectable in the lobby anyway). Consumables follow vanilla's unlock-all save and only include the ones unlocked by default. Vanilla's own `unlock_all_*` functions are not used, because they also change bought-item counts, killed enemies and challenges.
- **Player indices** are compacted when someone leaves the lobby. During a run (`run_in_progress`) the slot is kept with `connected = false` and `player_disconnected` fires; Steps 6 and 7 hook into that.
- **Security/robustness:** `server_relay` is off, every RPC checks the sender id and argument types, and peers that don't send a hello within 5 s are kicked. Rejected clients get the reason, then are kicked after 0.5 s.
- **ENet pitfall:** ENet calls `close_connection()` itself right after `server_disconnected` / `connection_failed`, so cleanup runs deferred and the close is guarded by connection status. Closing twice logs an engine `ERROR:`.
- `net_input.gd`, `host_sync.gd` and `client_sync.gd` belong to Step 6 and don't exist yet.

## Step 2: Main menu entry, host/join pages, LAN discovery
**Status: done** (reworked once after manual testing: separate host/join flow, digit pad removed, discovery added).

**Flow**
```
Main menu ─ Multiplayer ─► Multiplayer page: Name, [Host game], [Join game], [Back]
                              Host game ─► hosts on the saved port ─► Lobby
                              Join game ─► Join page: found games list + "IP or IP:port" + Connect ─► Lobby
```
Leaving the lobby returns to the page it was entered from (Multiplayer page for hosts, Join page for clients). Session-end reasons show in that page's status line, not in a popup.

**Files**
- `extensions/ui/menus/title_screen/title_screen_menus.gd`:
  - inserts the `MyMenuButton` "Multiplayer" after StartButton in `_main_menu.left_container`, with left/right focus going to ModsButton
  - adds the three pages as hidden children and wires the `switch()` calls
  - on title load (deferred, after `TitleScreen._ready`), opens the Join page if `LanNet.last_end_reason` is set, or the lobby if a session is still joined
- `ui/ui_kit.gd`: shared page building (dimmed background, centred column, `font_60_outline` title, `MyMenuButton`s, status label).
- `ui/multiplayer_menu.gd`: the Name field (saved on every edit; empty keeps the stored name), Host game, Join game, Back.
- `ui/join_menu.gd`:
  - the discovered games as button rows ("name  n/12"; incompatible versions disabled), updated in place so focus survives
  - an address field (`NetProtocol.parse_address`), Connect, status, Back
- `ui/lobby.gd` (Step 2 version):
  - host only: "Others join with: <LAN IPv4s> (port N)"
  - player count, rows with `(host)` / `(you)` / `(disconnected)`, Leave
- `net/net_discovery.gd` (`/root/LanNet/Discovery`):
  - **Host:** while hosting and not `run_in_progress`, sends a JSON beacon every second to UDP `DISCOVERY_PORT` (24568). Targets are `255.255.255.255` plus the /24 broadcast of each private LAN address, because Linux sends the limited broadcast only on the default interface.
  - **Client:** listens only while the Join page is visible. Games expire 3.5 s after their last beacon.
  - **Listen failure:** if `listen` fails (e.g. a second client on the same PC), the page says so and manual join still works.
- `net/net_protocol.gd`: beacon build/parse (types checked before comparing), `parse_address`, `get_lan_addresses` (skips loopback, link-local, docker/bridge/VM interfaces), `get_broadcast_addresses`.

**Pitfalls found**
- `MyMenuButton` re-enables itself after its 0.05 s press delay. Disable and enable it with its own `disable()` / `activate()`, not `disabled`.
- Every page's `_input` must call `get_tree().set_input_as_handled()` after handling `ui_cancel`. Otherwise the page that becomes visible handles the same event and navigation skips a page.
- `var x: = <untyped>.split(".")` is a parse error ("can't infer type"). Give an explicit type when the source is untyped.

**Verified** with two instances driven by a test-only autoload in a throwaway copy of the project:
- the host is found within about 0.5 s and joined from its row
- bad IP and bad port messages show
- manual join with `127.0.0.1:port` works
- Escape in the lobby goes back exactly one page
- when the host leaves, the client lands on the Join page with "The host closed the session." and the game leaves the list
- no `ERROR:` lines from mod code

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
  3. `add_starting_items_and_weapons()`, then apply the difficulty effects to player 0, like vanilla coop. The danger effects are read from player 0 only (`entity_service.gd`), and `double_boss` is summed over all players.
  4. Broadcast the serialized run state, then everyone does `change_scene(MenuData.game_scene)`.
- **Run-state serialization.** Use `PlayerRunData.serialize()` plus the global fields from `RunData.get_state()`. Mirror how `ProgressData` saves `saved_run_state`.

Done in three increments, each tested by the user and committed separately: 3a (picks and ready), 3b (host settings and Start), 3c (run build and sync).
- **Difficulty:** all difficulties (Danger 0–5) are always selectable.
- **Start** builds the run and syncs it to every peer, but stays in the lobby. Loading the wave needs Step 4 (input devices for remote players: `entity_spawner.gd:105` reads `CoopService.connected_players[i]`) and Step 6, so it is part of Milestone 3.

**3a status: done.**
- **Shared rules** live in `net/lobby_rules.gd`: character lookup and unlock, starting choices as in `weapon_selection.gd`, `is_entry_complete`. The UI, the host's validation in `LanNet._apply_player_changes` and `are_all_ready()` all use it.
- **Host validation:** invalid or locked picks are dropped. Changing character or weapon un-readies the player. `PROTOCOL_VERSION` is now 2.
- **Lobby UI** (`ui/lobby.gd`):
  - **Left:** player rows with colour (temporary 12-colour palette in `ui_kit.gd`), character icon, name and tags, weapon icon, Ready/Choosing.
  - **Right:** a character grid and a starting weapon grid built from vanilla `inventory.tscn`, with random tiles. Random is resolved locally and the real id is sent. Locked characters show as lock tiles.
  - **Info panel:** vanilla `character_panel_ui.tscn` for a focused character, `item_panel_ui.tscn` for a focused weapon.
  - **Ready** toggles ready.
  - **Focus** moves character → weapons → Ready once the host has confirmed each pick.
  - **Selection markers:** the picked character and weapon get a border in the player's colour (a `Panel` child named `LanSelectedMarker` on the `InventoryElement`).
  - **Scrolling:** both grids and the player list (sized for 12 rows) sit in `ScrollContainer`s with `follow_focus`, so the page height never changes.
  - **Focus up:** "up" from the weapon grid's top row goes back to the picked character, via Inventory's own `set_neighbour_top` + `focus_neighbour_top`, which survive its neighbour recomputation.
  - **Host address:** the host sees one address, `IP: ip:port`, from `NetProtocol.get_primary_lan_address()`. Private LAN addresses come first, wired before wireless; Windows virtual adapters are skipped.

**3b status: done.**
- **Host controls** under the player list: Zone and Difficulty `OptionButton`s (`zone_selection_button_theme.tres`).
  - They list every `ZoneService.zones` entry and every `ItemService.difficulties` entry.
  - They go through `LanNet.set_lobby_settings`, which validates via `LobbyRules.is_valid_zone/difficulty` and remembers the values in `net_config` (`last_zone`, `last_difficulty`).
  - `host()` restores them.
- **Clients** see a "Zone, Danger N" summary.
- **Hint line:** waiting / host can start / waiting for the host / too many players.
- **Start** (host only) is enabled when `are_all_ready()` and there are at most `LobbyRules.MAX_RUN_PLAYERS` (4) players. Step 4 lifts the cap. In 3b it only logs; 3c adds the run build.
- **Leaving with ui_cancel** needs a press *and* release with no dropdown open, because ui_cancel closes an `OptionButton` popup on press.
- **Lobby broadcasts** only go to peers in `get_network_connected_peers()`.

**3c status: done.**
- **Building the run:** `net/run_builder.gd` `build_run` follows `character_selection` → `weapon_selection` → `difficulty_selection` (without the save and stats calls).
- **Serializing the run:** it uses the save loader, `ProgressDataLoaderV3.new()` (no args = no disk access): `serialize_run_state(ProgressData.get_run_state())`, then `JSON.print`.
- **The run travels as JSON text.** The deserializers expect JSON types (string keys, floats); raw RPC dictionaries make `PlayerRunData._deserialize_effects` raise script errors.
- **Loading the run:** `apply_run` mirrors vanilla's load: `JSON.parse` → `deserialize_run_state` → merge into `_get_empty_run_state()` → the int fixes from `progress_data.gd` → `RunData.resume_from_state`. The host applies its own JSON too, so every peer runs the identical deserialized copy.
- **Sync flow:**
  - `LanNet.start_run()` (host) builds the run and sends `_rpc_run_state(run_id, json, digest)`.
  - Each client applies it and compares `RunBuilder.digest()` (md5 of a readable summary: zone, difficulty, per-player character, weapons, items, gold, max HP, elite/boss/event spawns), then answers `_rpc_run_state_ack`.
  - The lobby hint shows ready / pending / differs.
  - `lobby_settings.run_id` marks the current run. Any later lobby broadcast resets it to 0, so a stale run is never used.
- **What's kept:** `LanNet.run_state` holds the JSON for Milestone 3.
- **Cleanup:** RunData is reset when the session ends if a run replaced it.
- **Tested:** two instances with different characters at Danger 3. Identical digests; the JSON is about 23 KB and goes in one reliable RPC.
- **Pitfall:** in GDScript 3, `continue` inside a `match` block falls through to the next pattern instead of continuing the loop. Use `if`/`elif` in loops.

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

**Increments.** Nothing in a session loads `main.tscn` yet, so lifting the caps can't be tested until the host can enter a wave. Clients only get an in-wave view in Step 6. Until then they stay in the lobby while the host plays a test wave. Each increment is tested in two windows, then committed.

- **4a: host test wave (≤ 4 players).**
  - **Start → wave.** After a successful sync, Start loads `main.tscn` on the host (`set_run_in_progress(true)`, then `change_scene(MenuData.game_scene)`). Clients get a "host is in a test wave" hint and stay in the lobby.
  - **Devices.** Before the scene change, the host fills `CoopService.connected_players`: the local player gets keyboard 7, or gamepad 6 if `InputService.using_gamepad`; remote players get device `-1`.
    - Vanilla's per-player input helpers already return "nothing" for a negative device: `Utils.is_player_action_*`, `get_player_rjoy_vector`, and the pause check via `get_remapped_player_device`.
    - Only movement needs an override: `extensions/entities/units/movement_behaviors/player_movement_behavior.gd` `get_vector_for_input_prefix` returns `Vector2.ZERO` for `device < 0`. Step 6 swaps that for `LanNet` input.
  - **Wave end, temporary until Step 7.** In a session, `main.gd` `_on_EndWaveTimer_timeout` skips vanilla's coop upgrade UI and shop, which only have 4 slots. It sets `run_in_progress` false and changes back to the title screen, where the lobby reopens (`_restore_lan_page`). Quitting from the pause menu does the same.
- **4b: 12 players in the wave.** Lifting the caps:
  - `CoopService.get_max_players()` returns 12 in a session.
  - 12 player colours: the palette moves from `ui_kit.gd` into a `CoopService` extension.
  - All 4-slot arrays resized (list above).
  - Spawn circle.
  - `LobbyRules.MAX_RUN_PLAYERS` removed.
  - **HUD:** the extension's `_enter_tree` duplicates the P4 node sets (`LifeContainerP4`, `PlayerLifeBarContainerP4`, `UIThingsToProcessPlayerContainer4`) as P5–P12, with `owner = main` and `unique_name_in_owner`, before vanilla's `_ready` looks them up by `%` name. Screen HUDs beyond P1 are hidden in a session. `set_hud_position(i)` gets a safe slot for i ≥ 4.
  - **Test:** the host plus fake lobby entries (test driver) fill 12 slots. The wave runs about 20 s with no `ERROR:`. Check the spawn circle and the over-head life bars.
- **4c: other players' HUD.** `ui/net_player_list.gd`: a compact list (colour, name, HP bar) of the other players, in place of the hidden P2–P12 HUDs. The local player is always in the P1 slot. On the host that is index 0; Step 6 remaps it for clients.

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
- Default player name: if the player never set one, pick a random funny name from a predefined list that fits the game (potatoes, aliens, weapons, e.g. "Spud Lightyear", "Tater Tot", "Mashed Menace"). This replaces the current "Player123" in `net_config.gd`.
- ~~Unlock everything in multiplayer.~~ Done early (after Step 3), see Step 1 "Unlocks". Verified: the test save goes from 5 to 50 characters during a session, back to 5 after leaving, and the save file is not written.
- Controller text entry: an on-screen keyboard for the name and the join address. Until then, controller players keep the default name and join from the discovered games list.
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
  - **Windows that are covered or unfocused stall on vsync** under Wayland/XWayland, which also stops the network poll. Turn vsync off (`display/window/vsync/use_vsync=false`) and tile the windows with `--position`.
  - Without `config/custom_user_dir_name`, instances use the real `~/.local/share/Brotato` save and log. For throwaway tests, copy the project and set a separate user dir name in the copy.
- **Test setup used so far (Steps 2–3).** It lives in the session scratchpad and has to be rebuilt per session:
  - **Throwaway copy.** `cp -a Decompiled <scratch>/game`, then remove its `.git`. Replace `mods-unpacked/Moolt-Lan_Coop` with an **absolute** symlink to `brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop`. In the copy's `project.godot`:
    - `config/custom_user_dir_name="BrotatoLanTest"` (under `[application]`)
    - `window/vsync/use_vsync=false` (under `[display]`)
    - an autoload `LanTestDriver="*res://lan_test_driver.gd"` after `OS_Seaven`
  - **Running.** `Godot/Godot_v3.7-dev1_x11.64 --path <scratch>/game --resolution 1920x1080 -- <role>`. One instance runs in the background with role `host`, a second in the foreground with role `join`, each under `timeout 60` with stdout to a log file.
    - First run one instance with role `quit` (quit as soon as the title screen loads) to catch parse errors cheaply.
    - The two instances share `user://lan_coop.cfg` (names, port 24999 in that profile).
  - **Driver.** `lan_test_driver.gd` reads the role from `OS.get_cmdline_args()`. In `_process` it waits for `current_scene.filename == MenuData.title_screen_scene`, then finds `Menus` and runs a timed `match step` script that drives the pages by calling their handlers directly:
    - `LanMultiplayerButton.emit_signal("pressed")`, `mp._host_button`, `join._first_row()`
    - lobby `_on_CharacterGrid_element_pressed(element)`, `_on_ReadyButton_pressed()`, `_on_StartButton_pressed`
    - it prints `[TEST] ...` lines and saves screenshots: `get_viewport().get_texture().get_data()`, `flip_y()`, `save_png()` into `$SHOT_DIR`
    - each step sets `next_t` *before* any `yield`, otherwise `_process` re-enters the same step
    - fake lobby players: append `NetProtocol.new_player_entry(...)` to `LanNet.players`, then `_broadcast_lobby_state()`
  - **Log check.** `grep -a "SCRIPT\|ERROR"` the logs, then filter out the engine shutdown errors (`_first != nullptr`, resources/MemoryPool still in use, ObjectDB leaks). `--disable-mods` shows vanilla prints these too. A stray background instance from an earlier run can mix into results, so check `ps` first.
  - **Manual test by the user.** Two windows: `--resolution 1280x720 --position 0,0` and `--position 1280,0`, with no role argument (the driver stays idle), started with `nohup`. Commit only after the user approves.
- **Per milestone:**
  - M2: names, characters and ready flags show up on every instance. Start is disabled until all players are ready.
  - M3/M4: client movement is visible on the host and the other way round. Enemies, hits, deaths and gold match. Killing the client process mid-wave doesn't crash the host.
  - M5: shops on different machines finish in any order. Bought items persist into the next wave on all peers (compare `RunData` dumps).
  - M6: use debug devices or headless dummy clients that send scripted random input to fill 12 slots. Check FPS and bandwidth with about 300 enemies, check the arena scales, and check spawn counts against the formula.
- **Also test** keyboard-only and gamepad-only on both host and client, including menu and lobby navigation.
