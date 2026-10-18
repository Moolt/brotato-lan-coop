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
- **Clients run `main.tscn` in "puppet mode".** Each machine moves its own player and sends its position; everything else is rendered from host snapshots and events.
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
net/wave_sync.gd       # child of main in a session: host drives remote players and sends snapshots (20 Hz) + events;
                       # client sends its own player's state, applies snapshots, interpolates puppets
net/net_config.gd      # user://lan_coop.cfg: last name, last IP, port, scaling knobs
net/net_discovery.gd   # /root/LanNet/Discovery: host UDP beacon, client listener for the join page
net/net_translations.gd # runtime Translations (en + de) for the mod's keys
net/lobby_rules.gd     # character/weapon lookup and unlock checks shared by the lobby UI, host validation, run builder
net/run_builder.gd     # builds the run from the lobby, (de)serializes it as JSON, digest for the sync check
game/lan_game.gd       # in-wave helpers: MAX_PLAYERS, in_session(), get_player_name(), grow() for 4-slot arrays
ui/ui_kit.gd           # shared page building blocks (pages are built in code, no .tscn)
ui/multiplayer_menu.gd # name, Host game / Join game / Back
ui/join_menu.gd        # discovered games list, join by address
ui/lobby.gd            # player list, character grid, weapon pick, ready toggle, host: zone/difficulty/Start
ui/net_player_list.gd  # "waiting for X" list in the shop (Step 7)
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
- The in-wave sync is one file, `net/wave_sync.gd` (Step 6a), instead of `net_input.gd` / `host_sync.gd` / `client_sync.gd`.

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
  - Hide P2–P12; other players get a name and health bar over their head instead (4c).
  - Create the over-head `PlayerLifeBarContainer` for each player at runtime by duplicating the P4 node.
- **Spawn positions** (`entity_spawner.gd` `init`, L93-98): replace the 2×2 offset with a circle of radius `60 + 15*n` around the map centre.

**Increments.** Nothing in a session loads `main.tscn` yet, so lifting the caps can't be tested until the host can enter a wave. Clients only get an in-wave view in Step 6. Until then they stay in the lobby while the host plays a test wave. Each increment is tested in two windows, then committed.

- **4a: host test wave (≤ 4 players).**
  - **Start → wave.** After a successful sync, Start loads `main.tscn` on the host (`set_run_in_progress(true)`, then `change_scene(MenuData.game_scene)`). Clients get a "host is in a test wave" hint and stay in the lobby.
  - **Devices.** Before the scene change, the host fills `CoopService.connected_players`: the local player gets keyboard 7, or gamepad 6 if `InputService.using_gamepad`; remote players get device `-1`.
    - Vanilla's per-player input helpers already return "nothing" for a negative device: `Utils.is_player_action_*`, `get_player_rjoy_vector`, and the pause check via `get_remapped_player_device`.
    - Only movement needs an override: `extensions/entities/units/movement_behaviors/player_movement_behavior.gd` `get_vector_for_input_prefix` returns `Vector2.ZERO` for `device < 0`. Step 6 swaps that for `LanNet` input.
  - **Wave end, temporary until Step 7** (replaced by Step 7). In a session, `main.gd` `_on_EndWaveTimer_timeout` skips vanilla's coop upgrade UI and shop, which only have 4 slots. It sets `run_in_progress` false and changes back to the title screen, where the lobby reopens (`_restore_lan_page`). Quitting from the pause menu does the same.

**4a status: done.**
- **Start → wave:** `LanNet.start_run()` sets `_start_requested`. `_enter_wave_if_synced()` runs after the build and after every ack; once `get_run_sync_status()` is "synced" it calls `set_run_in_progress(true)`, `_fill_coop_players()` and `change_scene(MenuData.game_scene)`. A lobby change before then resets the run and cancels the start.
- **`lobby_settings.in_wave`** (`PROTOCOL_VERSION` 4) mirrors `run_in_progress`; clients show `LAN_HINT_HOST_IN_WAVE`.
- **Back to the lobby:** the `title_screen_menus.gd` extension calls `set_run_in_progress(false)` in `_ready`, so wave end and pause-menu Quit share one path. That drops players who left during the wave and resets `run_id` (the run was played, Start builds a fresh one). `main_menu.gd` `_ready` already calls `CoopService.clear()`.
- **Pause check:** the plan's assumption was wrong for `main.gd` `_check_for_pause`: it polls `Input.is_action_just_released("ui_pause_-1")`, an unknown action. The `main.gd` extension overrides it to skip negative devices.
- **Pause menu:** Restart and End Run are hidden in a session (`ingame_main_menu.gd` extension, `init`).
- **Tested:** host + one client, Danger 3. The wave loads with devices `[7, -1]`, the host moves with the keyboard, the remote player stands still. Wave end and Quit both reopen the lobby on the host; the client hint switches to "test wave" and back.
- **Known gap** (resolved in 7f: the own saved run is put aside for the session): `main.gd` calls `ProgressData.reset_and_save_new_run_state()` when all players die. The disk save is blocked, but the in-memory `saved_run_state` is cleared, so "Continue" disappears until the game restarts.

- **4b: 12 players in the wave.** Lifting the caps:
  - `CoopService.get_max_players()` returns 12 in a session.
  - 12 player colours: the palette moves from `ui_kit.gd` into a `CoopService` extension.
  - All 4-slot arrays resized (list above).
  - Spawn circle.
  - `LobbyRules.MAX_RUN_PLAYERS` removed.
  - **HUD:** the extension's `_enter_tree` duplicates the P4 node sets (`LifeContainerP4`, `PlayerLifeBarContainerP4`, `UIThingsToProcessPlayerContainer4`) as P5–P12, with `owner = main` and `unique_name_in_owner`, before vanilla's `_ready` looks them up by `%` name. Screen HUDs beyond P1 are hidden in a session. `set_hud_position(i)` gets a safe slot for i ≥ 4.
  - **Test:** the host plus fake lobby entries (test driver) fill 12 slots. The wave runs about 20 s with no `ERROR:`. Check the spawn circle and the over-head life bars.

**4b status: done.**
- **`game/lan_game.gd`:** `MAX_PLAYERS` (= `NetProtocol.MAX_PLAYERS`), `in_session()`, and `grow(array, value)`. Arrays grow to 12 slots **always**, not only in a session: vanilla already keeps 4 slots for 1–2 players, so it never reads slots beyond the player count.
- **Where arrays grow:**
  - Extension `_init`: `main.gd`, `entity_spawner.gd`, `stats_manager.gd`, `popup_manager.gd`, `run_data.gd`, `utils.gd`, `debug_service.gd`.
  - After the vanilla functions that reassign 4-slot literals: `RunData.reset`, `_reset_per_wave_properties`, `reset_run_caches`, `resume_from_state`; `Utils.reset_stat_caches`, `reset_last_elt_selected`.
  - `Utils._process` resets `_manual_aim_cache` to 4 slots every frame (deferred), so `is_manual_aim` grows it on demand.
  - `TempStats`/`LinkedStats` are never reassigned; `LanNet._ready` grows them once (`LanGame.grow_autoload_arrays`).
- **Crash sites the list above missed:**
  - `DebugService.log_run_info()` (called from `main.gd` with its 4-slot default arguments). The extension grows its arguments.
  - The coop `UpgradesUI._ready` indexes 4 containers and 4 stat popups. With more than 4 players, the `main.gd` extension sets `is_coop_ui = false` in `_enter_tree`, so its `_ready` returns early. Step 7 replaces that UI.
  - The pause menu's `PopupManager` adds popups for every player.
  - `DebugService.handle_player_spawn_debug_options` only indexes its arrays when a debug flag is on.
- **`on_gold_picked_up`:** calls vanilla for ≤ 4 players. For more players it runs a copy with player-sized `player_gold`/`player_xp`.
- **Colours:** the `CoopService` extension appends 8 colours to `player_colors` in `_ready`. `UiKit.get_player_color` delegates to `CoopService.get_player_color`.
- **Spawn circle:** `EntitySpawner.spawn_entity` override for `EntityType.PLAYER` in a session (radius `60 + 15n` around `_zone_max_pos / 2`).
- **HUD:** in `_enter_tree`, P4 node sets are copied as P5–P12. Names are changed before the owner is set, because setting `owner` claims the unique names. In a session, screen HUDs and things-to-process containers of players ≥ 1 are hidden. `set_hud_position(i ≥ 4)` already resolves to bottom-right, so it needs no change.
- **Tested:**
  - Host, one real client and 10 fake lobby entries. 12 players on the circle, distinct outlines, HUD P1–P12 found, pause menu opens. Gold splits over all 12. The wave ends back in the lobby with no `ERROR:`.
  - Vanilla solo wave outside a session: the run-lost screen works, no errors.
  - `WARNING: Node './Attach' was modified from inside an instance` also appears with 4a code; it is not new.
- **4c: names and health bars over players' heads.** A list of 12 players in the screen HUD would be hard to read in a fast game, so the other players' state sits on their characters instead. The screen HUD stays local-only (top-left: HP, XP, level, gold); nobody needs the others' gold or XP during a wave. The local player is always in the P1 slot. On the host that is index 0; Step 6 remaps it for clients.
  - **Name:** a `Label` under each `PlayerLifeBarContainerP*` (the `Node2D` the player's `RemoteTransform2D` drives), above the bar. It shows the lobby name in the player's colour (`CoopService.get_player_color`), in a small vanilla font with a dark outline (`font_22` or an outlined copy).
  - **Health bar:** in a session, other players' bars are always visible, even at full HP. Extend `main.gd` `_on_player_health_updated` (~L1658), which vanilla gates on `hp_bar_on_character` and HP < max. The local player's bar follows the vanilla option.
  - **Local player:** no name over the own character.
  - **Dead players:** bar hidden, name greyed out (players stay dead until the wave ends).
  - **Test:** 12 slots via the test driver. Names readable and coloured, bars visible at full HP, a dead player's name greyed.

**4c status: done.**
- **Implementation** (in the `main.gd` extension):
  - **Labels:** `_on_EntitySpawner_players_spawned` adds a `LanNameLabel` to each non-local player's `PlayerLifeBarContainerP*`. The font is a copy of `font_smallest_text` at size 22 with a 2 px outline; the label box is `Rect2(-150, -106, 300, 32)`, bottom-aligned above the bar. Because `WorldUI` is a `CanvasLayer`, names keep their pixel size when the camera zooms out.
  - **Health bars:** `_on_player_health_updated` calls vanilla, then shows the bar for non-local, living players.
  - **Death:** `_on_player_died` greys the name.
  - **Lookups:** `LanGame.get_lan_net()` and `get_player_name(i)`; the local player is `LanNet.local_player_index`.
- **Palette fix:** the 8 extra colours are now `[hue, value]` pairs built with `Color.from_hsv(h, 0.3, v)`. `get_player_color` adds 0.5 saturation, so the old near-white entries turned into near-duplicates of vanilla's colours (two reds from the "grey"). They now end at about 0.8 saturation, like vanilla's: blue, pink, purple, red, spring green, magenta, azure, brown.
- **Tested:** 12 slots with the test driver. 11 coloured names over the others with visible bars at full HP. Killing a fake player hides its bar and greys its name. No `ERROR:`.

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

**Step 5 status: done** (one increment; it was small enough).
- **Knobs:** `NetProtocol.DEFAULT_SCALING`, values per extra player: `arena_area_per_player` 0.25, `enemy_count_per_player` 0.3, `enemy_health_per_player` 0.3, `enemy_health_per_player_beyond_4` 0.2, `enemy_damage_per_player` 0.08, `enemy_cap_per_player` 0.25. The host reads them from the `[scaling]` section of `user://lan_coop.cfg` (clamped to 0–2) and sends them as `lobby_settings.scaling` (`PROTOCOL_VERSION` 5), so clients will build the same arena in Step 6. `LanGame.get_scaling(key)` reads them.
- **Arena:** `extensions/singletons/zone_service.gd` scales `width/height` by `LanGame.get_arena_factor(n)` = `sqrt(1 + 0.25(n-1))` before vanilla's `set_current_zone`. It applies after vanilla's `map_size` item effect, which sums over all players (one "Old" character shrinks the map by 33%).
- **Enemy factors:** `LanGame.apply_enemy_scaling(n)` from the `main.gd` extension's `_enter_tree` (before vanilla's `_ready`) sets the three `CoopService.additional_*` values and resets `EntityService`'s cache. HP gets the average over the extra players: 0.3 for players 2–4, 0.2 beyond (3.5× at 12 players instead of 4.3×). `CoopService.clear()` on the main menu restores vanilla's values.
- **Enemy cap:** the `entity_spawner.gd` extension sets `_current_wave_data.max_enemies` for the call of `on_group_spawn_timing_reached`, so vanilla's `max * (1 + (n-1)/8)` comes out as `max * (1 + 0.25(n-1))` (375 at 12 players), then restores it.
- **Camera:** every machine has its own screen, so in a session the camera targets only the local player with `_is_snapped = true` (solo behaviour). `lock_coop_camera` is ignored. When the local player dies, the camera follows all living players with vanilla's coop camera (smooth, zooms out to fit, snaps to the last one). On clients this works once Step 6 loads the wave, since it uses `LanNet.local_player_index`.
- **Tested:** host + client + 10 fake players, Danger 3, `nb_enemies_mult` 6, invulnerable players, 40 s wave (driver). Arena 41×31 tiles (21×16 after an "Old" character, × 1.94), HP factor 3.92 at Danger 3, damage 2.11. 160 enemies plus 100–170 queued (the spawn queue limits the rate, so the 375 cap was never hit) at about 300 FPS uncapped. After the host player dies, the camera zooms out to 1.37 over the other 11. No `ERROR:`. Vanilla solo wave unchanged.

## Step 6: In-wave sync
**Movement authority (decided before 6a).** Each machine moves its own player; the host decides everything else. Rendering the own player from 20 Hz snapshots would delay one's own movement by about 60–120 ms (snapshot interval, interpolation, round trip), and removing that later would need client-side prediction (numbered inputs, rewind and replay). In LAN co-op a client faking its position doesn't matter.
- **Client, own player:** a normal vanilla `Player` driven by the local keyboard/gamepad, so speed, the arena clamp and animations work as in solo play. About 30 Hz unreliable it sends `{pos, move, aim, manual_aim}` to the host. It decides nothing else: hurtbox, pickup area, weapon firing and HP regen are off; HP, death, gold and XP come from the host.
- **Host, remote players:** kinematic mode, moved to the latest reported position. `get_movement()` returns the reported direction, so the walk animation and moving/not-moving item effects work. Everything else stays vanilla on the host: enemies target them there, their hurtbox takes damage, they pick things up, their weapons fire from there.
- **Snapshots** carry every player's position; a client ignores its own.
- **Speed during a wave** (temp buffs, `decaying_bonus_speed`, slows) changes on the host. The snapshot carries each player's current speed and the client moves at it.
- **Death** is decided by the host: when the snapshot says dead, the client's player dies and stops taking input.
- **Host-side moves of a player** (if any effect does that) must be sent to that client, or it snaps back. Check for them in 6a.
- **Timing:** the host sees a client's position 1–5 ms late; enemies on a client run 50–100 ms behind (interpolation). A last-moment dodge can occasionally count differently from what the client saw.

**Increments.** Each is tested in two windows (driver plus manual test), then committed.
- **6a: players in the wave (Milestone 3).**
  - Start loads `main.tscn` on every peer from the synced run (replaces the 4a test wave and its lobby hint).
  - Clients: `_wave_manager` and `_entity_spawner` spawn no enemies (players only). Own player as above; other players are puppets (physics off, position interpolated between snapshots, animation and flip from the reported movement).
  - Host: remote players driven by the reported state; snapshot at 20 Hz (unreliable_ordered, `StreamPeerBuffer`): wave `time_left`, per player pos, move, speed, hp/max, dead. Enemies exist only on the host for now.
  - Wave end: the host sends a reliable event and every peer returns to the lobby (temporary until Step 7).
**6a status: done.**
- **Entering:** `_enter_wave_if_synced` sends `_rpc_enter_wave(run_id)` to every client, which checks the run id against its verified run, fills `CoopService.connected_players` (own device, others -1) and loads `main.tscn`. `PROTOCOL_VERSION` 6.
- **`net/wave_sync.gd`** (`LanWaveSync`, added by the `main.gd` extension's `_ready`, after vanilla's): holds both roles. RPCs live on `LanNet` (`_rpc_snapshot`, `_rpc_player_state`, `_rpc_wave_cleanup`), which forwards them to `LanNet.wave_sync`.
  - Client → host every physics frame (unreliable): `pos, move, aim, manual_aim`. The host applies the latest each physics frame (clamped to the arena). Sending every frame instead of 30 Hz avoids choppy remote players on the host without host-side interpolation.
  - Host → clients every 3 physics frames (20 Hz, unreliable, `StreamPeerBuffer`, 13 + 23 bytes per player): seq, host msec, `time_left`, per player pos, move (int8), `get_move_speed()`, hp, max hp, dead flag.
  - Client puppets: physics off, positioned 100 ms in the past between the two snapshots around that time (clock offset tracked from the smallest delay seen), `update_animation(move)` for walk animation and flip.
- **`extensions/entities/units/player/player.gd`:** `lan_net_driven` (host, remote: `get_movement()` returns the reported move, `get_next_velocity()` is zero, since players are kinematic bodies the position is just set), `lan_move_speed` (client: host's speed), `lan_no_regen` (client).
- **Client own player:** hurtbox, pickup and attract areas off, no regen; HP and death from snapshots (`health_updated` is emitted so the HUD follows). Wave manager and entity spawner physics are off (no enemies, structures or pets); bullet hell nodes are freed.
- **HUD on clients:** the own `LifeContainerP*` takes P1's anchors and margins, and the own things-to-process container moves into P1's slot.
- **Aim:** `Utils.is_manual_aim` returns the reported flag for remote players on the host; `gamepad_attack_vector` is set from the reported aim. (`is_manual_aim` returns null, not false, when manual aim is off.)
- **Wave end:** the client ignores its own `WaveTimer` timeout. The host's `clean_up_room` sends `_rpc_wave_cleanup`; the client runs `clean_up_room` once (that event or vanilla's all-dead check, whichever is first), then its `EndWaveTimer` returns it to the lobby. A client in `main.tscn` also returns when a lobby broadcast says `in_wave` is false (host quit).
- **Focus:** losing window focus doesn't pause in a session.
- **Lobby hint** for a client that left the wave: "A wave is in progress. You are back in when it ends."
- **Tested:** host + client (+1 and +10 fake players), 20 s wave. Client movement shows on the host (1196 → 1871 on both), host movement and both deaths show on the client, the client's camera spectates after its death, both return to the lobby, client HUD shows its own HP and gold colour. No `ERROR:`. Vanilla solo wave unchanged.
- **Known gaps** (later increments; all resolved in 6e and Step 7): the host starts the wave without waiting for clients to load (the client's timer resyncs; 6e); a client quitting from its pause menu leaves its player standing on the host (6e); pause only pauses the own machine (6e); client-side `RunData` changes during the wave (e.g. random stat rolls at wave start) diverge, which Step 7's state broadcast overwrites.

- **6b: enemies, trees, structures and pets on clients.** Net ids assigned on each (re)spawn (`entity_spawner.gd` `spawn_entity`; nodes are pooled). Reliable spawn (scene index) and death (`DieArgs` essentials) events; snapshot: id, pos (int16), flip, hp ratio. Clients instance through `EntitySpawner.spawn_entity`, then disable physics, set kinematic, turn off hitboxes, interpolate, and call `die()` on the death event.
**6b status: done.**
- **Net ids (host):** the `entity_spawner.gd` extension reports every non-player `spawn_entity` to `LanWaveSync.on_entity_spawned`, which gives it a u16 id (`lan_net_id` meta; nodes are pooled, so a new id per spawn) and connects `died` once per node. Entities spawned before `LanWaveSync` exists (jellyshields in `Player.init`) are not synced; each machine keeps its own.
- **Reliable events,** batched per physics frame in one `_rpc_events` call (`PROTOCOL_VERSION` 7):
  - spawn: `[0, id, type, scene path, pos, player_index, data ref, charmed_by]`. Structures and pets need their `StructureEffect`/`PetEffect`: the data ref is `[effect key, index]` into the player's `structures` / `stat_pets` effect arrays (same order on every peer), else a resource path. A structure or pet whose data can't be resolved is skipped on the client.
  - death: `[1, id, knockback]`, not sent for cleanup deaths (each client's own `clean_up_room` kills everything).
  - birth (spawn marker): `[2, type, pos, charmed_by]`.
- **Snapshot** adds a u16 count and 7 bytes per entity (id, int16 x/y, HP 0–255); trees are left out since they don't move.
- **Client copies:** spawned through the client's own `spawn_entity` (pools, signals, HUD hooks all vanilla), then made inert: physics off, `MODE_KINEMATIC`, every `Area2D` in the subtree stops monitoring and being monitorable. Interpolated like puppet players; `update_animation(b - a)` flips Units. On death: `DieArgs` with `enemy_killed_by_player = false` (no loot, kill effects or stats) and the host's knockback; physics is turned back on for Units so vanilla slides the corpse.
- **Entity HP on clients** is the 0–255 ratio itself (`max_stats.health = 255`), because the client's max HP can differ from the host's (elite stats, buffs). `health_updated` drives boss and other over-head bars.
- **Spawn markers on clients:** `spawn_entity_birth` shows them; the extension's `on_entity_birth_timeout` returns them to the pool instead of spawning. The `entity_birth.gd` extension ignores client players standing on a marker (vanilla would move it).
- **Client side, other:** the structure timer is stopped; `main.spawn_loot` does nothing (loot comes in 6d); the `weapons/weapon.gd` extension's `should_shoot()` is false, so weapons turn towards targets but never fire.
- **Background:** the earlier note was wrong; `current_background` is part of the synced run state, so host and client already show the same ground.
- **Tested:** host + client + 1 fake Engineer (turrets), plus an injected rhino boss and three trees. Ids and positions match on both sides, turrets show, a tree killed on the host dies on the client, the boss bar follows (host 2436/5000 → client 124/255). Stress: 12 slots, 6× enemies: 166 entities, snapshot about 1.45 KB, client 800+ FPS, host 500+ (uncapped). No `ERROR:`. Vanilla solo unchanged.
- **Not covered yet:** pets weren't in the test (same data-ref path as structures). Snapshots with more than about 190 entities exceed one UDP packet and get fragmented by ENet; split them in the perf pass if that drops snapshots. A host-side spawn marker that vanilla moves away from a player wasn't moved on clients; fixed in 6f.

- **6c: combat visuals,** in two parts:
  - **6c1: attacks and projectiles.** Weapon attacks (melee swings, ranged recoil), player, turret and enemy projectiles (spawn and stop events, copies with their areas off).
  - **6c2: enemy attacks and hit feedback.** Enemy attack animations (shoot, charge), `took_damage` floating text and hit flashes, explosions, burning, and bullet-hell patterns (Nightmare only: Danger 6 effect, `constant_projectile` option; without sync, clients on Nightmare get hit by bullets they can't see).

**6c1 status: done.**
- **Weapon attacks:** the `weapons/weapon.gd` extension's `shoot()` reports each host attack before vanilla runs it (`MeleeWeapon` flips `next_attack_type` afterwards): `[3, player_index, weapon index, rotation, distance, attack type or -1]`. Clients set the rotation, then melee weapons run the real `_shooting_behavior.shoot(distance)` (the swing hits nothing, because client entities are inert), and ranged weapons play the sound and the recoil tween from `RangedWeaponShootingBehavior.shoot` without projectiles. Attacks arriving while a weapon is still busy are skipped.
- **Projectiles:** the `projectiles/projectile.gd` extension (covers `PlayerProjectile`, `EnemyProjectile` and their subclasses) reports `shoot()`, `stop()` and `_return_to_pool()` on the host. Spawn events are built at the end of the host's physics frame, after position and velocity are set (an enemy projectile shoots once in `_ready` before it's placed): `[4, id, scene path, pos, velocity, rotation, speed, max range, is_enemy]`. Stop: `[5, id, pos]`, also sent when vanilla pools a projectile without `stop()`. Only projectiles directly in `_player_projectiles` / `_enemy_projectiles` are synced; bullets inside a `GroupOfBullet` (bullet hell) are not.
- **Client copies:** taken from the client's own pools (pool id = the loaded scene's instance id), placed, then `shoot()` runs for the visuals; player projectiles get a stand-in `RangedWeaponStats` with the host's speed and range, which `PlayerProjectile.shoot` and some subclasses read. All their `Area2D`s stop monitoring and being monitorable. They fly on their own and stop on the host's event, or at their range. `PROTOCOL_VERSION` 8.
- **Tested:** host + client + 3 fakes (one Engineer) with 4 injected spitters: turret shots and enemy projectiles fly on the client (about 14 enemy projectiles in flight on both sides), melee weapons swing. 12 slots with 5× enemies: no `ERROR:`, client 850+ FPS. Vanilla solo unchanged.

**6c2 status: done.**
- **Bullet hell:** the 12 patterns in `ZoneService.bullets_hell` fire single `BulletHellProjectile`s straight into `_enemy_projectiles`, so 6c1's projectile events already cover them. The spawn event now also carries `sinusoidal_motion`, `sinusoidal_motion_speed` and the bullet-hell `direction` (used to stop at the map edge; a missing one spams `printerr`). The `GroupOfBullet` patterns (`BulletHell_2`/`_3`) aren't in that list, so groups stay unsynced.
- **Animations:** on the host, enemies' and turrets' `AnimationPlayer.animation_started` (except idle, death, RESET) is sent as `[6, id, animation, playback speed]`; clients play it. The animations' method tracks call `start_shoot()`/`shoot()`: the `enemy.gd` extension makes both no-ops on clients, the `turret.gd` extension only plays the shot sound. Garden turrets emit `wanted_to_spawn_fruit`, which the `main.gd` extension ignores on clients.
- **Damage:** the host forwards `took_damage` of synced Units and all players: `[7, target kind (0 entity, 1 player), id or player index, value, knockback direction, flags (crit, dodge, protected, armor, one-shot), hit type, effect scale]`. Clients flash the unit, play its hurt/crit/dodge sound and emit `took_damage` with a stand-in `TakeDamageArgs` (`DUMMY_PLAYER_INDEX`, `base_effect_scale`), so vanilla's floating text, blood, hit effects and screen shake run. `main._on_enemy_took_damage` (landmines on kill) is skipped on clients.
- **Explosions:** the `singletons/weapon_service.gd` extension reports `explode()` after vanilla set it up: `[8, scene path, pos, scale, smoke amount, sound db]`. Clients take one from their pool, apply it with areas off and run `start_explosion()`.
- **Burning:** the snapshot's entity entry gains a flags byte (8 bytes per entity); clients start or stop `_burning_particles` when the burning flag changes.
- **`LanWaveSync.event_counts`** counts events per type (sent on the host, received on clients), for tests and tuning. `PROTOCOL_VERSION` 9.
- **Tested:** host + client + 3 fakes with injected spitters, boss and an explosion: animation, damage and explosion events arrive (same counts as sent), damage numbers, hit flashes and blood show on the client. 12 slots with 5× enemies: about 450 damage events in 20 s, no `ERROR:`, client about 590 FPS. Vanilla solo unchanged.

- **6d: materials, consumables and player stats.** Materials (gold), consumables and crates: spawn, attraction and pickup events (`items/global/item.gd` `pickup()` does nothing on clients); gold, XP and level in the HUD, level-up and pickup feedback; the things-to-process icons (upgrades and crates collected during the wave).
**6d status: done.**
- **`items/global/item.gd` extension** (covers `Gold` and `Consumable`): on the host, `drop()` gives the item a u16 net id and `pickup()` reports pickups; `lan_net_id` is 0 while unsynced.
- **Events** (`PROTOCOL_VERSION` 10):
  - drop: `[9, id, kind (0 gold, 1 consumable), gold texture path, consumable id, pos, rotation, push-back target, scale, boosted]`. Clients take the item from their own pool (or instance `gold_scene`/`consumable_scene`), add it to `_active_golds`/`_consumables` and call vanilla's `drop()`, so the push-back looks the same.
  - attraction: the host checks every physics frame whether an item's `attracted_by` changed and sends `[10, id, target kind, target id]` for players and synced entities (lootworms). The gold bag at wave end counts as none: every machine sends its own items there in `clean_up_room`.
  - pickup: `[11, id, player_index]`, only for players (the gold bag's pickups stay local). Clients play vanilla's gold or consumable pickup sound, the gold pickup effect and floating text, and pool the item.
  - crate to process: `[12, player_index, consumable id]`. The `main.gd` extension's `on_consumable_picked_up` finds which player's `_consumables_to_process` grew (any player with `share_coop_loot`); clients add the icon to that player's things-to-process.
- **Snapshot** per player adds gold (s32), XP (float) and level (u16): 33 bytes per player. Clients write them into `RunData.players_data` and emit `gold_changed`, `xp_added` and, per level gained, `levelled_up`, so vanilla's HUD, level-up sound, floating text and upgrade icon follow.
- **Client side:** `main.spawn_gold` and `spawn_consumables` do nothing (with `spawn_loot` and garden fruit, nothing drops locally).
- **Tested:** host + client + 3 fakes with an injected level-up and a crate dropped onto the host player: gold, XP and level match (host player level 1, XP 18 on both), the drop/attract/pickup/crate events arrive in the counts sent, materials on the ground match (50 at the cap). 12 slots with 5× enemies: no `ERROR:`, client about 600 FPS. Vanilla solo unchanged.
- **Gaps:** once 50 materials lie on the ground, vanilla adds new value to a random existing one and grows it; that size change wasn't synced (fixed in 6f). Level-ups on clients run vanilla's `on_levelled_up`, which also adds +1 max HP to the client's copy of `RunData` and queues an upgrade in `_upgrades_to_process`; Step 7 replaces the client's run data from the host anyway (resolved in 7a).
- **Test driver pitfall:** a test that instances a pooled node itself must call `main.get_node_from_pool(pool_id, container)` once first. Vanilla's `add_node_to_pool` asserts that the pool exists, and the failed assert is a `SCRIPT ERROR` attributed to the mod's `main.gd`.

- **6e: pause, dropouts and run end.** Pause (`ui/menus/ingame/pause_menu.gd` `pause()` shows the menu without `get_tree().paused`; `pause_on_focus_lost` is already off in a session), the host waiting for clients to load before the wave timer starts, players dropping out or quitting mid-wave (their player dies or stands still on the host; the host leaving ends the session), run won/lost events.

**6e status: done.**
- **Pause** (`ui/menus/ingame/pause_menu.gd` extension): in a session `pause()`/`unpause()` show and hide the menu without `get_tree().paused`, which would also stop the physics server. Vanilla's `_input` decides open/closed by `get_tree().paused`, so it calls `pause()` again on the pause button while the menu is open; that closes the menu. The extension's `_input` runs before vanilla's for the same event (Godot 3 `call_multilevel` goes derived → base) and handles cancel; `_lan_skip_pause` stops vanilla from reopening the menu when one key is both cancel and pause. `LanNet.pause_menu_open` makes the local player's movement zero (`player_movement_behavior.gd`) and makes `main._check_for_pause` stand aside.
- **Mouse in the pause menu:** two vanilla coop behaviours blocked it.
  - The pause menu's `FocusEmulator` (couch coop's per-player menu focus, active when the menu belongs to a player with a real device) marks every input it doesn't handle as handled, mouse motion and clicks included. In a session the extension leaves it off and the menu uses native focus, as in solo play; it still belongs to the local player (inventory, pause and cancel keys). Without an emulator, coop UI code (inventory popups, stat panels) gets -1 from `FocusEmulatorSignal.get_player_index` and calls `push_error`; the `singletons/focus_emulator_signal.gd` extension answers with the local player in a session.
  - `InputService._input` hides the cursor on every input in a coop run with more than one player (couch coop shares one mouse), also in the lobby once a run was built. During a session `LanNet` turns `InputService`'s input processing off and applies its solo rule in its own `_input`: mouse input shows the cursor, keyboard and gamepad input hide it, and `InputService.using_gamepad` follows. (An extension can't replace `_input`; both levels run.)
  - The driver first opened the menu as player 0, which on a client is a remote player (device -1, so no emulator), and missed the bug; it now passes the local player's index like `main._check_for_pause`.
- **Waiting for clients:** the host pauses the `WaveTimer` and its `HalfWaveTimer` (enemy spawns follow the timer) until every connected client sent `_rpc_wave_loaded` from its `LanWaveSync._ready`, at most 15 s. A snapshot header flag carries the state (header 14 bytes); every screen shows "Waiting for players..." (`LAN_WAITING_FOR_PLAYERS`, en + de) meanwhile. The host logs `Wave starts after X s (every client loaded | timed out)`.
- **Dropouts:** a client that quits the wave (its `LanWaveSync._exit_tree` before cleanup sends `_rpc_left_wave`) or disconnects (`LanNet.player_disconnected`) loses its player: the host calls `die()`, which greys its name everywhere and counts for the run-lost check. The client that quit waits in the lobby with the in-wave hint and rejoins with the next run; one that disconnected is dropped from the lobby when the wave ends.
- **Run end:** the `main.gd` extension's `_set_run_states` sends the host's verdict `[wave failed, run lost, run won]` with `_rpc_wave_cleanup`; a client's `clean_up_room` uses it instead of its own, which could miss the last death (deaths travel in unreliable snapshots). Both still return to the lobby afterwards (until Step 7). `PROTOCOL_VERSION` 11.
- **Tested:** host + client + 3 fakes. Pause on the client: menu open, tree not paused, own player didn't move with a key held, the wave timer kept running; pause on the host: the wave kept running. Everyone killed on the host: both report wave failed and run lost. Client quitting the wave: its player dies on the host, the client sits in the lobby with the in-wave hint, then rejoins the lobby. Client process closed mid-wave: "ClientPlayer left", its player dies, the host plays on. 12 slots with 5× enemies: no `ERROR:`. Vanilla solo unchanged (cleared with an invulnerable player).
- **Not covered by the driver:** the 15 s load timeout (clients on one PC load within 0.1 s).

- **6f: loose ends.** The two visible mismatches left from 6b and 6d: spawn markers that vanilla moves away from a player, and materials that grow when new ones merge into them.

**6f status: done.**
- **Spawn markers** get u16 ids: the birth event is now `[2, birth id, type, pos, charmed_by]`. After vanilla's `spawn_entity_birth` the started marker is the last child of `_births_container` (from the pool or newly added) on both sides. Markers are pooled, so each keeps its current id in the `lan_birth_id` meta and older ids that still point at it are ignored. The host checks every physics frame whether an active marker moved (vanilla moves an enemy's marker to a random spot when a player stands on it) and sends `[14, birth id, pos]`; clients move their marker and restart its countdown, as vanilla does. Finished markers hide themselves and are dropped from the list.
- **Merged materials:** the host compares each synced item's scale every physics frame and sends `[13, id, scale]` when it changed; clients apply it. `PROTOCOL_VERSION` 12.
- **Bullet hell** needs nothing more: the patterns in use fire single projectiles (6c2); `GroupOfBullet` patterns are never picked.
- **Tested:** an enemy queued right on the host player: its marker moved, the move event arrived, and the client's marker list holds only current markers. 12 slots with 5× enemies: about 50 grown materials on both sides (scale 1.3 on the client at the same time as 1.35 on the host), no `ERROR:`. Vanilla solo unchanged.

## Step 7: Between-wave flow (upgrades and shop per machine)
Goal (milestone 5): after a wave, every machine picks its own level-up upgrades, processes its own crates and shops on its own screen; the host waits for everyone, merges the results and starts the next wave on all machines. Read [lan-coop-mod.md](lan-coop-mod.md) first (session flow, sync protocol, pitfalls).

**Design (original outline, still valid):**
1. **Host, at wave end:** run what vanilla runs before the upgrades, then send every client the authoritative run state plus each player's pending upgrades and crates (7a).
2. **Every peer, host included, sets up a solo between-wave phase** (7b), resolves the pending level-ups and crates with the solo `_upgrades_ui` flow (7c), then goes to the solo `shop.tscn` (7d).
3. **Shop "Go"** sends the own player data to the host and shows who is still shopping (7d).
4. **Host merge:** when all players are done, the host merges them and starts the next wave on every machine (7e).
5. **Run end:** solo end screens (7f).

**Increments.** Each is tested in two windows (driver plus manual test), then committed. The facts below were checked in 6e; adjust the split after reading the code. Milestone 5 is reached with 7e.

- **7a: wave-end state broadcast.** No new UI yet; every peer still returns to the lobby afterwards, as today.
  - **Where:** the `main.gd` extension's `_on_EndWaveTimer_timeout` (today: back to the lobby, temporary). Vanilla's version, for reference: a failed wave shows `_retry_wave` and returns; otherwise `RunData.on_wave_end()`, `LinkedStats.reset()`, then either `RunData.get_end_run_scene_path()` (run lost/won: `coop_end_run.tscn` / `end_run.tscn`) or the upgrades (7c), the challenge UI and the shop (7d).
  - **Host:** run `RunData.on_wave_end()` and `LinkedStats.reset()` as vanilla does, then send every client the run state and the pending upgrades and crates.
  - **Why the state must be sent:** client run data diverged during the wave. Gold/XP/level come from snapshots, but a client's `RunData` also got vanilla side effects (each `levelled_up` adds +1 max HP via `main.on_levelled_up`, half-wave stat conversions, wave-start rolls). So the host's state at wave end must replace the client's before the upgrades. Use `RunBuilder.serialize_run()` / `apply_run()` (JSON through the save loader, `ProgressDataLoaderV3.serialize_run_state` / `deserialize_run_state`) and the digest check, as Start does. JSON round trips turn ints into floats; `RunBuilder.apply_run` already fixes the known run-level keys.
  - **Pending upgrades and crates live in `main`, not in `RunData`:** `_upgrades_to_process[i]` (`UpgradesUI.UpgradeToProcess`: `level`, `player_index`) and `_consumables_to_process[i]` (`UpgradesUI.ConsumableToProcess`: `consumable_data`, `player_index`). They must be sent separately (levels and consumable `my_id`s).
  - **The wave verdict** is already the host's (`_rpc_wave_cleanup` with `[failed, lost, won]`), so all peers agree on "run end vs shop". On run end, keep returning to the lobby until 7f.
  - **Test:** after a wave the client's digest matches the host's, and each client received its own pending levels and crates.

**7a status: done.**
- **Host:** the `main.gd` extension's `_on_EndWaveTimer_timeout` runs `RunData.on_wave_end()` and `LinkedStats.reset()` unless the wave failed (vanilla's retry case), then `LanNet.send_wave_end_state(_upgrades_to_process, _consumables_to_process)`: serializes the run, applies its own copy from the same JSON (as Start), and sends `_rpc_wave_end_state(run_id, wave, json, digest, pending)` to every connected client (also those waiting in the lobby). `PROTOCOL_VERSION` 13.
- **Pending:** `RunBuilder.pack_pending` gives `[[levels], [consumable ids]]` per player; `is_valid_pending` checks the received one against the run (player count, int levels, known consumable ids).
- **Client:** keeps the message in `_incoming_wave_end` and applies it from `LanNet._process` once its own wave is over (`main._end_wave_timer_timedout`, or no longer in `main.tscn`, e.g. after following the host's lobby broadcast), since vanilla's end-wave code uses `RunData` until then. It runs `on_wave_end()` / `LinkedStats.reset()` itself too (vanilla side effects only; the state replaces its `RunData`). Then `apply_run`, digest and pending check, `LanNet.wave_end_state = {wave, pending, ok}`, ack `_rpc_wave_end_ack(wave, ok)`; the host logs it and keeps it in `_wave_end_acks`.
- **Digest** (`RunBuilder.summarize`) now also has the wave and each player's level and XP.
- **Failed wave** (everyone dead): nothing is sent, as before (7f).
- **Tested:** host + client + 1 fake (Engineer), 20 s wave ended cleared (driver: the old kill-everyone ending is now `KILL_ALL=1`), with a host level-up and a crate (vanilla handed it to the client's player): client "received and verified", pending `[[[1,2],[]],[[],["consumable_item_box"]],[[],[]]]` on both, the host got the ack. `KILL_ALL=1` (run lost): nothing sent. No `ERROR:`.
- **Note:** back in the lobby, vanilla's `title_screen.gd` `_ready` resets `RunData` on every peer that loads it (the host's run is gone there; a client that applies after loading the title screen keeps it). Harmless while the wave end still goes to the lobby; from 7c on, nobody passes through the title screen between waves.

- **7b: solo view swap.** A pair of helpers that turns the coop run into the local player's solo run and back, without UI changes yet.
  - **Enter:** stash the full `players_data`, set `RunData.players_data = [my_player_data]` and `set_coop_run(false)`.
  - **Must hold during the solo phase:** `RunData.get_player_count()` is 1, `is_coop_run` false, `CoopService.connected_players` describes only the local device, and per-player caches (`Utils` stat caches, `TempStats`, `LinkedStats`) are reset, since index 0 now means the own player.
  - **Per-player state outside `players_data`:** RunData keeps 4-slot arrays (grown to 12 by the mod) indexed by player. In a solo phase the own data sits at index 0, so these entries must move from slot `local_player_index` to 0 and back. List them by grepping `run_data.gd` for `[[], [], [], []]`-style initialisers and `player_index]`. A first grep finds `remove_speed_effect_cache`, `items_nb_cache`, `different_items_nb_cache`, `duplicate_items_cache`, `max_consumable_stats_gained_this_wave`, `tracked_item_effects`, `_are_player_stats_dirty`, `current_charmed_enemies`, `steps_taken_this_wave` (~L148-164) and `locked_shop_items` (~L193, reset ~L556). The reroll counts, free rerolls and item steals are not in `RunData` but in `base_shop.gd` (4-slot `_reroll_count`, `_paid_reroll_count`, `_initial_free_rerolls`, `_free_rerolls`, `_item_steals`, …) and reach the run state through `ProgressData.save_run_state` (7d).
  - **Leave:** put the own `PlayerRunData` and the per-player entries back into slot `local_player_index`, restore `players_data`, `is_coop_run` and `connected_players`, reset the caches again.
  - **Test (driver):** enter and leave right after 7a's state arrives; the digest is unchanged, and during the swap the solo invariants above hold.

**7b status: done.**
- **`game/solo_view.gd`** (`SoloView`, one instance as `LanNet.solo_view`; `LanNet.enter_solo_view()` / `leave_solo_view()`):
  - **Enter:** stashes `players_data`, `is_coop_run` and `connected_players`, sets `players_data = [own]`, `set_coop_run(false)` and `connected_players` to the local device only (`LanNet._get_local_coop_player`, the same entry `_fill_coop_players` uses, so it works whether or not the coop list is filled at that moment).
  - **Moved arrays** (slot `local_player_index` → 0, the other solo slots get fresh defaults so vanilla code that clears unused slots can't touch the stashed ones): `_players_die_args`, `remove_speed_effect_cache`, `max_consumable_stats_gained_this_wave`, `tracked_item_effects`, `current_charmed_enemies`, `steps_taken_this_wave`, `locked_shop_items`.
  - **Reset on enter and leave** (caches keyed by player index): `RunData.reset_run_caches()` (`items_nb_cache`, `different_items_nb_cache`, `duplicate_items_cache`), every `_are_player_stats_dirty` slot, `Utils.reset_stat_caches()` and `reset_last_elt_selected()`, `TempStats.reset()` (in-wave stats only; main already resets them in `clean_up_room`), `LinkedStats.reset()` (recomputed from the effects).
  - **Leave:** slot 0 of each moved array (even if vanilla replaced the array meanwhile) and `players_data[0]` go back into slot `local_player_index`; `players_data`, `is_coop_run` and `connected_players` are restored, caches reset again. `discard()` (session end) forgets the stash.
- **`LanNet.get_local_run_index()`:** 0 in the solo view, else `local_player_index`. The `focus_emulator_signal.gd` extension answers with it.
- **`LanNet` signal `wave_end_ready`:** emitted once `wave_end_state` is set (host: after sending, still in `main.tscn`; client: after applying). 7c's client waits for it.
- **Tested** (driver `solo_view_test` on `wave_end_ready`, host + client + 1 fake, client is index 1): in the solo view count 1, not coop, `connected_players` `[[7, 0]]`, own `PlayerRunData` and `tracked_item_effects` at 0, own max HP from the stat caches (client 11/11, host 17/17); after leaving the serialized run and the digest are identical on both. No `ERROR:`.

- **7c: solo upgrades on every machine.** After 7a's state, every peer enters the solo view and resolves its own level-ups and crates, then (temporarily) returns to the lobby.
  - Do **not** show `_coop_upgrades_ui` (it has only 4 slots).
  - Every pending element gets `player_index` 0 in the solo phase.
  - **Vanilla's solo flow to reuse:** `_upgrades_ui.show_options(_consumables_to_process, _upgrades_to_process)`, then yield `consumable_selected` / `upgrade_selected` per element and `options_processed`, removing the things-to-process icons as it goes (`_things_to_process_player_containers[0]`, whose `consumables` / `upgrades` lists drop each processed element). Then the challenge UI (`_challenge_completed_ui` `finished`, if shown).
  - **Test:** host and client each get their own upgrade choices and crates at the same time; picks change only the own player's stats.

**7c status: done.**
- **`main.gd` extension, `_on_EndWaveTimer_timeout`** (session, wave not failed): after 7a's part, a client waits for its wave-end state (`LanNet.wave_end_ready`, relayed as `main`'s own `lan_wave_end_ready` so the yield ends with the scene). Unless the run was lost or won (still straight to the lobby until 7f): hide the wave labels, stop the camera, `MusicManager.tween(-8)`, `LanWaveSync.stop()`, `LanNet.enter_solo_view()`, set up the solo `UpgradesUI` (its `_ready` returned early in the coop run, so it runs once more now), and vanilla's solo loop on `_upgrades_ui` with the own pending list from `wave_end_state` (`UpgradeToProcess` / `ConsumableToProcess` with `player_index` 0). The icons in the own things-to-process container (`_things_to_process_player_containers[local_player_index]`) are rebuilt from that list first, since a client's came from its own copy of the wave. Then the challenge UI, then (temporary) `leave_solo_view()` and the title screen.
- **`LanWaveSync.stop()`:** physics off and `LanNet.wave_sync` = null, so the host sends nothing more and a client drops late snapshots and events (they index players the solo `RunData` doesn't have).
- **HUD:** `on_gold_changed` / `on_xp_added` map RunData index 0 to the local player's HUD in the solo view (gold from recycling a crate item).
- **Temporary (until 7e):** a client in the solo view doesn't follow the host's "back in the lobby" broadcast; it goes there itself when done. If the host has nothing to pick and returns to the lobby before a client's end-wave timer ran, that client follows the host and skips its upgrades.
- **Pause** during the upgrades works as in the wave: `_check_for_pause` sees one player (index 0, the local device) in the solo view.
- **`LanNet`** logs entering and leaving the solo view (with the run summary on leaving).
- **Tested** (driver: host and client level up twice; three crates, one per player; the host takes its item, the client recycles its): both get their own "Level up!" screens at the same time with their own stats panel (client: the Brawler's). The client's recycle shows in its own HUD gold (44 → 51). Each pick lands only in the own slot: client harvesting `[9, 5, 0]` (host's 9 unchanged), host engineering `[2, 0, 11]` (the fake Engineer's 11 unchanged), the host's crate item only in its slot. `KILL_ALL=1` (run lost): straight to the lobby as before. A vanilla solo wave loads without errors (that run lost window focus, so vanilla's focus pause held it at 20 s). No `ERROR:`.

- **7d: solo shop and Go.** After the upgrades, every peer goes to the solo `shop.tscn` on its own data (vanilla: `_change_scene(RunData.get_shop_scene_path())`, which picks `coop_shop.tscn` / `shop.tscn` by `is_coop_run`, so the solo view yields `shop.tscn`).
  - Extend `ui/menus/shop/base_shop.gd` (still to come in the extension list): instead of vanilla's next-wave code, Go sends the own `PlayerRunData.serialize()` (exists in `singletons/player_run_data.gd`, along with `deserialize(dict)`; the run serializer uses them per player) plus the own per-player shop state from 7b to the host.
  - Then show "Waiting for: …" (`ui/net_player_list.gd`, not written yet).
  - **Vanilla shop "Go"** (`base_shop.gd` `_on_GoButton_pressed(player_index)`), for what Go replaces: waits until every local player pressed Go, `ProgressData.save_run_state(shop items, reroll counts, …)` (in memory; disk saves are blocked in a session), marks item locking for the candy-bag challenge, removes hourglass items and counts them as `wave_reset_count`, rolls `extra_elite_next_wave_chance`, then `RunData.current_wave += 1 - wave_reset_count` and `change_scene(MenuData.game_scene)`. The per-player parts (candy-bag item locking, hourglass, elite rolls) and the wave increment move to the host in 7e.
  - Until 7e, the host collects everyone's Go and then sends all peers back to the lobby.
  - **Test:** both machines shop independently; the waiting list updates as players press Go.

**7d status: done.**
- **`main.gd` extension:** after the upgrades and the challenge UI, `_change_scene(RunData.get_shop_scene_path())`, still in the solo view, so `shop.tscn` on the own data.
- **`extensions/ui/menus/shop/base_shop.gd`** (`Shop` picks it up, ModLoader reloads `class_name` children): in a session, Go doesn't run vanilla's next-wave code. It marks the candy-bag item locking (vanilla's Go reads the shop items locked on screen, which only this machine has, so this runs here and not on the host), opens the waiting overlay and calls `LanNet.send_shop_done(true)`. "Back to the shop" or cancel (vanilla's `_clear_go_button_pressed`) hides it and sends `send_shop_done(false)`. Vanilla clears Go when the Go button loses focus; the overlay takes the focus, so that is off in a session. The pause menu hides the overlay and shows it again afterwards.
- **`ui/shop_waiting_overlay.gd`** (instead of the planned `ui/net_player_list.gd`): full-screen dim (0.8, blocks the mouse), "Waiting for the others", "Still shopping: …", "Back to the shop" (focus stays on it). Added right after the shop's `Content`, so the pause menu's own handling (hide `Content`) doesn't apply and `on_paused` hides it instead.
- **`LanNet`** (`PROTOCOL_VERSION` 14):
  - `between_waves` (set when entering the solo view, cleared on the title screen or when everyone is done), `shop_done`, `shop_waiting_names`, signal `shop_waiting_changed`.
  - `send_shop_done(done)`: the own solo run (`RunBuilder.serialize_run()`, its slot 0 is the player with locked items and tracked effects) or `""` goes to the host as `_rpc_shop_done(wave, json)`; the host handles its own directly.
  - Host: `_shop_runs[player_index]` (checked with `RunBuilder.parse_solo_run`: save-loader deserialization without touching `RunData`, exactly one player), `_update_shop_waiting()` lists the host and every connected client not in `_left_run_peers` that hasn't sent its run, broadcasts `_rpc_shop_waiting(names)` on change, and goes on when the list is empty. Called on Go, Back, disconnect and quit.
  - `_left_run_peers`: `_rpc_left_wave` now also works between waves (no `LanWaveSync`); cleared when a wave is entered.
  - `on_title_screen()` (from the title-screen extension's `_ready`): a client that hadn't pressed Go sends `_rpc_left_wave`; any solo view is left; `between_waves` ends.
  - Clients follow the host's "back in the lobby" broadcast from `main.tscn` and from the shop (7c's exception for the solo view is gone: the host only returns there once everyone is done, or when it quits).
  - Fix for 7a: `_rpc_wave_end_state` carries `_run_id_counter`, not `lobby_settings.run_id`, which a disconnect during the run resets to 0 (clients would have dropped the state).
- **Temporary (until 7e):** once everyone is done, the host logs each result (gold, items, weapons, locked items), leaves the solo view and goes to the lobby; the clients follow.
- **Tested** (driver: each buys one shop item and locks another; the client presses Go, Back, Go again; the host is last): client overlay "Still shopping: HostPlayer", Back hides it and takes the Go back, Go again shows it; the host gets both results (e.g. player 1: gold 45, 3 weapons, 1 locked) and both end in the lobby. `SHOP_QUIT=1` (client quits from the shop): the host goes on after its own Go. Found and fixed on the way: vanilla's Go-button `focus_exited` took the Go back as soon as the overlay took the focus. No `ERROR:`.
- **Fix after the manual test (second run in one session):** the client still held the first run's `wave_end_state` (wave 1), so at the next run's wave 1 its end-wave code didn't wait, entered the solo view on stale data, and a frame later the new state replaced `RunData` with the coop run inside the solo view: `SCRIPT ERROR: Invalid get index '1'` in `upgrades_ui.gd` and a frozen `coop_shop.tscn`, in every later run of that lobby. Now `LanNet._reset_between_waves()` clears the wave-end and shop state whenever a wave is entered (host `_enter_wave_if_synced`, client `_rpc_enter_wave`) and at session end, and a wave-end state arriving during the solo view is dropped with a warning. Driver `ROUNDS=2` (the host starts a second run from the lobby) reproduced it without the fix (client in `coop_shop.tscn` with 3 players, three script errors) and passes with it.

- **7e: host merge and next wave (milestone 5).**
  - When all players are done, the host deserializes each player into `players_data[i]` (JSON round trips turn ints into floats, see 7a), puts their per-player shop state into their slots, and restores the coop run.
  - It runs the once-per-wave parts of vanilla's Go handler: `save_run_state`, hourglass items and `extra_elite_next_wave_chance` per player, then the wave increment **once** for everyone (`current_wave += 1 - wave_reset_count`). (The candy-bag item locking already ran on each machine at Go, 7d.)
  - **12-player fix needed:** `ProgressDataLoaderV3.deserialize_run_state` builds `locked_shop_items` as `[[], [], [], []]` and then loops over the state's slots (12 in a session), so `apply_run` fails as soon as a player with index 4+ has a locked shop item. Extend the loader (grow the result's `locked_shop_items` before the loop) before merging runs with locked items.
  - Inputs: `LanNet._shop_runs[player_index]` (solo run JSON; `RunBuilder.parse_solo_run` gives `players_data[0]`, `locked_shop_items[0]`, `tracked_item_effects[0]`). Players without a result (quit or disconnected) keep their wave-end state.
  - Then it sends the run state and everyone loads `main.tscn` (same path as Start: run state, digest, `_rpc_enter_wave`). Every peer leaves its solo view first.
  - **Gap carried over:** clients that left the wave mid-way sit in the lobby and need the run state when the next wave starts.
  - **Test:** several waves in a row on two machines; items bought on the client exist on the host in the next wave (and the reverse), gold and stats match.

**7e status: done (milestone 5).**
- **`LanNet._on_all_shops_done`:** leaves the host's solo view (its own result is what that leaves in its slot), merges every other player's result (`RunBuilder.merge_solo_run`: `players_data[0]`, `locked_shop_items[0]`, `tracked_item_effects[0]` converted like `resume_from_state` does), runs `RunBuilder.apply_go()` and sends the run with `_send_run`, which `start_run` now uses too (serialize, apply own copy, new run id, `_rpc_run_state`, acks, `_enter_wave_if_synced` → `_rpc_enter_wave`). Players without a result (quit or disconnected) keep their state from the wave's end.
- **`RunBuilder.apply_go()`:** vanilla's once-for-all parts of Go: hourglass items (removed, counted as `wave_reset_count`) and the `extra_elite_next_wave_chance` roll per player, `current_wave += 1 - wave_reset_count`, then the locked-item curse (DLC) per player, copied from `base_shop.gd` `_on_tree_exited`. The `base_shop.gd` extension skips `_on_tree_exited` in a session, since every machine would roll its own curses on the merged run. `ProgressData.save_run_state` is left out (disk saves are blocked in a session; the in-memory copy only feeds "Continue").
- **Client:** `_rpc_run_state` leaves the solo view first when the next wave's run comes while it waits in the shop.
- **Quit and disconnect:** clients that quit to the lobby (pause menu, during the wave or between waves) get the next run and are back in from the next wave (the gap from 6a). Disconnected players keep their slot; the host's `LanWaveSync` kills them again at the start of each wave (`_kill_disconnected_players`). A disconnect during a run no longer resets `lobby_settings.run_id` (`_broadcast_lobby_state(run_in_progress)`), so a next-wave sync waiting for acks goes on (`_enter_wave_if_synced` after the disconnect).
- **12 players:** `extensions/singletons/progress_data_loader_v3.gd` lets vanilla (de)serialize the first 4 slots of `locked_shop_items` and `shop_items` and does the rest the same way.
- **Tested** (driver `WAVES=n`: n waves with upgrades and shop, then both check the next wave 3 s in):
  - `FAKES=5 WAVES=2` (7 players, the driver locks an item for player 5 in wave 1): in wave 3 host and client have the same digest and the same gear for all 7 players; weapon nodes in the scene match RunData; the client's buys (claw, lightning shiv) are on its player on the host; locked items carry over (the host locked the slingshot in shop 1 and bought it in shop 2); player 5's locked item survives.
  - `CLIENT_QUITS=2 WAVES=2` (the client's process ends mid-wave 1): the host shops alone, waves 2 and 3 start, player 1 is dead in each.
  - Default (one wave, the host leaves in wave 2) and `KILL_ALL=1` (run lost → lobby) unchanged. No `ERROR:`.
- **Known gaps** (both resolved, see the gap review after 7f): if a client's digest differs for the next wave's run, the host waits for its ack forever (the client sits in the shop overlay); at Start the lobby shows it, between waves nothing does. `ROUNDS=n` (the regression test for the stale wave-end state) needs a run that ends in the lobby; with 7e only a lost run does (`KILL_ALL=1`), which sends no wave-end state, so it runs again with 7f's run end.

- **7f: run end.** On run won or lost, every peer shows the solo end screen for its own player. "Back" leaves the session for clients; the host returns to the lobby.
  - Vanilla's end-run path: `RunData.get_end_run_scene_path()` (`coop_end_run.tscn` / `end_run.tscn` by `is_coop_run`), so the solo view yields `end_run.tscn`.
  - A failed wave: vanilla shows `_retry_wave` and returns (only when `RunData.current_wave > 0`). Decide what a session does there.
  - **Gap carried over:** `ProgressData.reset_and_save_new_run_state()` runs on every peer when all players die (in-memory "Continue" disappears).
  - **Test:** win (last wave) and lose (everyone dies), with the end screen on both machines and Back from each.

**7f status: done (Step 7 complete).**
- **Decision:** everyone dead always ends the run in a session (lost; won past the last wave in endless). The retry screen isn't shown (a host-decided retry is in Step 8). Clients go back to the lobby, not out of the session, so the host can start the next run.
- **`main.gd` extension:** at the run's end the host still sends the wave-end state (also after a failed wave; `on_wave_end` runs only when the wave wasn't failed, as in vanilla), so the end screens show the host's numbers. Every peer stops `LanWaveSync`, sets `LanNet.run_over`, enters the solo view without the shop phase (`enter_solo_view(false)` doesn't start `between_waves` or the host's waiting list), restores `RunData.run_won` and `difficulty_unlocked` (cleared by applying the host's run) and opens `end_run.tscn`.
- **`extensions/ui/menus/run/base_end_run.gd`:** in a session Restart and New Run are hidden, Exit says "Back to the lobby" (`LAN_BACK_TO_LOBBY`) and gets the focus. `LanNet.on_title_screen()` discards the solo view (the title screen resets `RunData`).
- **Lobby hint:** a client back before the host sees "The run is over. Waiting for the host to leave the results." (`LAN_HINT_HOST_RESULTS`, `run_over`, reset when a wave starts).
- **Own saved run (the carried-over gap, and more):** saves are blocked in a session, but the shop (`save_run_state` in `_ready`, pause, Go) and a lost run (`reset_and_save_new_run_state`) change `ProgressData.saved_run_state` in memory. The next save after the session would have written the LAN run (or an empty one) over the player's own "Continue" run. The `progress_data.gd` extension now puts `saved_run_state` and `last_saved_run_state` aside when saves get blocked (session start) and restores them when they're unblocked (session end).
- **Shop:** the Endless button (shown at wave 19) is hidden in a session: `is_endless_run` is run-wide, but each machine would set it alone and the merge only takes per-player data.
- **Tested** (driver: both log the end screen and press Exit, the client first; `START_WAVE=n` starts the run at wave n; `FAKE_SAVED_RUN=1` puts a stand-in "Continue" run in memory before the session):
  - `KILL_ALL=1`: "Run Lost" on both, each with its own character, gold and weapons, only "Back to the lobby", focused; the client's lobby shows the run-over hint, the host's Exit returns both to the normal lobby.
  - `START_WAVE=20`: wave 20 cleared, "Run Won" on both (it showed "Run Lost" before `run_won` was restored).
  - `FAKE_SAVED_RUN=1`: the stand-in run (wave 7) is the same after leaving the session (same hash).
  - `ROUNDS=2 KILL_ALL=1` (the regression test for the stale wave-end state, now that a lost run sends one): both runs end on the end screens, round 2's client receives the state before entering the solo view.
  - Default (one wave, then wave 2): unchanged. No `ERROR:`.
- **Fix after the manual test (ticking in the upgrade screen):** vanilla's `WaveTimer.stop()` only pauses the timer and stops the tick timer, and its `_physics_process` restarts the tick while 0.1–6 s are left. A client's wave timer runs a little behind the host's (resynced only beyond 0.5 s), so the host's cleanup could pause it with time left, and the countdown ticked through the upgrades until the shop. In a session `clean_up_room` now also turns off the wave timer's physics process. Driver `TIMER_LAG=0.3` (the client's timer 0.3 s behind) reproduced it (`ticking=True` in the upgrades) and passes with the fix.

**Gap review before Step 8** (every "gap", "not covered" and "temporary" note in Steps 1–7 checked against the code):
- **Fixed now:**
  - A next-wave digest mismatch froze everyone (the host waited for an ok ack, the client refused `_rpc_enter_wave`). During a run both sides now log a warning and go on with the host's run (`_enter_wave_if_synced` once every connected client acked, `_rpc_enter_wave` when `in_wave`); at Start a mismatch still keeps everyone in the lobby.
  - A client that quit to the lobby could change its entry (character, weapon, ready) during the run; the host broadcast it, which reset the run id (and would have stalled a next-wave sync waiting for acks). The host now ignores entry changes while a run is in progress.
  - Driver: the client's pause-and-click step set its next time after its yields, so with `CLIENT_QUITS=1` the quit ran a frame later and the resumed step touched the freed scene (a `SCRIPT ERROR` in the driver, not the mod).
  - Tested: `FAIL_ACK=1 WAVES=2` (the driver turns the next wave's ack into a mismatch on the host and clears the client's run-ok flag): warning, wave 2 starts on both, wave 3 matches. `CLIENT_QUITS=1 WAVES=2` (the client quits wave 1 and changes its character in the lobby): ignored, the client is back in wave 2 as the Brawler, wave 3 matches. No `ERROR:`.
- **Resolved earlier:** Step 4's temporary wave end and the lost "Continue" (Step 7, 7f); 6a's gaps (6e, Step 7); 6b's moved spawn markers and 6d's grown materials (6f); 6d's client-side level-up effects (7a); 7c/7d's temporary returns to the lobby (7e); the stale wave-end state test (7f).
- **Still open:** moved into Step 8 (perf, tests, the quit client's lobby hint) and Step 9.

## Step 8: Polish
Goal: a smoother experience with what exists: visuals, controls, menus, small bugs, performance and test coverage. New mechanics, settings and modes are in Step 9. Read [lan-coop-mod.md](lan-coop-mod.md) first (session flow, sync protocol, pitfalls); the driver and test setup are in Verification below.

**Done early:** ~~floating names above players~~ (4c); ~~unlock everything in multiplayer~~ (after Step 3, see Step 1 "Unlocks"; the test save goes from 5 to 50 characters during a session, back to 5 after leaving, and the save file is not written).

**In the wave (visuals and controls):**
- Name overlap: 12 names overlap when players stand close together, for example on the spawn circle at wave start. If plain labels are too busy, fade names while they overlap, or shorten long names.
- ~~Off-screen teammates~~ (8a): `game/offscreen_arrows.gd`, a `Control` in main's `UI` layer right above the damage vignette (below the HUD and pause menu). Every frame it draws a triangle with a dark outline, in the player's colour, for each living non-local player whose screen position (`get_global_transform_with_canvas()`) is outside the viewport: on the line from the screen centre towards them, 36 px inside the edge. Hidden from cleanup on.
- ~~Remote players' colours applied to the outline~~: obsolete. Vanilla coop already gives every player the coloured highlight in their colour (`Player.update_highlight`, 12 colours from the `coop_service.gd` extension).
- ~~Dead players~~ (8a): vanilla's goat skull icon (`items/all/goat_skull/goat_skull_icon.png`, 48 px) as `LanDeadIcon` below the greyed-out name, where the hidden bar was. Only players with a name label (not the local one).
- ~~Mouse aim for keyboard players~~ (8a):
  - **Local player:** the `utils.gd` extension answers `is_manual_aim` for the local player in a session with vanilla's solo rules (`manual_aim`: always; `manual_aim_on_mouse_press`: while the left button or the right stick is pressed). The `main.gd` extension's `_handle_manual_aim_visuals` (vanilla returns in coop) shows the crosshair cursor for the mouse or the crosshair sprite for a gamepad, and keeps the cursor visible while mouse-aiming (LanNet's solo mouse rule hides it on keyboard input). Off while the pause menu is open or the local player is dead.
  - **Host:** `aim` in `_rpc_player_state` is now an aim point relative to the player: the mouse (`get_global_mouse_position() - position`) or the gamepad aim × 10000 (`GAMEPAD_AIM_DISTANCE`). Protocol 15. Remote players count as keyboard players on the host (device -1), so vanilla's weapons turned towards the **host's** mouse in manual aim, also for remote gamepad players (a bug since 6a). The `weapon.gd` extension overrides `get_global_mouse_position` and returns `LanWaveSync.get_remote_aim_point` (player position + reported aim) for remote players on the host, so each weapon turns towards that point as vanilla does with the mouse; the far point gives a gamepad's parallel aim.
  - Tested (`AIM_TEST=1 FAKES=5`): the client's mouse at its top left, its own first weapon and the host's copy both at -159°; before the client's mouse moved, the host's copy at 0° (gamepad default). Without `AIM_TEST` auto-aim is unchanged; solo role unchanged. Arrows: host on the client's screen and the client on the host's (screenshots), skull under Fake2. No `ERROR:`.

**Menus and lobby:**
- ~~Lobby layout~~ (8b, `ui/lobby.gd`):
  - **Layout** (chosen by the user): player list on the left (620 px). Right: two columns, character (9-column grid, 760 px) and starting weapon (4-column grid); below each grid its preview; Ready under the weapon preview. The weapon preview and Ready together are as tall as the character preview (440 px). The grids scroll and take the height the left side leaves (at least 150 px), so both previews and Ready end level with Start (asked for after the first version, which had 250 px grids). The weapon area keeps its height when the no-choice text replaces the grid, so the previews never move.
  - **Previews:** both are vanilla's small item panel (`item_panel_ui.tscn`), also for the character: no animated character or tile background, the name in the item panel's 26 px font with its category. The icon box is hidden (the grid shows the icon); the name's scroll box gets 64 px height, which the icon box gave it. The description scrolls inside the panel (`expand_indefinitely = false`, set before its `_ready`, as vanilla's selection screens do); its scroll box fills what the panel leaves (min 100 px) instead of vanilla's fixed 265 px, which pushed the character preview past its 440 px. The character preview adds the starting weapons and items (as vanilla's character panel lists them) as a vanilla `Inventory` with vanilla's `ItemPopup` on hover, focus and press, as in vanilla's character panel (asked for after the first version, which had icons with the name as tooltip). The popup is the page's last child, so it draws over everything; it shows without synergies and without the last-wave line (`display_item_data`, not `display_element`, which reads run data). The row is refilled only when the shown character changes, so a focused item survives lobby updates.
  - **What a preview shows:** with the cursor visible, the last hovered element; with it hidden (keyboard or gamepad; LanNet's solo mouse rule), the focused one; else the player's pick (nothing if none). With the mouse, focus stays where a pick moved it (the weapon grid, Ready), so it doesn't count. A hover ends when the mouse leaves the grid and its preview (checked on mouse motion), not when it leaves the element, so the mouse can reach a hovered character's starting items. The focused character stays while the focus moves on to its starting items (checked deferred: during a focus change the old element reports the loss before the new one gets it). The grids' hovered/focused/unfocused signals and a cursor change (checked deferred in `_input`) update both previews; a refilled weapon grid drops its hovered/focused elements.
  - **Focus:** "left" from the weapon grid's first column and from Ready goes to the picked character (was "up" from the weapon grid when it sat below); "up" from Ready too when the character has no weapon choice.
  - Tested with the driver's `lobby` role (screenshots: a character hovered (Mage, with its starting items), a weapon hovered, nothing hovered: Well-Rounded and Knife, the picks) and the default host/join run. No `ERROR:`.
  - **Fix after the manual test:** a client back in the lobby from the shop logged `SCRIPT ERROR`s in vanilla's `effect_line.gd` when the next wave loaded. The title screen leaves the tree children first; the focused character element's `focus_exited` then refilled a preview whose nodes were already out. `_update_previews` now returns unless both panels are in the tree. `SHOP_QUIT=1` reproduced it (the previous `lobby.gd` didn't) and passes with the fix.
  - **Second pass (user request):** starting items with vanilla's popup, grids grown so the previews and Ready end level with Start (see Layout, Previews, What a preview shows). Tested with the `lobby` role (all bottoms at y = 1015 at 1080p, popup shown, keyboard focus kept on Mage through its starting item) and `SHOP_QUIT=1`. No `ERROR:`.
- Lobby hint for a client that quit to the lobby: it shows "A wave is in progress" until the host is back from its end screen, since it gets no end-of-run notice there (`LanNet.run_over` is only set in `main`). The host's wave-end state at the run's end, or the lobby broadcast, could carry it.
- Default player name: if the player never set one, pick a random funny name from a predefined list that fits the game (potatoes, aliens, weapons, e.g. "Spud Lightyear", "Tater Tot", "Mashed Menace"). This replaces the current "Player123" in `net_config.gd`.
- Controller text entry: an on-screen keyboard for the name and the join address. Until then, controller players keep the default name and join from the discovered games list.
- End screen focus: vanilla's `end_run.gd` gives the focus to the (hidden in a session) New Run button after an inventory element is pressed; with a gamepad the focus is then lost until the mouse or a direction moves it.

**Performance (milestone 6's perf pass):**
- Snapshot size: above about 190 entities a snapshot exceeds one UDP packet and ENet fragments it (6b). Split it if that drops snapshots.
- Spawn rate: `EntitySpawner` releases queued enemies at a fixed rate (1, or 2 with 110+ queued, every 3 physics frames, so 20–40/s), whatever the player count. Measure 12 slots at a late wave (15–20) with the normal multiplier: queue length and enemies alive. If the queue limits the count, release `ceil(n / 4)` per tick before raising enemy HP; watch host CPU and snapshot size.

**Tests not done yet:**
- Pets (same data-ref path as structures, 6b).
- The 15 s load timeout (6e; clients on one PC load within 0.1 s).
- Real separate machines, and more than two real players (the driver fills slots with fake lobby players that are never sent anything).
- Keyboard-only and gamepad-only on host and client through lobby, wave, upgrades, shop and end screen.

**Ongoing rule:** no `push_error` or script errors from mod code. Any `ERROR:` in the log that mentions `mods-unpacked` makes the crash reporter disable mods on the next launch.

## Step 9: Feature additions
New mechanics, settings and modes beyond vanilla co-op on separate machines. Each needs a design decision first.
- Mod config in the manifest `config_schema` (ModLoader's mod settings): the scaling knobs (now in `lan_coop.cfg` `[scaling]`, Step 5), the port, and the settings below that the host chooses.
- Material sharing option: vanilla coop splits every material a player picks up round-robin over all players (1 material and 1 XP per unit, `main.gd` `on_gold_picked_up`, also the mod's copy for > 4 players); only the picker's own pickup effects apply. Add a lobby setting (host, synced like the scaling knobs) to keep materials and XP with the player who picked them up instead. Crates have their own vanilla option (`share_coop_loot`).
- Upgrade countdown: with many players, waiting for everyone to pick their level-up upgrades and shop between waves gets tedious. Consider a countdown that starts once some players are done, or after a fixed time. When it runs out, the host marks the remaining players ready by picking their upgrades for them (e.g. the first or a random option) and pressing Go with their wave-end state. Make the duration a config knob, with 0 = off. (The host's waiting list is `LanNet._update_shop_waiting`, 7d.)
- Rejoin a run in progress after a lost connection (not after the player died). Today a disconnect kills the player (6e) and it stays dead in later waves (7e). Instead: keep the disconnected player alive but idle (or protected) for a grace period, let the same machine reconnect into its old slot (match by name or a session token from the hello), send it the current run state and drop it straight into the running wave (or the between-wave phase). A player who died stays out until the next wave as before. (Quitting to the lobby and rejoining with the next wave already works, 7e.)
- Retry in a session: vanilla's retry screen (`retry_wave` option) restarts the wave from `start_wave_state`. A session skips it (7f); the host could offer the retry and send the start-of-wave run to everyone.
- Endless runs: a lobby setting for the host instead of the shop's Endless button at wave 19 (hidden in a session, 7f).
- Progress from LAN runs: `RunData.apply_run_won` (in `clean_up_room`) completes the character challenges and difficulty records for every player's character on every machine, and challenges completed in a session may be dropped when the own unlock lists are restored on leaving. Decide what a LAN run should count for, and credit only the own character on each machine.
- Game modes (beyond co-op):
  - Teams: players split into teams (lobby choice), each team sharing materials among itself, compared by a score at the end (kills, waves survived, damage).
  - Last man standing: the run goes on while players die off; the last player alive wins. Needs a decision on what the dead do (spectate), how waves scale as players drop out, and whether players can hurt each other.

---

## Milestones
Status: milestones 1–5 are done (3 and 4 with Step 6, 5 with Step 7e). Steps 4 (12 players in a wave, names over heads) and 5 (arena, enemy scaling, camera) also cover part of milestone 6. Step 7 (between-wave flow, run end) is complete; next is Step 8 (polish, including milestone 6's perf pass), then Step 9 (feature additions).
1. **Docs.** Step 0, plus the `mod_main` fix.
2. **Connect.** Menu button → host/join → lobby with names, characters, ready. Verify on 2 local instances.
3. **Sync.** ~~Synced run start, then the host simulates and clients puppet players only, with no enemies~~ (6a).
4. **Full wave.** ~~Enemies, projectiles, pickups, and wave end~~ (Step 6).
5. **Between waves.** ~~Per-machine upgrades/shop and merge, so the loop runs for multiple waves~~ (7a–7e).
6. **Scale.** ~~12-player caps~~ (Step 4), ~~larger arena, enemy scaling~~ (Step 5), ~~names and health bars over heads~~ (4c), ~~disconnect handling~~ (6e, 7d, 7e; rejoining after a lost connection is in Step 9), perf pass (Step 8).

## Critical files to extend
**Already extended:** `singletons/progress_data.gd`, `ui/menus/title_screen/title_screen_menus.gd`, `ui/menus/ingame/ingame_main_menu.gd`, `ui/menus/global/popup_manager.gd`, `main.gd`, `entities/units/movement_behaviors/player_movement_behavior.gd`, `global/entity_spawner.gd`, `global/stats_manager.gd`, `singletons/coop_service.gd`, `singletons/debug_service.gd`, `singletons/run_data.gd`, `singletons/utils.gd`, `singletons/zone_service.gd`, `entities/units/player/player.gd`, `entities/birth/entity_birth.gd`, `weapons/weapon.gd`, `projectiles/projectile.gd`, `entities/units/enemies/enemy.gd`, `entities/structures/turret/turret.gd`, `singletons/weapon_service.gd`, `items/global/item.gd`, `ui/menus/ingame/pause_menu.gd`, `singletons/focus_emulator_signal.gd`. `TempStats`/`LinkedStats` arrays are grown from `LanNet._ready` instead of an extension.

**Also extended:** `ui/menus/shop/base_shop.gd` (7d), `singletons/progress_data_loader_v3.gd` (7e).

## Verification
- **Local multi-instance testing.**
  - Run 2–4 game instances on one PC (Godot 3.7 editor "Run multiple instances", or the game exe with mod loading). Each instance needs a separate `user://` (`--user-data-dir` or a separate profile) so saves and config don't collide.
  - Host on 127.0.0.1.
  - Run with `-vvv` and watch `ModLoaderLog` output.
  - **Windows that are covered or unfocused stall on vsync** under Wayland/XWayland, which also stops the network poll. Turn vsync off (`display/window/vsync/use_vsync=false`) and tile the windows with `--position`.
  - Without `config/custom_user_dir_name`, instances use the real `~/.local/share/Brotato` save and log. For throwaway tests, copy the project and set a separate user dir name in the copy.
- **Test setup used so far (Steps 2–7).** `tools/make_test_copy.sh <scratch>/game` builds it in one go (about 300 MB, a few seconds). The driver lives in the repo as `tools/lan_test_driver.gd` and is symlinked into the copy, so edits to it are tracked. It is not in the release zip.
  - **Throwaway copy** (what the script does). `cp -a Decompiled <scratch>/game`, then remove its `.git`. Replace `mods-unpacked/Moolt-Lan_Coop` with an **absolute** symlink to `brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop`, and symlink `tools/lan_test_driver.gd` as `lan_test_driver.gd`. In the copy's `project.godot`:
    - `config/custom_user_dir_name="BrotatoLanTest"` (under `[application]`)
    - `window/vsync/use_vsync=false` (under `[display]`)
    - an autoload `LanTestDriver="*res://lan_test_driver.gd"` after `OS_Seaven`
  - **Running.** `Godot/Godot_v3.7-dev1_x11.64 --path <scratch>/game --resolution 1280x720 --position 0,0 -- <role>` (second instance at `--position 1280,0`). Start `host` with `nohup ... &`, wait 1 s, start `join` the same way, then `wait`; stdout goes to `host.log` / `join.log`. The driver quits each instance at the end of its script.
    - First run one instance with role `quit` (quit as soon as the title screen loads) to catch parse errors cheaply.
    - The two instances share `user://lan_coop.cfg` (names, port 24999 in that profile).
  - **Driver.** Roles: `host`, `join`, `solo`, `lobby` (hosts alone, screenshots the lobby with a character hovered, a starting item's popup, a weapon hovered, nothing hovered; then with the keyboard focuses Mage and its first starting item and logs that the preview keeps Mage until Ready has the focus; quits), `quit`, or none (idle, for manual tests); see its header. Its step scripts follow the latest feature under test and get edited for the next one. `lan_test_driver.gd` reads the role from `OS.get_cmdline_args()`. In `_process` it waits for `current_scene.filename == MenuData.title_screen_scene`, then finds `Menus` and runs a timed `match step` script that drives the pages by calling their handlers directly:
    - `LanMultiplayerButton.emit_signal("pressed")`, `mp._host_button`, `join._first_row()`
    - lobby `_on_CharacterGrid_element_pressed(element)`, `_on_ReadyButton_pressed()`, `_on_StartButton_pressed`
    - it prints `[TEST] ...` lines and saves screenshots: `get_viewport().get_texture().get_data()`, `flip_y()`, `save_png()` into `$SHOT_DIR`
    - each step sets `next_t` *before* any `yield`, otherwise `_process` re-enters the same step
    - fake lobby players: append `NetProtocol.new_player_entry(...)` to `LanNet.players` (peer ids 1000+, with `character_id`, `weapon_id`, `ready = true`), then `_broadcast_lobby_state()`. They are never sent anything, because only connected peers count, so the host can start a 12-player wave alone.
    - in the wave (Step 4): `get_tree().current_scene` is `main`; read `_players`, `_players_ui`, `_wave_timer`, `get_node("%LifeContainerP12")`; move the host with `Input.action_press("button_move_right_7")`; kill a player with `_players[i].die()`; open/close the pause menu with `_pause_menu.pause(0)` / `unpause()`; Quit with `_pause_menu.get_node("Menus/MenuConfirm")._on_ConfirmButton_pressed()`
    - role `solo`: `RunBuilder.build_run` with one entry, then `set_coop_run(false)` and `change_scene(MenuData.game_scene)`, to check that vanilla solo play still works without a session
    - the game starts in a splash scene (`res://pause.tscn`); wait for the title screen before counting time
    - between waves (Step 7), outside the step script, every frame: `pick_upgrades` (in the solo upgrades UI: first upgrade, or take the crate item on the host and recycle it on the client; logs the picked upgrade's stat for every player from the solo view's stash and the coop run), `shop_actions` (buy one item, lock another, Go; the client goes Back and Go again; the host is last), `end_screen_actions` (log the end screen, Exit: the client first). `solo_view_test` (on `LanNet.wave_end_ready`) enters and leaves the solo view once and checks the run is unchanged. `log_run_check` prints every player's gear, the scene's weapon nodes and the digest; compare host and client.
    - **Environment options** (combine as needed; the header lists them too): `FAKES=n` fake players (the first an Engineer); `ENEMY_MULT=x`; `KILL_ALL=1` everyone dies in wave 1 (run lost); `WAVES=n` n waves with upgrades and shop, then both check wave n+1; `ROUNDS=n` n runs in one session (needs a run that ends, e.g. with `KILL_ALL=1`); `START_WAVE=n` the run starts at wave n (20: run won); `CLIENT_QUITS=1` the client quits the wave from its pause menu and changes its character in the lobby (ignored), `=2` its process exits mid-wave; `SHOP_QUIT=1` the client quits from the shop; `FAIL_ACK=1` the next wave's run counts as a digest mismatch on both sides; `TIMER_LAG=s` the client's wave timer s seconds behind; `FAKE_SAVED_RUN=1` a stand-in "Continue" run in memory before the session (never saved); `AIM_TEST=1` manual aim on both, the client's mouse at its top left (`log_visuals`, part of `log_sync`, logs off-screen players, skulls, manual aim, every player's first weapon rotation and the host's reported aims).
    - Regression set used for Step 7: default, `KILL_ALL=1`, `FAKES=5 WAVES=2`, `CLIENT_QUITS=1 WAVES=2`, `CLIENT_QUITS=2 WAVES=2`, `SHOP_QUIT=1`, `START_WAVE=20 FAKE_SAVED_RUN=1`, `ROUNDS=2 KILL_ALL=1`, `FAIL_ACK=1 WAVES=2`, `TIMER_LAG=0.3`; each about 1–2 min. A bug is first reproduced with a new option without the fix (e.g. `git stash` the mod change), then checked with it.
  - **Runner script.** Keep a small script in the scratchpad (e.g. `run2.sh`) that checks `game/project.godot` exists, exports `SHOT_DIR`, starts `host` and 1 s later `join` with `nohup`, and `wait`s. Call it by absolute path.
  - **Test infra pitfalls:**
    - The session scratchpad can be emptied between sessions. Godot started with `--path` to a missing copy opens the editor on the last project, `Decompiled/`, which may re-save vanilla files; rebuild the copy first (`tools/make_test_copy.sh`) and check `git status` in `Decompiled/` afterwards.
    - Stopping test instances: list the PIDs in one command (`ps -eo pid,args | grep "[G]odot_v3.7-dev1_x11.64 --path game"`) and kill them in a separate one. In the same command line as the game's own invocation the pattern matches the shell itself, which then kills itself.
    - `rm` of a glob after a `cd` in the same command is refused by Claude Code's safety check (the whole command doesn't run); screenshots overwrite by name, so there is no need to clear them.
  - **Log check.** `grep -a "SCRIPT\|ERROR"` the logs, then filter out the engine shutdown errors (`_first != nullptr`, resources/MemoryPool still in use, ObjectDB leaks). `--disable-mods` shows vanilla prints these too. `WARNING: Node './Attach' was modified from inside an instance` on wave load is vanilla as well. A stray background instance from an earlier run can mix into results, so check `ps` first.
  - **Manual test by the user.** Two windows: `--resolution 1280x720 --position 0,0` and `--position 1280,0`, with no role argument (the driver stays idle), started with `nohup`. Commit only after the user approves.
- **Per milestone:**
  - M2: names, characters and ready flags show up on every instance. Start is disabled until all players are ready.
  - M3/M4: client movement is visible on the host and the other way round, with no delay on one's own player. Enemies, hits, deaths and gold match. Killing the client process mid-wave doesn't crash the host.
  - M5: shops on different machines finish in any order. Bought items persist into the next wave on all peers (compare `RunData` dumps).
  - M6: use debug devices or headless dummy clients that send scripted random input to fill 12 slots. Check FPS and bandwidth with about 300 enemies, check the arena scales, and check spawn counts against the formula.
- **Also test** keyboard-only and gamepad-only on both host and client, including menu and lobby navigation.
