# The Moolt-Lan_Coop mod as built (Steps 1–6)

A reference for working on the mod: what exists, how a session flows, the sync protocol, and the pitfalls already paid for. The plan with per-step history is [lan-coop-plan.md](lan-coop-plan.md); vanilla internals are in [brotato/](brotato/).

## Files (`mods-unpacked/Moolt-Lan_Coop/`)
| File | Role |
|---|---|
| `mod_main.gd` | Installs the extensions (one line each), registers translations, adds `/root/LanNet` deferred. |
| `net/net_manager.gd` | `LanNet`: ENet peer, handshake, lobby state, run sync, all RPCs, session flags. |
| `net/net_protocol.gd` | `PROTOCOL_VERSION` (now 13, bump on any RPC/layout change), limits, reject reasons, `DEFAULT_SCALING`, lobby entry and settings defaults, unlock helpers. |
| `net/net_config.gd` | `user://lan_coop.cfg`: name, last IP, port, last zone/difficulty, `[scaling]` knobs. |
| `net/net_discovery.gd` | UDP beacon (host) and listener (join page). |
| `net/lobby_rules.gd` | Character/weapon/zone/difficulty lookup and validation. |
| `net/run_builder.gd` | Builds the run from the lobby (host), serializes it as JSON via the save loader, applies it, digests it. |
| `net/wave_sync.gd` | `LanWaveSync`, child of `main` in a session: everything in-wave (both roles). |
| `net/net_translations.gd` | Runtime en + de translations for `LAN_*` / `MENU_MULTIPLAYER` keys. |
| `game/solo_view.gd` | `SoloView` (`LanNet.solo_view`): between waves, RunData becomes the local player's solo run (index 0, not coop, only the local device) and back; moves RunData's per-player slots, resets per-player caches. |
| `game/lan_game.gd` | Static helpers: `MAX_PLAYERS` (12), `in_session()`, `get_lan_net()`, `get_wave_sync()`, `is_wave_client()`, `get_player_name()`, `grow()` for 4-slot arrays, scaling formulas. |
| `ui/*.gd` | Pages built in code: multiplayer menu, join menu, lobby, `ui_kit.gd` building blocks. |
| `extensions/…` | Script extensions, mirrored vanilla paths (list below). |
| `tools/lan_test_driver.gd` (repo root, not in the mod) | Test autoload for the throwaway game copy; see the plan's Verification section. |

## Session flow
1. **Host / join** (`LanNet.host()` / `join()`): sets `active`, `is_host`/`is_client`, blocks saves (`ProgressData.lan_coop_saves_blocked`), unlocks everything (own unlock lists restored on leave), switches to the solo mouse rule. Client sends `_rpc_hello`; host validates (protocol, game version, DLCs, full, in progress) and answers `_rpc_welcome(player_index)` or `_rpc_rejected(reason)`.
2. **Lobby**: `LanNet.players` (entries from `NetProtocol.new_player_entry`, sorted by `player_index`; the host is peer 1 and index 0) and `lobby_settings` (`zone`, `difficulty`, `run_id`, `in_wave`, `scaling`) are broadcast with `_rpc_lobby_state` on every change. Clients change their own entry with `_rpc_update_player`.
3. **Start** (`start_run`): host builds the run (`RunBuilder.build_run`), serializes it, applies its own copy from the same JSON, sends `_rpc_run_state(run_id, json, digest)`; clients apply and ack. Any lobby change makes the run stale (`run_id` = 0).
4. **Wave**: once every client acked, the host sets `run_in_progress` (`lobby_settings.in_wave`), fills `CoopService.connected_players` (own device 7 keyboard / 6 gamepad, others -1), sends `_rpc_enter_wave(run_id)` and everyone loads `main.tscn`. The `main.gd` extension adds `LanWaveSync` in `_ready`.
5. **Wave end**: unless the wave failed, the host's `main.gd` extension runs `RunData.on_wave_end()` / `LinkedStats.reset()` and `LanNet.send_wave_end_state`: the run after the wave (JSON, applied on the host too) with its digest and each player's pending level-ups and crates (`RunBuilder.pack_pending`: `[[levels], [consumable ids]]` per player) go out as `_rpc_wave_end_state(run_id, wave, json, digest, pending)`. A client applies it once its own wave is over (end-wave timer ran, or it left `main.tscn`), stores `LanNet.wave_end_state = {wave, pending, ok}` and answers `_rpc_wave_end_ack(wave, ok)`. Both roles emit `LanNet.wave_end_ready` once `wave_end_state` is set. Then (temporary until Step 7 is done) the `main.gd` extension's `_on_EndWaveTimer_timeout` goes back to the title screen (whose vanilla `_ready` resets `RunData`), whose extension reopens the lobby and (host) calls `set_run_in_progress(false)`, which drops disconnected players and makes the run stale. Clients still in `main.tscn` follow when a lobby broadcast says `in_wave` is false.
6. **Leave / errors**: `_end_session(reason)` restores unlocks and saves, resets RunData if a synced run replaced it, and returns to the title screen with a reason popup.

## In-wave sync (`LanWaveSync`)
**Authority:** each machine moves its own player; the host simulates everything else. Clients spawn copies of host entities through vanilla code, then make them inert.

**RPCs** (all on `LanNet`, which forwards to `LanNet.wave_sync`; every remote func checks sender and argument types):
| RPC | Direction | Mode | Content |
|---|---|---|---|
| `_rpc_player_state(pos, move, aim, manual_aim)` | client → host | unreliable, every physics frame | own player |
| `_rpc_snapshot(bytes)` | host → clients | unreliable, every 3 physics frames (20 Hz) | layout below |
| `_rpc_events(array)` | host → clients | reliable, once per physics frame if any | event list below |
| `_rpc_wave_loaded()` | client → host | reliable | wave scene is up |
| `_rpc_left_wave()` | client → host | reliable | quit the wave (pause menu) |
| `_rpc_wave_cleanup([failed, lost, won])` | host → clients | reliable | wave over, host's verdict |

**Snapshot** (`StreamPeerBuffer`): header 14 bytes (seq u32, host msec u32, `time_left` f32, flags u8 (1 = waiting for clients), player count u8); per player 33 bytes (pos f32×2, move s8×2 (×127), speed f32, hp s32, max hp s32, flags u8 (1 = dead), gold s32, xp f32, level u16); then entity count u16 and 8 bytes per entity (net id u16, x/y s16, HP ratio u8 (0–255), flags u8 (1 = burning)). Trees are left out (static). Clients drop older seqs and render puppets 100 ms in the past.

**Events** (`[code, …]`):
| Code | Name | Fields |
|---|---|---|
| 0 | spawn | net id, `EntityType`, scene path, pos, player_index, data ref (`[effect key, index]` into the player's structures/pets effects, or a resource path), charmed_by |
| 1 | die | net id, knockback |
| 2 | birth (spawn marker) | birth id, type, pos, charmed_by |
| 3 | weapon attack | player_index, weapon index, rotation, distance, melee attack type or -1 |
| 4 | projectile | id, scene path, pos, velocity, rotation, speed, max range, is_enemy, sinusoidal motion, sinusoidal speed, bullet-hell direction |
| 5 | projectile stop | id, pos |
| 6 | animation | net id, animation name, playback speed |
| 7 | damage | target kind (0 entity, 1 player), id, value, knockback dir, flags (crit 1, dodge 2, protected 4, armor 8, one-shot 16), hit type, effect scale |
| 8 | explosion | scene path, pos, scale, smoke amount, sound db |
| 9 | item drop | id, kind (0 gold, 1 consumable), gold texture path, consumable id, pos, rotation, push-back target, scale, boosted |
| 10 | item attract | id, target kind (1 player, 0 entity, -1 none), target id |
| 11 | item pickup | id, player_index (players only; the gold bag stays local) |
| 12 | crate to process | player_index, consumable id |
| 13 | item scale | id, scale |
| 14 | birth moved | birth id, pos |

`LanWaveSync.event_counts` counts sent (host) / received (client) events per code.

**Ids:** entities, projectiles, items and spawn markers each have their own u16 counter (wrapping). Pooled nodes keep their id in a member (`lan_net_id` on projectiles and items) or meta (`lan_net_id` on entities, `lan_birth_id` on markers) and stale ids pointing at a reused node are ignored.

**Client side:** wave manager and entity spawner physics off, structure timer stopped, local loot and drops blocked (`spawn_loot`, `spawn_gold`, `spawn_consumables`, garden fruit), weapons never fire (`should_shoot`), enemy/turret `shoot()`/`start_shoot()` no-ops (animations still play), own player has no hurtbox, no pickup/attract areas, no regen, speed and HP from the host. "Inert" copies: `set_physics_process(false)`, `MODE_KINEMATIC`, every `Area2D` in the subtree `monitoring`/`monitorable` false (deferred). Client entity HP is the 0–255 ratio (`max_stats.health = 255`).

**Host side:** remote players are `lan_net_driven` (position set from the client, `get_movement()` = reported move, zero velocity); their manual aim comes from `get_remote_manual_aim`. The wave timer waits for `_rpc_wave_loaded` from every client (15 s at most). Disconnect or `_rpc_left_wave` kills that player.

## Extensions (`extensions/<vanilla path>`)
| Vanilla script | What the extension does |
|---|---|
| `main.gd` | HUD copies P5–P12, local HUD in the P1 slot, over-head names/bars, camera on the local player (spectate on death), adds `LanWaveSync`, enemy scaling, client end-of-wave from the host (verdict via `_set_run_states`), blocks client loot, crate-to-process hook, pause check, no pause on focus loss, wave-end state to the clients, temporary wave end → lobby, `on_gold_picked_up` copy for > 4 players |
| `singletons/run_data.gd`, `utils.gd`, `stats_manager.gd`, `debug_service.gd`, `ui/menus/global/popup_manager.gd` | grow 4-slot arrays to 12 (also after vanilla functions that reassign them) |
| `singletons/coop_service.gd` | 12 players, 12 colours |
| `singletons/zone_service.gd` | arena grows with the player count |
| `singletons/progress_data.gd` | saves blocked during a session |
| `global/entity_spawner.gd` | 12-slot arrays, spawn circle, enemy cap, reports spawns and markers (host), markers only show (client) |
| `entities/units/player/player.gd` | `lan_net_driven`, `lan_move_speed`, `lan_no_regen` |
| `entities/units/movement_behaviors/player_movement_behavior.gd` | remote players (device -1) read no input; local player stands still while the pause menu is open |
| `entities/units/enemies/enemy.gd`, `entities/structures/turret/turret.gd` | attacks from animations do nothing on clients |
| `entities/birth/entity_birth.gd` | client markers ignore players standing on them |
| `weapons/weapon.gd` | clients never fire; host reports attacks |
| `projectiles/projectile.gd` | host reports shoot/stop/pool; ids |
| `items/global/item.gd` | host reports drops and pickups; ids |
| `singletons/weapon_service.gd` | host reports explosions |
| `ui/menus/ingame/pause_menu.gd` | session pause without `get_tree().paused`, native focus (no FocusEmulator) |
| `singletons/focus_emulator_signal.gd` | answers the local player (`LanNet.get_local_run_index()`, 0 in the solo view) when no emulator reported one |
| `ui/menus/ingame/ingame_main_menu.gd` | hides Restart and End Run in a session |
| `ui/menus/title_screen/title_screen_menus.gd` | Multiplayer button, mod pages, lobby restore |

## Pitfalls learned
- **Errors disable the mod**: any `ERROR:` / `SCRIPT ERROR:` mentioning `mods-unpacked` triggers the crash reporter on the next Steam/Epic launch. Vanilla `push_error` and failed `assert`s in vanilla code called from an extension are attributed to the extension's file. Check logs after every test.
- **Parse errors** make an extension silently absent; run the driver's `quit` role after edits. `var x: = <untyped expr>` and duplicate `var` names in one scope are the usual causes.
- **Engine callbacks run at every inheritance level.** `_ready` goes base → derived; `_input`, `_process`, `_physics_process` go derived → base. An extension can't suppress vanilla's callback; switch processing off or override the regular methods it calls.
- **Pools:** `main.add_node_to_pool` asserts that the pool exists; create it with `get_node_from_pool` first. Pooled nodes are removed from the tree and re-added, `_ready` runs only once.
- **Coop UI vs one player per machine:** an active FocusEmulator swallows all mouse input; `InputService` hides the cursor on every input in a coop run with more than one player; coop UI asks `FocusEmulatorSignal` for the focusing player and `push_error`s on -1. Sessions use native focus and the solo mouse rule instead.
- **`Utils.is_manual_aim` returns null** when no manual-aim setting is on; compare with `== true`.
- **GDScript 1:** `continue` inside `match` falls through to the next pattern; use `if`/`elif` in loops. Compare arrays by value with `==`.
- **Test driver:** pass the local player's index to `pause()` (as `main._check_for_pause` does); a remote index has device -1 and hides coop-only behaviour. Simulated mouse events need window coordinates (`get_tree().root.get_final_transform()`). Don't `pkill -f` with a pattern that is also in the shell command line.
