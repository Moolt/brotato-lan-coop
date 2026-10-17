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
  - **Wave end, temporary until Step 7.** In a session, `main.gd` `_on_EndWaveTimer_timeout` skips vanilla's coop upgrade UI and shop, which only have 4 slots. It sets `run_in_progress` false and changes back to the title screen, where the lobby reopens (`_restore_lan_page`). Quitting from the pause menu does the same.

**4a status: done.**
- **Start → wave:** `LanNet.start_run()` sets `_start_requested`. `_enter_wave_if_synced()` runs after the build and after every ack; once `get_run_sync_status()` is "synced" it calls `set_run_in_progress(true)`, `_fill_coop_players()` and `change_scene(MenuData.game_scene)`. A lobby change before then resets the run and cancels the start.
- **`lobby_settings.in_wave`** (`PROTOCOL_VERSION` 4) mirrors `run_in_progress`; clients show `LAN_HINT_HOST_IN_WAVE`.
- **Back to the lobby:** the `title_screen_menus.gd` extension calls `set_run_in_progress(false)` in `_ready`, so wave end and pause-menu Quit share one path. That drops players who left during the wave and resets `run_id` (the run was played, Start builds a fresh one). `main_menu.gd` `_ready` already calls `CoopService.clear()`.
- **Pause check:** the plan's assumption was wrong for `main.gd` `_check_for_pause`: it polls `Input.is_action_just_released("ui_pause_-1")`, an unknown action. The `main.gd` extension overrides it to skip negative devices.
- **Pause menu:** Restart and End Run are hidden in a session (`ingame_main_menu.gd` extension, `init`).
- **Tested:** host + one client, Danger 3. The wave loads with devices `[7, -1]`, the host moves with the keyboard, the remote player stands still. Wave end and Quit both reopen the lobby on the host; the client hint switches to "test wave" and back.
- **Known gap:** `main.gd` calls `ProgressData.reset_and_save_new_run_state()` when all players die. The disk save is blocked, but the in-memory `saved_run_state` is cleared, so "Continue" disappears until the game restarts.

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
- **Known gaps** (later increments): the host starts the wave without waiting for clients to load (the client's timer resyncs; 6e); a client quitting from its pause menu leaves its player standing on the host (6e); pause only pauses the own machine (6e); client-side `RunData` changes during the wave (e.g. random stat rolls at wave start) diverge, which Step 7's state broadcast overwrites.

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
- **Not covered yet:** pets weren't in the test (same data-ref path as structures). Snapshots with more than about 190 entities exceed one UDP packet and get fragmented by ENet; split them in the perf pass if that drops snapshots. A host-side spawn marker that vanilla moves away from a player isn't moved on clients (the enemy then appears where the host spawns it).

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
- **6e: pause, dropouts and run end.** Pause (`ui/menus/ingame/pause_menu.gd` `pause()` shows the menu without `get_tree().paused`; `pause_on_focus_lost` is already off in a session), the host waiting for clients to load before the wave timer starts, players dropping out or quitting mid-wave (their player dies or stands still on the host; the host leaving ends the session), run won/lost events.

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
- ~~Floating names above players.~~ Moved into 4c.
- Name overlap: 12 names overlap when players stand close together, for example on the spawn circle at wave start. If plain labels are too busy, fade names while they overlap, or shorten long names.
- Off-screen teammates: clients' cameras follow only the local player (Step 5), so teammates can be off-screen. Show a small arrow at the screen edge in their colour, pointing towards them.
- Remote players' colours applied to the outline (`CoopService.change_stylebox_for_player`).
- Mod config knobs exposed in the manifest `config_schema`: the scaling knobs (now in `lan_coop.cfg` `[scaling]`, Step 5), port.
- Default player name: if the player never set one, pick a random funny name from a predefined list that fits the game (potatoes, aliens, weapons, e.g. "Spud Lightyear", "Tater Tot", "Mashed Menace"). This replaces the current "Player123" in `net_config.gd`.
- ~~Unlock everything in multiplayer.~~ Done early (after Step 3), see Step 1 "Unlocks". Verified: the test save goes from 5 to 50 characters during a session, back to 5 after leaving, and the save file is not written.
- Controller text entry: an on-screen keyboard for the name and the join address. Until then, controller players keep the default name and join from the discovered games list.
- Avoid `push_error` from mod code. Any `ERROR:` in the log that mentions `mods-unpacked` makes the crash reporter disable mods on the next launch.
- Spawn rate: `EntitySpawner` releases queued enemies at a fixed rate (1, or 2 with 110+ queued, every 3 physics frames, so 20–40/s), whatever the player count. Measure 12 slots at a late wave (15–20) with the normal multiplier: queue length and enemies alive. If the queue limits the count, release `ceil(n / 4)` per tick before raising enemy HP; watch host CPU and snapshot size.
- Mouse aim for keyboard players: vanilla coop disables it (`Utils.is_manual_aim`), but in a session every player has their own mouse. Allow it for the local player, and send the aim direction to the host (6a already sends `aim`/`manual_aim`).
- Lobby layout (`ui/lobby.gd`):
  - Show the selected character's and the selected weapon's previews at the same time.
  - While an entry is hovered, its preview shows (as now); once nothing is hovered, the preview goes back to the current selection.
  - Lay out the character and weapon lists and their previews so both fit and display correctly.
  - Simplify vanilla's preview panels if possible: no character preview animation (it takes a lot of space), a smaller font for the character name, no repeated icon of the selected entry in the preview.
- Dead players: a skull image below the greyed-out name over their head (4c labels in the `main.gd` extension).
- Upgrade countdown: with many players, waiting for everyone to pick their level-up upgrades between waves gets tedious. Consider a countdown that starts once some players are done, or after a fixed time. When it runs out, the host marks the remaining players ready by picking their upgrades for them (e.g. the first or a random option). Make the duration a config knob, with 0 = off.

---

## Milestones
Status: 1, 2 and 3 are done (3 with Step 6a). Steps 4 (12 players in a wave, names over heads), 5 (arena, enemy scaling, camera) 6b (enemies on clients) and 6c (attacks, projectiles, hit feedback) are done. Next is Step 6d (materials, consumables, player stats), then 6e (pause, dropouts, run end).
1. **Docs.** Step 0, plus the `mod_main` fix.
2. **Connect.** Menu button → host/join → lobby with names, characters, ready. Verify on 2 local instances.
3. **Sync.** ~~Synced run start, then the host simulates and clients puppet players only, with no enemies~~ (6a).
4. **Full wave.** Enemies, projectiles, pickups, and wave end.
5. **Between waves.** Per-machine upgrades/shop and merge, so the loop runs for multiple waves.
6. **Scale.** ~~12-player caps~~ (Step 4), ~~larger arena, enemy scaling~~ (Step 5), ~~names and health bars over heads~~ (4c), disconnect handling, perf pass.

## Critical files to extend
**Already extended:** `singletons/progress_data.gd`, `ui/menus/title_screen/title_screen_menus.gd`, `ui/menus/ingame/ingame_main_menu.gd`, `ui/menus/global/popup_manager.gd`, `main.gd`, `entities/units/movement_behaviors/player_movement_behavior.gd`, `global/entity_spawner.gd`, `global/stats_manager.gd`, `singletons/coop_service.gd`, `singletons/debug_service.gd`, `singletons/run_data.gd`, `singletons/utils.gd`, `singletons/zone_service.gd`, `entities/units/player/player.gd`, `entities/birth/entity_birth.gd`, `weapons/weapon.gd`, `projectiles/projectile.gd`, `entities/units/enemies/enemy.gd`, `entities/structures/turret/turret.gd`, `singletons/weapon_service.gd`. `TempStats`/`LinkedStats` arrays are grown from `LanNet._ready` instead of an extension.

**Still to come:** `items/global/item.gd`, `ui/menus/ingame/pause_menu.gd` (Step 6), `ui/menus/shop/base_shop.gd` (Step 7).

## Verification
- **Local multi-instance testing.**
  - Run 2–4 game instances on one PC (Godot 3.7 editor "Run multiple instances", or the game exe with mod loading). Each instance needs a separate `user://` (`--user-data-dir` or a separate profile) so saves and config don't collide.
  - Host on 127.0.0.1.
  - Run with `-vvv` and watch `ModLoaderLog` output.
  - **Windows that are covered or unfocused stall on vsync** under Wayland/XWayland, which also stops the network poll. Turn vsync off (`display/window/vsync/use_vsync=false`) and tile the windows with `--position`.
  - Without `config/custom_user_dir_name`, instances use the real `~/.local/share/Brotato` save and log. For throwaway tests, copy the project and set a separate user dir name in the copy.
- **Test setup used so far (Steps 2–4).** `tools/make_test_copy.sh <scratch>/game` builds it in one go (about 300 MB, a few seconds). The driver lives in the repo as `tools/lan_test_driver.gd` and is symlinked into the copy, so edits to it are tracked. It is not in the release zip.
  - **Throwaway copy** (what the script does). `cp -a Decompiled <scratch>/game`, then remove its `.git`. Replace `mods-unpacked/Moolt-Lan_Coop` with an **absolute** symlink to `brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop`, and symlink `tools/lan_test_driver.gd` as `lan_test_driver.gd`. In the copy's `project.godot`:
    - `config/custom_user_dir_name="BrotatoLanTest"` (under `[application]`)
    - `window/vsync/use_vsync=false` (under `[display]`)
    - an autoload `LanTestDriver="*res://lan_test_driver.gd"` after `OS_Seaven`
  - **Running.** `Godot/Godot_v3.7-dev1_x11.64 --path <scratch>/game --resolution 1280x720 --position 0,0 -- <role>` (second instance at `--position 1280,0`). Start `host` with `nohup ... &`, wait 1 s, start `join` the same way, then `wait`; stdout goes to `host.log` / `join.log`. The driver quits each instance at the end of its script.
    - First run one instance with role `quit` (quit as soon as the title screen loads) to catch parse errors cheaply.
    - The two instances share `user://lan_coop.cfg` (names, port 24999 in that profile).
  - **Driver.** Roles: `host`, `join`, `solo`, `quit`, or none (idle, for manual tests); see its header. Its step scripts follow the latest feature under test and get edited for the next one. `lan_test_driver.gd` reads the role from `OS.get_cmdline_args()`. In `_process` it waits for `current_scene.filename == MenuData.title_screen_scene`, then finds `Menus` and runs a timed `match step` script that drives the pages by calling their handlers directly:
    - `LanMultiplayerButton.emit_signal("pressed")`, `mp._host_button`, `join._first_row()`
    - lobby `_on_CharacterGrid_element_pressed(element)`, `_on_ReadyButton_pressed()`, `_on_StartButton_pressed`
    - it prints `[TEST] ...` lines and saves screenshots: `get_viewport().get_texture().get_data()`, `flip_y()`, `save_png()` into `$SHOT_DIR`
    - each step sets `next_t` *before* any `yield`, otherwise `_process` re-enters the same step
    - fake lobby players: append `NetProtocol.new_player_entry(...)` to `LanNet.players` (peer ids 1000+, with `character_id`, `weapon_id`, `ready = true`), then `_broadcast_lobby_state()`. They are never sent anything, because only connected peers count, so the host can start a 12-player wave alone.
    - in the wave (Step 4): `get_tree().current_scene` is `main`; read `_players`, `_players_ui`, `_wave_timer`, `get_node("%LifeContainerP12")`; move the host with `Input.action_press("button_move_right_7")`; kill a player with `_players[i].die()`; open/close the pause menu with `_pause_menu.pause(0)` / `unpause()`; Quit with `_pause_menu.get_node("Menus/MenuConfirm")._on_ConfirmButton_pressed()`
    - role `solo`: `RunBuilder.build_run` with one entry, then `set_coop_run(false)` and `change_scene(MenuData.game_scene)`, to check that vanilla solo play still works without a session
    - the game starts in a splash scene (`res://pause.tscn`); wait for the title screen before counting time
  - **Log check.** `grep -a "SCRIPT\|ERROR"` the logs, then filter out the engine shutdown errors (`_first != nullptr`, resources/MemoryPool still in use, ObjectDB leaks). `--disable-mods` shows vanilla prints these too. `WARNING: Node './Attach' was modified from inside an instance` on wave load is vanilla as well. A stray background instance from an earlier run can mix into results, so check `ps` first.
  - **Manual test by the user.** Two windows: `--resolution 1280x720 --position 0,0` and `--position 1280,0`, with no role argument (the driver stays idle), started with `nohup`. Commit only after the user approves.
- **Per milestone:**
  - M2: names, characters and ready flags show up on every instance. Start is disabled until all players are ready.
  - M3/M4: client movement is visible on the host and the other way round, with no delay on one's own player. Enemies, hits, deaths and gold match. Killing the client process mid-wave doesn't crash the host.
  - M5: shops on different machines finish in any order. Bought items persist into the next wave on all peers (compare `RunData` dumps).
  - M6: use debug devices or headless dummy clients that send scripted random input to fill 12 slots. Check FPS and bandwidth with about 300 enemies, check the arena scales, and check spawn counts against the formula.
- **Also test** keyboard-only and gamepad-only on both host and client, including menu and lobby navigation.
