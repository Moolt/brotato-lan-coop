# The Moolt-Lan_Coop mod as built (Steps 1–7)

A reference for working on the mod: what exists, how a session flows, the sync protocol, and the pitfalls already paid for. The plan with per-step history is [lan-coop-plan.md](lan-coop-plan.md); vanilla internals are in [brotato/](brotato/).

## Files (`mods-unpacked/Moolt-Lan_Coop/`)
| File | Role |
|---|---|
| `mod_main.gd` | Installs the extensions (one line each), registers translations, adds `/root/LanNet` deferred. |
| `net/net_manager.gd` | `LanNet`: ENet peer, handshake, lobby state, run sync (Start and each next wave), wave-end state, shop waiting and merge, all RPCs, session flags. |
| `net/net_protocol.gd` | `PROTOCOL_VERSION` (now 15, bump on any RPC/layout change), limits, reject reasons, `DEFAULT_SCALING`, lobby entry and settings defaults, unlock helpers. |
| `net/net_config.gd` | `user://lan_coop.cfg`: name, last IP, port, last zone/difficulty, `[scaling]` knobs. |
| `net/net_discovery.gd` | UDP beacon (host) and listener (join page). |
| `net/lobby_rules.gd` | Character/weapon/zone/difficulty lookup and validation. |
| `net/run_builder.gd` | Builds the run from the lobby (host), serializes it as JSON via the save loader, applies it, digests it; pending level-ups/crates (`pack_pending`), solo shop results (`parse_solo_run`, `merge_solo_run`), vanilla's once-for-all Go parts (`apply_go`). |
| `net/wave_sync.gd` | `LanWaveSync`, child of `main` in a session: everything in-wave (both roles). |
| `net/net_translations.gd` | Runtime en + de translations for `LAN_*` / `MENU_MULTIPLAYER` keys. |
| `game/solo_view.gd` | `SoloView` (`LanNet.solo_view`): between waves, RunData becomes the local player's solo run (index 0, not coop, only the local device) and back; moves RunData's per-player slots, resets per-player caches. |
| `game/offscreen_arrows.gd` | Arrows at the screen edge pointing at off-screen teammates, in their colour (main's `UI` layer). |
| `game/lan_game.gd` | Static helpers: `MAX_PLAYERS` (12), `in_session()`, `get_lan_net()`, `get_wave_sync()`, `is_wave_client()`, `get_player_name()`, `grow()` for 4-slot arrays, scaling formulas. |
| `ui/*.gd` | Pages built in code: multiplayer menu, join menu, lobby (player list; character and weapon grids, each with a simplified preview of the hovered entry or the pick), `ui_kit.gd` building blocks; `shop_waiting_overlay.gd` (over the shop after Go). |
| `extensions/…` | Script extensions, mirrored vanilla paths (list below). |
| `tools/lan_test_driver.gd` (repo root, not in the mod) | Test autoload for the throwaway game copy; see the plan's Verification section. |

## Session flow
1. **Host / join** (`LanNet.host()` / `join()`): sets `active`, `is_host`/`is_client`, blocks saves (`ProgressData.lan_coop_saves_blocked`), unlocks everything (own unlock lists restored on leave), switches to the solo mouse rule. Client sends `_rpc_hello`; host validates (protocol, game version, DLCs, full, in progress) and answers `_rpc_welcome(player_index)` or `_rpc_rejected(reason)`.
2. **Lobby**: `LanNet.players` (entries from `NetProtocol.new_player_entry`, sorted by `player_index`; the host is peer 1 and index 0) and `lobby_settings` (`zone`, `difficulty`, `run_id`, `in_wave`, `scaling`) are broadcast with `_rpc_lobby_state` on every change. Clients change their own entry with `_rpc_update_player`.
3. **Start** (`start_run`): host builds the run (`RunBuilder.build_run`), serializes it, applies its own copy from the same JSON, sends `_rpc_run_state(run_id, json, digest)`; clients apply and ack. Any lobby change makes the run stale (`run_id` = 0).
4. **Wave**: once every client acked, the host sets `run_in_progress` (`lobby_settings.in_wave`), fills `CoopService.connected_players` (own device 7 keyboard / 6 gamepad, others -1), sends `_rpc_enter_wave(run_id)` and everyone loads `main.tscn`. The `main.gd` extension adds `LanWaveSync` in `_ready`.
5. **Wave end**: unless the wave failed, the host's `main.gd` extension runs `RunData.on_wave_end()` / `LinkedStats.reset()` and `LanNet.send_wave_end_state`: the run after the wave (JSON, applied on the host too) with its digest and each player's pending level-ups and crates (`RunBuilder.pack_pending`: `[[levels], [consumable ids]]` per player) go out as `_rpc_wave_end_state(run_id, wave, json, digest, pending)`. A client applies it once its own wave is over (end-wave timer ran, or it left `main.tscn`), stores `LanNet.wave_end_state = {wave, pending, ok}` and answers `_rpc_wave_end_ack(wave, ok)`. Both roles emit `LanNet.wave_end_ready` once `wave_end_state` is set (`main` relays it as its own `lan_wave_end_ready`, which a client's end-wave code yields on).
6. **Upgrades** (not after a lost or won run): every peer stops `LanWaveSync` (`stop()`: no physics, `LanNet.wave_sync` = null, so late snapshots and events are dropped), enters the solo view (`game/solo_view.gd`) and runs vanilla's solo flow on the solo `UpgradesUI` with its own pending level-ups and crates from `wave_end_state` (`player_index` 0; the own things-to-process icons are rebuilt from them). The solo `UpgradesUI` set itself up as nothing in `_ready` (the run was coop then), so its `_ready` runs again once in the solo view. Then the challenge UI, then the solo `shop.tscn`, still in the solo view.
7. **Shop**: the `base_shop.gd` extension's Go marks the candy-bag item locking, shows `ui/shop_waiting_overlay.gd` and calls `LanNet.send_shop_done(true)`: the own solo run (JSON) goes to the host as `_rpc_shop_done(wave, json)`; "Back to the shop" or cancel sends `""`. The host keeps the runs (`_shop_runs`), waits for itself and every connected client that didn't quit (`_left_run_peers`, from `_rpc_left_wave`, which a client also sends when it reaches the title screen between waves without having pressed Go), and broadcasts who is still shopping (`_rpc_shop_waiting(names)`).
8. **Next wave**: once nobody is shopping, the host leaves its solo view (its own result is what that leaves in its slot), merges every other result into its player's slot (`RunBuilder.merge_solo_run`: `players_data`, `locked_shop_items`, `tracked_item_effects`; players without a result keep their wave-end state), runs `RunBuilder.apply_go()` (vanilla's once-for-all Go parts: hourglass, extra-elite roll, `current_wave += 1 - wave_reset_count`, then cursing locked items as the shop's `_on_tree_exited` would) and sends the run like Start (`_send_run`: new run id, `_rpc_run_state`, acks, `_rpc_enter_wave`). A client leaves its solo view before applying it. Clients that quit to the lobby get it too and are back in (the host ignores lobby entry changes while a run is in progress). A digest mismatch here logs a warning and the wave starts anyway with the host's run (at Start it keeps everyone in the lobby). At the next wave the host kills the players of disconnected entries again (`LanWaveSync._kill_disconnected_players`).
9. **Run end** (everyone dead, which always ends the run in a session (no retry screen), or the last wave won): the host still sends the wave-end state; every peer stops `LanWaveSync`, sets `LanNet.run_over`, enters the solo view without the shop phase (`enter_solo_view(false)`), puts back `RunData.run_won` and `difficulty_unlocked` (set by `apply_run_won` in `clean_up_room`, cleared by applying the host's run) and opens the solo `end_run.tscn`. The `base_end_run.gd` extension hides Restart and New Run and turns Exit into "Back to the lobby". A client back in the lobby while the host is still on its end screen sees "The run is over…" (`run_over`).
10. **Back to the lobby** (from the end screen, or the host quits): the title screen's vanilla `_ready` resets `RunData`; its extension calls `LanNet.on_title_screen()` (a client that hadn't pressed Go sends `_rpc_left_wave`; any solo view is discarded), reopens the lobby and (host) calls `set_run_in_progress(false)`, which drops disconnected players and makes the run stale. Clients in `main.tscn` or the shop follow when a lobby broadcast says `in_wave` is false. A disconnect during a run keeps the run id (`_broadcast_lobby_state(run_in_progress)`), so a next-wave sync in progress isn't dropped.
11. **Leave / errors**: `_end_session(reason)` restores unlocks and saves, resets RunData if a synced run replaced it, and returns to the title screen with a reason popup.

## Between waves (Step 7)
**Idea:** the vanilla coop upgrade UI, shop and end screen have 4 player slots and assume one screen. Instead every machine shows the vanilla **solo** screens for its own player: `RunData` temporarily becomes that player's solo run (the solo view), and the host merges the results.

**State in `LanNet`:**
| Name | Meaning |
|---|---|
| `wave_end_state` | `{wave, pending, ok}`: the run after the wave was applied (host: sent). Cleared when a wave is entered (`_reset_between_waves`), since a new run starts at wave 1 again. |
| `solo_view` (`game/solo_view.gd`) | `enter(index, local device)` / `leave()` / `discard()`. Moves `players_data[index]` and the per-player `RunData` arrays (`MOVED_ARRAYS`) to slot 0 and back; resets per-player caches. Use `LanNet.enter_solo_view(shopping)` / `leave_solo_view()`. |
| `between_waves`, `shop_done`, `shop_waiting_names` | upgrades and shop phase; set by `enter_solo_view(true)` |
| `_shop_runs` (host) | player_index → that player's solo run JSON from Go |
| `_left_run_peers` (host) | clients that quit the run (not waited for); cleared when a wave is entered |
| `run_over` | the run ended and the end screen was shown (lobby hint) |
| `_run_id_counter` vs `lobby_settings.run_id` | the run the clients hold vs the lobby's current run (a lobby broadcast can reset the latter; wave-end states use the counter) |

**RPCs** (besides `_rpc_run_state` / `_rpc_run_state_ack` / `_rpc_enter_wave`, which Start and every next wave share via `_send_run`):
| RPC | Direction | Content |
|---|---|---|
| `_rpc_wave_end_state(run_id, wave, json, digest, pending)` | host → clients | the run after the wave and `[[levels], [consumable ids]]` per player; applied once the client's own wave is over |
| `_rpc_wave_end_ack(wave, ok)` | client → host | digest check result |
| `_rpc_shop_done(wave, json)` | client → host | Go: the own solo run; `""` = back to the shop |
| `_rpc_shop_waiting(names)` | host → clients | who is still shopping |
| `_rpc_left_wave()` | client → host | quit the run (pause menu in the wave, or reaching the title screen between waves without Go) |

**Order on every machine:** `main._on_EndWaveTimer_timeout` → host `send_wave_end_state` / client waits for `lan_wave_end_ready` (main's relay of `LanNet.wave_end_ready`) → `LanWaveSync.stop()` → run end: `enter_solo_view(false)`, `end_run.tscn`; otherwise `enter_solo_view()`, solo `UpgradesUI` (its `_ready` run again), `shop.tscn` → Go → host merges when nobody is shopping → next run via `_send_run` → client leaves the solo view in `_rpc_run_state` → `_rpc_enter_wave`.

## In-wave sync (`LanWaveSync`)
**Authority:** each machine moves its own player; the host simulates everything else. Clients spawn copies of host entities through vanilla code, then make them inert.

**RPCs** (all on `LanNet`, which forwards to `LanNet.wave_sync`; every remote func checks sender and argument types):
| RPC | Direction | Mode | Content |
|---|---|---|---|
| `_rpc_player_state(pos, move, aim, manual_aim)` | client → host | unreliable, every physics frame | own player; `aim` is the aim point relative to the player (mouse, or gamepad aim × 10000) |
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

**Host side:** remote players are `lan_net_driven` (position set from the client, `get_movement()` = reported move, zero velocity); their manual aim comes from `get_remote_manual_aim`, and their weapons turn towards `get_remote_aim_point` (the `weapon.gd` extension's `get_global_mouse_position`; remote players count as keyboard players on the host). The wave timer waits for `_rpc_wave_loaded` from every client (15 s at most). Disconnect or `_rpc_left_wave` kills that player; disconnected players are killed again at the start of each later wave.

## Extensions (`extensions/<vanilla path>`)
| Vanilla script | What the extension does |
|---|---|
| `main.gd` | HUD copies P5–P12, local HUD in the P1 slot, over-head names/bars, skull under dead players' names, off-screen arrows, solo crosshair for the local player's manual aim, camera on the local player (spectate on death), adds `LanWaveSync`, enemy scaling, client end-of-wave from the host (verdict via `_set_run_states`), blocks client loot, crate-to-process hook, pause check, no pause on focus loss, wave-end state to the clients, solo upgrades between waves (gold/XP HUD of RunData index 0 goes to the local player's HUD in the solo view), temporary wave end → lobby, `on_gold_picked_up` copy for > 4 players |
| `singletons/utils.gd` | grows 4-slot arrays; `is_manual_aim`: remote players' reported flag (host), solo rules for the local player (own mouse) |
| `singletons/run_data.gd`, `stats_manager.gd`, `debug_service.gd`, `ui/menus/global/popup_manager.gd` | grow 4-slot arrays to 12 (also after vanilla functions that reassign them) |
| `singletons/coop_service.gd` | 12 players, 12 colours |
| `singletons/zone_service.gd` | arena grows with the player count |
| `singletons/progress_data.gd` | saves blocked during a session; the own `saved_run_state` / `last_saved_run_state` ("Continue") put aside at session start and restored at its end, since the shop and a lost run change them in memory |
| `ui/menus/run/base_end_run.gd` | session end screen: no Restart / New Run, Exit = "Back to the lobby" |
| `singletons/progress_data_loader_v3.gd` | run (de)serialization of `locked_shop_items` / `shop_items` beyond 4 slots (vanilla builds 4) |
| `global/entity_spawner.gd` | 12-slot arrays, spawn circle, enemy cap, reports spawns and markers (host), markers only show (client) |
| `entities/units/player/player.gd` | `lan_net_driven`, `lan_move_speed`, `lan_no_regen` |
| `entities/units/movement_behaviors/player_movement_behavior.gd` | remote players (device -1) read no input; local player stands still while the pause menu is open |
| `entities/units/enemies/enemy.gd`, `entities/structures/turret/turret.gd` | attacks from animations do nothing on clients |
| `entities/birth/entity_birth.gd` | client markers ignore players standing on them |
| `weapons/weapon.gd` | clients never fire; host reports attacks; remote players' manual aim towards their reported aim point (host) |
| `projectiles/projectile.gd` | host reports shoot/stop/pool; ids |
| `items/global/item.gd` | host reports drops and pickups; ids |
| `singletons/weapon_service.gd` | host reports explosions |
| `ui/menus/ingame/pause_menu.gd` | session pause without `get_tree().paused`, native focus (no FocusEmulator) |
| `singletons/focus_emulator_signal.gd` | answers the local player (`LanNet.get_local_run_index()`, 0 in the solo view) when no emulator reported one |
| `ui/menus/ingame/ingame_main_menu.gd` | hides Restart and End Run in a session |
| `ui/menus/shop/base_shop.gd` | Go sends the own solo run to the host and shows the waiting overlay; Back/cancel takes it back; no Go clear on focus loss; candy-bag locking at Go; no locked-item curse on close (the host does it); Endless button hidden |
| `ui/menus/title_screen/title_screen_menus.gd` | Multiplayer button, mod pages, lobby restore |

## Pitfalls learned
- **Errors disable the mod**: any `ERROR:` / `SCRIPT ERROR:` mentioning `mods-unpacked` triggers the crash reporter on the next Steam/Epic launch. Vanilla `push_error` and failed `assert`s in vanilla code called from an extension are attributed to the extension's file. Check logs after every test.
- **Parse errors** make an extension silently absent; run the driver's `quit` role after edits. `var x: = <untyped expr>` and duplicate `var` names in one scope are the usual causes.
- **Engine callbacks run at every inheritance level.** `_ready` goes base → derived; `_input`, `_process`, `_physics_process` go derived → base. An extension can't suppress vanilla's callback; switch processing off or override the regular methods it calls.
- **Pools:** `main.add_node_to_pool` asserts that the pool exists; create it with `get_node_from_pool` first. Pooled nodes are removed from the tree and re-added, `_ready` runs only once.
- **Coop UI vs one player per machine:** an active FocusEmulator swallows all mouse input; `InputService` hides the cursor on every input in a coop run with more than one player; coop UI asks `FocusEmulatorSignal` for the focusing player and `push_error`s on -1. Sessions use native focus and the solo mouse rule instead.
- **`Utils.is_manual_aim` returns null** when no manual-aim setting is on; compare with `== true`.
- **GDScript 1:** `continue` inside `match` falls through to the next pattern; use `if`/`elif` in loops. Compare arrays by value with `==`. `sync` (like `master`, `puppet`, `remote`) is a keyword; don't name a variable after it.
- **Native methods can be overridden for script callers:** vanilla scripts calling e.g. `get_global_mouse_position()` reach an extension's method of that name (the engine itself doesn't); `.get_global_mouse_position()` calls the native one.
- **`WaveTimer.stop()` only pauses:** its `_physics_process` restarts the tick sound while 0.1–6 s are left, so a timer stopped early (a client's, which lags the host's) ticks on; `clean_up_room` turns its physics off in a session.
- **Per-wave state across runs:** a new run in the same session starts at wave 1 again, so state keyed only by the wave number (like `LanNet.wave_end_state`) must be cleared when a wave is entered, or the next run takes the old one for its own.
- **Coop-only UI setup:** vanilla UIs set themselves up in `_ready` only for the run type they were made for (`UpgradesUI._ready` returns when `RunData.is_coop_run != is_coop_ui`). In a session the solo `UpgradesUI` in `main.tscn` is therefore unset; it runs `_ready` again once the solo view is active.
- **Solo view hazards:** while it is active, `RunData` has one player, but `main` still has every player node. Anything that indexes players by their coop index must be off (`LanWaveSync.stop()`) or mapped (`main.on_gold_changed` / `on_xp_added` map index 0 to the local HUD). Never apply a run (`RunBuilder.apply_run`) inside the solo view: leave or discard it first.
- **Applying a run clears what isn't in the run state:** `RunData.reset()` resets `run_won`, `difficulty_unlocked` and per-wave values; keep what the current scene needs (7f).
- **Title screen:** vanilla `title_screen.gd` `_ready` calls `RunData.reset()`. Its child `Menus` (the extension) is ready before it, so `LanNet.on_title_screen()` runs first.
- **Yield on another object's signal from a scene:** if the scene is freed before the signal fires, the resumed function errors ("class instance is gone"). Relay it through a signal on the scene itself (`main.lan_wave_end_ready`).
- **Several connections to one signal** run in no guaranteed order; don't let them depend on each other.
- **Shop:** vanilla's Go button clears Go when it loses focus (`_on_GoButton_focus_exited`); the waiting overlay takes the focus. `_on_tree_exited` curses locked items randomly per player, so in a session only the host does it (`RunBuilder.apply_go`). The Go handler's hourglass, extra-elite roll and wave increment must run once for everyone (host).
- **Save loader has 4 slots** for `locked_shop_items` and `shop_items` (`ProgressDataLoaderV3`); the extension handles the rest. Extending a `class_name` script works for `ClassName.new()` too.
- **`saved_run_state` changes in memory during a session** (shop, lost run) although disk saves are blocked; the `progress_data.gd` extension puts the own one aside.
- **Disconnects during a run** must not reset the run id (`_broadcast_lobby_state(run_in_progress)`), or a pending next-wave sync stalls; lobby entry changes are ignored during a run for the same reason.
- **Test driver:** pass the local player's index to `pause()` (as `main._check_for_pause` does); a remote index has device -1 and hides coop-only behaviour. Simulated mouse events need window coordinates (`get_tree().root.get_final_transform()`). Don't `pkill -f` with a pattern that is also in the shell command line.
