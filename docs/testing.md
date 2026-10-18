# Testing the mod

How to run and check the mod: a throwaway game copy, the test driver (`tools/lan_test_driver.gd`), the regression set, and the manual test. Open test coverage is tracked in [lan-coop-plan.md](lan-coop-plan.md#tests).

## Workflow
1. Implement, then run the driver's `quit` role once (catches parse errors cheaply; a parse error makes an extension silently absent).
2. Run the driver scenario for the change, plus the relevant part of the [regression set](#regression-set). A bug is first reproduced with a new driver option *without* the fix (e.g. `git stash` the mod change), then checked with it.
3. [Check the logs](#log-check).
4. Manual test by the user in two windows. **Commit only after the user approves.**

## Throwaway game copy
`tools/make_test_copy.sh <scratchpad>/game` builds it in one go (about 300 MB, a few seconds). It does:
- `cp -a Decompiled <scratch>/game`, then removes its `.git`
- replaces `mods-unpacked/Moolt-Lan_Coop` with an **absolute** symlink to `brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop`, and symlinks `tools/lan_test_driver.gd` as `lan_test_driver.gd` (edits to the driver stay tracked in the repo; it is not in the release zip)
- in the copy's `project.godot`:
  - `config/custom_user_dir_name="BrotatoLanTest"` (under `[application]`); without it, instances use the real `~/.local/share/Brotato` save and log
  - `window/vsync/use_vsync=false` (under `[display]`): covered or unfocused windows stall on vsync under Wayland/XWayland, which also stops the network poll
  - an autoload `LanTestDriver="*res://lan_test_driver.gd"` after `OS_Seaven`

## Running
```
Godot/Godot_v3.7-dev1_x11.64 --path <scratch>/game --resolution 1280x720 --position 0,0 -- <role>
```
- Second instance at `--position 1280,0`. Start `host` with `nohup ... &`, wait 1 s, start `join` the same way, then `wait`; stdout goes to `host.log` / `join.log`. The driver quits each instance at the end of its script.
- Both instances share `user://lan_coop.cfg` (names, port 24999 in that profile).
- Add `-vvv` to see `ModLoaderLog` output.
- **Runner script:** keep a small script in the scratchpad (e.g. `run2.sh`) that checks `game/project.godot` exists, exports `SHOT_DIR`, starts `host` and 1 s later `join` with `nohup`, and `wait`s. Call it by absolute path.

## Driver (`tools/lan_test_driver.gd`)
Reads the role from `OS.get_cmdline_args()`. In `_process` it waits for the title screen (`current_scene.filename == MenuData.title_screen_scene`; the game starts in the splash scene `res://pause.tscn`), then runs a timed `match step` script that drives the pages by calling their handlers directly. Its step scripts follow the latest feature under test and get edited for the next one; the header lists roles and options.

### Roles
| Role | Does |
|---|---|
| `host` / `join` | the two sides of a session |
| `solo` | `RunBuilder.build_run` with one entry, `set_coop_run(false)`, `change_scene(MenuData.game_scene)`: vanilla solo play still works without a session |
| `lobby` | hosts alone; screenshots the lobby with a character hovered, a starting item's popup, a weapon hovered, nothing hovered; then focuses Mage and its first starting item with the keyboard and logs that the preview keeps Mage until Ready has the focus |
| `quit` | quits as soon as the title screen loads (parse-error check) |
| none | idle, for manual tests |

### Environment options (combine as needed)
| Option | Effect |
|---|---|
| `FAKES=n` | n fake lobby players (the first an Engineer) |
| `ENEMY_MULT=x` | enemy count multiplier |
| `KILL_ALL=1` | everyone dies in wave 1 (run lost) |
| `WAVES=n` | n waves with upgrades and shop, then both check wave n+1 |
| `ROUNDS=n` | n runs in one session (needs a run that ends, e.g. with `KILL_ALL=1`) |
| `START_WAVE=n` | the run starts at wave n (20: run won) |
| `CLIENT_QUITS=1` / `=2` | the client quits the wave from its pause menu and changes its character in the lobby (ignored) / its process exits mid-wave |
| `SHOP_QUIT=1` | the client quits from the shop |
| `FAIL_ACK=1` | the next wave's run counts as a digest mismatch on both sides |
| `TIMER_LAG=s` | the client's wave timer s seconds behind |
| `FAKE_SAVED_RUN=1` | a stand-in "Continue" run in memory before the session (never saved) |
| `AIM_TEST=1` | manual aim on both, the client's mouse at its top left |
| `MORTAL=1` | host: players can be hit; at t=16 an enemy is placed on the host player (`enemy_contacts` in the `quirks` line) |
| `WAVE_DURATION=s` | host: the first wave lasts s seconds (default 20) |
| `PERF_LOG=1` | once a second in a wave: enemies, physics bodies/pairs, physics and process time, FPS (`*_curve` lines) |
| `TIMING=1` | with `PERF_LOG`: times all enemy scripts and weapon target scans once a second |
| `ENEMY_CAP=n`, `PHYS_ITER=n`, `NO_ENEMY_COLLIDE=1`, `NO_SYNC=1` | perf experiments: the wave's enemy cap (solo: exactly n), solver iterations, no enemy–enemy collision, host `LanWaveSync` per-tick work off |

### Helpers and checks
- Between waves, every frame: `pick_upgrades` (first upgrade, or take the crate item on the host and recycle it on the client; logs the picked stat per player), `shop_actions` (buy one item, lock another, Go; the client goes Back and Go again; the host is last), `end_screen_actions` (log the end screen, Exit: the client first).
- `solo_view_test` (on `LanNet.wave_end_ready`) enters and leaves the solo view once and checks the run is unchanged.
- `log_run_check` prints every player's gear, the scene's weapon nodes and the digest; compare host and client.
- `log_quirk_fixes` (with `log_sync`): enemy hitboxes on `LanGame.ENEMY_HITBOX_BIT`, enabled burning `SpreadArea`s, burning enemies, enemy collision masks (clients: 128), player hurtbox masks, enemy contacts, the cap factor. `burn_spread_test` (host, t=16): an enemy with spread 2 and two neighbours (10000 HP); `burn_spread burning=[true, true, true]` when the fire spread.
- `TIME_PHYSICS_PROCESS` is the longest physics tick of the last second, updated once a second; sample it once a second and compare medians over separate runs. Switching parts off one after another within one run changes the crowd (enemies without scripts drift apart) and is not a clean breakdown.
- `log_sync` / `log_visuals`: off-screen players, skulls, manual aim, first weapon rotation per player, the host's reported aims. `LanWaveSync.event_counts` (sent on the host, received on clients) shows whether events arrive.
- `log_perf` (with every `log_sync` and at the wave's cleanup): frames, avg FPS, max frame time and frames over 33 ms since the last call; physics/process time, physics bodies and pairs, the mod's own per-frame cost (`_build_snapshot` on the host, `_update_puppets` on clients). Clients also log snapshots received and lost (new buffer entries against the seq advance, by size in UDP packets), the largest gap, and the interpolation cushion (below 0: the 100 ms buffer ran dry). Each screenshot costs ~120 ms, which shows up in `max_frame_ms`.
- Screenshots: `get_viewport().get_texture().get_data()`, `flip_y()`, `save_png()` into `$SHOT_DIR`. Output lines start with `[TEST]`.

### Writing steps
- Drive pages directly: `LanMultiplayerButton.emit_signal("pressed")`, `mp._host_button`, `join._first_row()`, lobby `_on_CharacterGrid_element_pressed(element)`, `_on_ReadyButton_pressed()`, `_on_StartButton_pressed`.
- Each step sets `next_t` *before* any `yield`, otherwise `_process` re-enters the same step.
- **Fake lobby players:** append `NetProtocol.new_player_entry(...)` to `LanNet.players` (peer ids 1000+, with `character_id`, `weapon_id`, `ready = true`), then `_broadcast_lobby_state()`. Only connected peers are sent anything, so the host can start a 12-player wave alone.
- **In the wave:** `get_tree().current_scene` is `main`; read `_players`, `_players_ui`, `_wave_timer`, `get_node("%LifeContainerP12")`; move the host with `Input.action_press("button_move_right_7")`; kill a player with `_players[i].die()`; Quit with `_pause_menu.get_node("Menus/MenuConfirm")._on_ConfirmButton_pressed()`.
- **Pause:** `_pause_menu.pause(local_index)` / `unpause()`. Pass the *local* player's index, as `main._check_for_pause` does; a remote index has device -1 and hides coop-only behaviour.
- **Pools:** a step that instances a pooled node itself must call `main.get_node_from_pool(pool_id, container)` once first; vanilla's `add_node_to_pool` asserts that the pool exists, and the failed assert is a `SCRIPT ERROR` attributed to the mod's `main.gd`.
- Simulated mouse events need window coordinates (`get_tree().root.get_final_transform()`).

## Regression set
Each takes about 1–2 min.

| Command | Covers |
|---|---|
| default | one wave with upgrades and shop, then wave 2 |
| `KILL_ALL=1` | run lost, end screens, back to the lobby |
| `FAKES=5 WAVES=2` | 7 players, merge, locked item of player 5 (slot ≥ 4) |
| `CLIENT_QUITS=1 WAVES=2` | quit to lobby mid-wave, back in next wave, lobby changes ignored |
| `CLIENT_QUITS=2 WAVES=2` | client process dies mid-wave |
| `SHOP_QUIT=1` | client quits from the shop |
| `START_WAVE=20 FAKE_SAVED_RUN=1` | run won; own "Continue" run untouched |
| `ROUNDS=2 KILL_ALL=1` | stale wave-end state across runs |
| `FAIL_ACK=1 WAVES=2` | next-wave digest mismatch doesn't freeze |
| `TIMER_LAG=0.3` | no wave-timer ticking in the upgrade screen |
| `AIM_TEST=1 FAKES=5` | remote manual aim, off-screen arrows, skulls |
| role `lobby` | lobby layout and previews |
| role `solo` | vanilla solo play outside a session |

## Log check
- `grep -a "SCRIPT\|ERROR"` the logs. Nothing from mod code is allowed: any `ERROR:` mentioning `mods-unpacked` makes the crash reporter disable mods on the next launch.
- Ignore (vanilla prints them too, check with `--disable-mods`): engine shutdown errors (`_first != nullptr`, `self_list.h`, resources/MemoryPool still in use, ObjectDB leaks) and `WARNING: Node './Attach' was modified from inside an instance` on wave load.
- A stray background instance from an earlier run can mix into results; check `ps` first.

## Two machines
Host here, join on the second PC (same layout, its own test copy from `tools/make_test_copy.sh`, the driver copied over with `scp`). Start the client over `ssh` with `DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth.*)` (GNOME Wayland session), pass the test options in that environment too, and start the host 1 s later; discovery finds the host across the LAN. Run `ping` alongside for RTT. Interface byte counters are useless for bandwidth when the other PC syncs files in the background; work it out from `snapshot_bytes` × 20 Hz.

## Manual test by the user
Two windows, `--resolution 1280x720 --position 0,0` and `--position 1280,0`, no role argument (the driver stays idle), started with `nohup` and logging to files. Check the logs afterwards.

## Pitfalls
- The session scratchpad can be emptied between sessions. Godot started with `--path` to a missing copy opens the editor on the last project, `Decompiled/`, which may re-save vanilla files. Rebuild the copy first and check `git status` in `Decompiled/` afterwards.
- Stopping instances: list the PIDs in one command (`ps -eo pid,args | grep "[G]odot_v3.7-dev1_x11.64 --path game"`) and kill them in a separate one. In the same command line as the game's invocation the pattern matches the shell itself, which then kills itself. Don't `pkill -f` with such a pattern either.
- `rm` of a glob after a `cd` in the same command is refused by Claude Code's safety check (the whole command doesn't run). Screenshots overwrite by name, so there is no need to clear them.
- Instances on one PC: a second join-page listener can't bind the discovery port (the page says so; manual join works), and clients load within 0.1 s, so load timeouts can't be hit.

## Acceptance checks (per area)
- **Lobby:** names, characters and ready flags show on every instance; Start is disabled until all players are ready.
- **Wave:** client movement shows on the host and the other way round, no delay on the own player; enemies, hits, deaths and gold match; killing the client process mid-wave doesn't crash the host.
- **Between waves:** shops on different machines finish in any order; bought items persist into the next wave on all peers (compare `log_run_check`).
- **Scale:** 12 slots (fake players), check FPS and bandwidth with about 300 enemies, the arena size and spawn counts against the formulas in [lan-coop-mod.md](lan-coop-mod.md#scaling-and-12-players-steps-45).
- **Input:** keyboard-only and gamepad-only on host and client, including menus and lobby.
