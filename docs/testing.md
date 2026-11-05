# Testing the mod

How to run and check the mod: a throwaway game copy, the test driver (`tools/lan_test_driver.gd`), the regression set, the shipped game and Windows, and the manual test. Open test coverage is tracked in [lan-coop-plan.md](lan-coop-plan.md#tests).

## Workflow
1. Implement, then run the driver's `quit` role once (catches parse errors cheaply; a parse error makes an extension silently absent).
2. Run the driver scenario for the change, plus the relevant part of the [regression set](#regression-set). A bug is first reproduced with a new driver option *without* the fix (e.g. `git stash` the mod change), then checked with it.
3. [Check the logs](#log-check).
4. Manual test by the user in two windows. **Commit only after the user approves.**

## Throwaway game copy
`tools/make_test_copy.sh <scratchpad>/game` builds it in one go (about 300 MB, a few seconds). It does:
- `cp -a ../Game/1.2.0.1/Decompiled <scratch>/game` (`VANILLA=<dir>` for another tree), then removes its `.git`
- replaces `mods-unpacked/Moolt-Lan_Coop` with an **absolute** symlink to `brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop`, and symlinks `tools/lan_test_driver.gd` as `lan_test_driver.gd` (edits to the driver stay tracked in the repo; it is not in the release zip)
- both DLCs are in the sources; the copy owns those listed in `DLCS` (default `abyssal_terrors,primal_dread`, `DLCS=none`: no DLC) through marker files `<copy>/<id>.dlc`: the project has the custom feature `gog`, so the copy runs as the GOG build and looks for the markers in `res://`. Add or remove a marker to change it later
- in the copy's `project.godot`:
  - `config/custom_user_dir_name="BrotatoLanTest"` (under `[application]`); without it, instances use the real `~/.local/share/Brotato` save and log
  - `window/vsync/use_vsync=false` (under `[display]`): covered or unfocused windows stall on vsync under Wayland/XWayland, which also stops the network poll
  - an autoload `LanTestDriver="*res://lan_test_driver.gd"` after `OS_Seaven`

## Running
```
Godot/Godot_v3.7-dev1_x11.64 --path <scratch>/game --resolution 1280x720 --position 0,0 -- <role>
```
- Second instance at `--position 1280,0`. Start `host` with `nohup ... &`, wait 1 s, start `join` the same way, then `wait`; stdout goes to `host.log` / `join.log`. The driver quits each instance at the end of its script.
- Both instances share `user://lan_coop.cfg` (names, port 24999 in that profile, the client's rejoin token; the host's config saves can overwrite the token on disk, so a rejoin after a client restart can't be tested on one machine).
- A second test copy alongside (e.g. another worktree's): give it its own `custom_user_dir_name` in its `project.godot` and its own port in that dir's `lan_coop.cfg`. Discovery uses one fixed port, so the other copy's games show up on the Join page (as incompatible when the protocol differs).
- Add `-vvv` to see `ModLoaderLog` output.
- **Runner script:** keep a small script in the scratchpad (e.g. `run2.sh`) that checks `game/project.godot` exists, exports `SHOT_DIR`, starts `host` and 1 s later `join` with `nohup` (`join` with `env $JOIN_ENV` in front, for options only the client gets), and `wait`s. Call it by absolute path.

## Driver (`tools/lan_test_driver.gd`)
Reads the role from `OS.get_cmdline_args()`. In `_process` it waits for the title screen (`current_scene.filename == MenuData.title_screen_scene`; the game starts in the splash scene `res://pause.tscn`), then runs a timed `match step` script that drives the pages by calling their handlers directly. Its step scripts follow the latest feature under test and get edited for the next one; the header lists roles and options.

### Roles
| Role | Does |
|---|---|
| `host` / `join` | the two sides of a session |
| `solo` | `RunBuilder.build_run` with one entry, `set_coop_run(false)`, `change_scene(MenuData.game_scene)`: vanilla solo play still works without a session. Sets `pause_on_focus_lost` off in memory: vanilla solo pauses when the window loses focus (someone using the desktop meanwhile), and the wave then never ends |
| `lobby` | hosts alone; screenshots the lobby with a character hovered, a starting item's popup, a weapon hovered, nothing hovered; then focuses Mage and its first starting item with the keyboard and logs that the preview keeps Mage until Ready has the focus; opens the settings page (screenshot, focus chain), sets the choice time to 60 and the scaling to Tough (knobs, the help box with the scaling row focused, summary, config), closes it with `ui_cancel` (focus on Settings) and sets 90 and Normal again. The `join` role logs and screenshots its lobby (summary, Settings button) and its read-only settings page (note, every zone entry disabled, a pick leaves the zone unchanged) |
| `title` | screenshots the main menu after 2 s and logs its layout (containers, each left button's rect), then again with Continue toggled (`title_no_continue`); the menu must end within the 1080 px screen |
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
| `CLIENT_QUITS=1` or `=3` with `KILL_ALL=1` | the client waits in the lobby while the run is lost; `client_run_over` logs its hint ("The run is over…") while the host is on its end screen |
| `CLIENT_QUITS=3` / `=4` | at t=18 in the wave the client's connection breaks without a goodbye (`drop_connection`) and it rejoins: unnoticed by the host (the old ENet peer is kept unpolled, so the rejoin takes over a slot that still looks connected) / with the host seeing the disconnect first |
| `SHOP_QUIT=2` | the client's connection breaks silently in the shop; it rejoins and the host goes on without waiting |
| `HOST_DIES=1` | the host also dies at t=18, with the fake: in Team Race (`MODE=team_race`) their team is out and the run ends with that wave |
| `HOST_QUITS=1` | the host closes its game at t=18 in the wave; the client must end with "host left" (goodbye), not reconnect |
| `FAIL_ACK=1` | the next wave's run counts as a digest mismatch on both sides |
| `TIMER_LAG=s` | the client's wave timer s seconds behind |
| `FAKE_SAVED_RUN=1` | a stand-in "Continue" run in memory before the session (never saved) |
| `AIM_TEST=1` | manual aim on both, the client's mouse at its top left |
| `PUSH_TEST=1` | at t=20–26 the client walks straight at the host player, which stands still; both log both positions twice a second (the host's must not change) |
| `CLIENT_WALK=1` | join: in a wave the client's player keeps walking, a new direction every second |
| `HIT_LOG=1` | any role, also idle (manual tests): enemy bullets and enemies entering player hurtboxes, and every player HP change, with the wave time |
| `STALE_DIE_ARGS=1` | host: at t=16 `Utils.default_die_args.from` is a freed node, as vanilla leaves it; with `CLIENT_QUITS=2` the host then kills the left client's player |
| `JITTER_LOG=1` | every 2 s in a wave: frame times, physics ticks per frame, enemy motion per tick (stalls, speed change median/p90; the host's is the vanilla baseline), and on clients snapshot lateness p50/p90/max, clock offset jumps, frames with a dry buffer, the interpolation delay; on the host the remote players' state gaps and how smoothly they are shown (stalls, step change overall and while walking straight, state age) |
| `TEST_VOLUME=x` | master volume at x of the saved one (default 0.2), in every role including the idle manual-test windows |
| `MORTAL=1` | host: players can be hit; at t=16 an enemy is placed on the host player (`hurtbox_hits` line: enemy contacts and enemy bullets on player hurtboxes) |
| `WAVE_DURATION=s` | host: the first wave lasts s seconds (default 20) |
| `CHOICE_TIME=s` | host: the choice time between waves (`lobby_settings.choice_time`) |
| `SCALING_PRESET=n` | host: the enemy scaling preset (0 relaxed, 1 normal, 2 tough), through `set_lobby_settings`, so the test config remembers it: run `SCALING_PRESET=1` once afterwards. `log_sync`'s `coop` line shows the knobs on both sides |
| `IDLE_CHOICE=1` / `=2` / `=3` | no Go in the shop (the choice time presses it; the host presses Go at 13 s left, for the waiting overlay's countdown) / no upgrade picks either / as 2, and the client's time never ends (the host goes on without it after the grace). Both wait for the next wave; `choice_watch` logs and screenshots the countdown at 13, 8 and 3 s left |
| `PERF_LOG=1` | once a second in a wave: enemies, physics bodies/pairs, physics and process time, FPS, enemies culled by the cap (`removed_for_perf`) (`*_curve` lines) |
| `TIMING=1` | with `PERF_LOG`: times all enemy scripts and weapon target scans once a second |
| `ENEMY_CAP=n`, `PHYS_ITER=n`, `NO_ENEMY_COLLIDE=1`, `NO_SYNC=1` | perf experiments: the wave's enemy cap (solo: exactly n), solver iterations, no enemy–enemy collision, host `LanWaveSync` per-tick work off |
| `JOIN_ADDR=ip:port`, `PLAYER_NAME=s`, `PICK=n` | join: join that address instead of the first discovered game (e.g. through `tools/netsim.py`), the client's name, its nth character |
| `HOST_NAME=s`, `FAKE_NAMES=a,b,…` | host: its name and the fake players' names (screenshots, as in the README: `RES=1920x1080` windows, 7 players, `START_WAVE=20 ZONE=1` and `MODE=last_potato`) |
| `EXPECT=n` | host: wait (up to t=120) until n players are in the lobby and ready before Start; the later steps keep their timing relative to Start, and the host's and client's first wave step wait until 3 s into the wave |
| `GPE_TEST=1` | host (Primal Dread; `ZONE=2 START_WAVE=4` for a wave with holes): at t=15 an acid, a petrol and a fire puddle, a single hole, a mutant and a meca spitter, and the enemy time at half speed for 4 s. `log_sync`'s `gpe` lines on both sides (also every `DLC_LOG` seconds): decoration hash, dig sites and poacher zones (`CHAR=character_archaeologist JOIN_ENV="CHAR=character_poacher"`; the test puts the host player on the first dig site and fires a poacher kill and bonus), the brachiosaurus, feet and lasers, charging dinosaurs, consumables, hole layout, puddles by kind and how many have their areas on (clients: 0), evolved enemies by net id, time factor and overlay, the wave seed; clients also check that a puddle of their own is refused (`local_blocked=True`) |
| `PROJ_TEST=1` | host and join: every second in a wave the host deflects one flying player bullet (as the ankylosaurus does); both log the synced player projectiles (id, velocity angle, boomerang phase) in a `_proj` line |
| `ITEMS=id,id` | host: at t=16 those items (or weapons, into free slots) for players 0 and 1; 5 s into the next wave both sides log pets, structures and boomerangs (`_pets`, `_structures`, `_projectiles`) |
| `SPAWN_EVOLVE=meca\|mutant` | host: the `SPAWN` enemies come evolved (meca jungle enemies shoot lasers; `log_gpe`'s `lasers`/`following`) |
| `TARGET_FPS=n` | any role: `Engine.target_fps`, enforced every frame (the game sets its own limit after startup). For many instances on one PC |
| `CLIENT_WALK=2` | join: stop and go (0.6 s walking, 0.6 s standing, the next direction each time) |
| `OVERSHOOT_LOG=1` | host: per remote player and stop, how far the host showed the player past where the client stopped (along its last direction), every 5 s (median, p90, max px) |
| `LOAD_STALL=s` | join: the main thread blocks s seconds when the first wave's `LanWaveSync` enters the tree, as a slow load would (the host's 15 s load timeout) |
| `END_STAY=1` | host and join: stay on the end screen instead of pressing Exit (to look at it by hand; start without `timeout`) |
| `HURT_HOST=n` | host: in wave 1 at 5 s the host player takes n damage; the next-wave check (`log_run_check`) logs every player's `hp=` |
| `SHARE_MATERIALS=0`, `SHARE_CRATES=0` | host: loot sharing off for the run (`lobby_settings`, not remembered) |
| `TOGGLE_TEST=1` | any role, a mode with a scoreboard: in wave 1 Tab at 6 s, the gamepad's Back at 8 s; logs the table's visibility before and after |
| `STORM_EDGE=1` | host, Last Potato Standing: from wave time 24 s the host player is held 60 px outside the storm, towards the arena centre; screenshots at 26, 30, 34 s (`WAVE_DURATION=40`) |
| `TARGET_LOG=1` | any role: once a second in a wave, every player weapon's targets (script, name, distance, Enemy or not), rotation, shooting state, bodies in range that are no Enemy |
| `MODE=id` | host (and the `lobby` role, with `FAKES` fake players): the run's game mode (`lobby_settings.mode`, an id from `modes/mode_registry.gd`), not remembered. `log_sync` and `log_wave_end` log the mode's id, serial and state on both sides (`mode=` lines; the draft pool as its size). With the default 3 players (host, client, fake) the fake dies at t=18: in the elimination modes it is out from then on; in Team Race host and fake are one team, the client the other |
| `PET_TEST=1` | host: at t=16 a Blazemander for player 0 and a Bonk Dog for player 1; 5 s into the next wave both sides log every pet (owner, position, net id) |
| `ZONE=n` | host: the run's zone (`lobby_settings.zone`, 1 = the DLC's Abyss), not remembered |
| `CHAR=id` | host and join: pick that character (e.g. `character_diver`) instead of the nth |
| `ITEM_SETS_OFF=id,...` | host: switches those item sets off before hosting (in memory, e.g. `primal_dread`). Both log `lobby_item_sets` (the sets in use, the characters left out of the grid and the picked character's left-out weapons, the weapon label) after their pick; `CHAR=character_survivor` picks two weapons (`picked` line) |
| `TRY_CHAR=id` | join (with `EXPECT=2` on the host, it takes a second): asks the host for that character before the pick and logs what it got (`try_char`; a character from a set that is off: `got=''`) |
| `MECA_TEST=1` | host and join, Primal Dread on: at t=16 meca parts at the host's player and a mutation fruit at the client's; 1.5 s later both log each player's things-to-process consumables (`meca_test`: player 0 `meca_parts_consumable`, player 1 `mutation_consumable_fruit`, on both sides) and the meca parts count |
| `CURSE_TEST=1` | host and join (DLC): every item in the first shop is cursed before the buy and the lock; `log_run_check` logs each player's cursed gear and a hash of all its gear's effects (must match on both sides) |
| `SPAWN_NEAR=1` | host: the `SPAWN` enemies 250 px around the host player |
| `CHARM_BOOST=1` | host: at t=13 players 0 and 1 get 200 max HP: a Romantic then charms on every hit that leaves an enemy below 25 % HP (vanilla's charm path, from both players' hits) |
| `DLC_ITEMS=k` | host (DLC): at t=16 the DLC's items and weapons with index % 7 == k for players 0 and 1; k = 0..6 covers all (with `WAVES=2`, the shop merge and a wave with them). `DLC_SET=id`: which DLC's item set (default `abyssal_terrors`; `primal_dread`) |
| `DLC_LOG=s` | any role: every s seconds in a wave, `log_sync`'s `dlc` line (long waves) |
| `FULL_SLOTS=1` / `=2` | host and join (also the `solo` role): at t=16 the host fills players 0 and 1's weapon slots with knives; in the shop each buys a knife first, which vanilla merges into one of theirs, and presses Go in the same frame (`=2`: a second later). Vanilla's merge raises an engine `grab_focus` "!is_inside_tree()" error (not the mod) |
| `GEAR_DUMP=id,id` | host and join: `log_run_check` prints those items' serialized data in full (to diff a `gear_md5` mismatch; the per-item hashes are always logged). `dmg_dealt_last_wave` is left out of the hashes: the host counts it during the wave |
| `BOSS=path`, `BOSS_HP2=n` | host: the boss spawned at t=13 instead of the rhino (e.g. `res://entities/units/enemies/abyss/elites/giant/giant.tscn`, `…/abyss/bosses/eel/eel.tscn`); its HP at t=18 of 5000 (default 2500; the eel's phase 2, which adds pivots, is below 2000) |
| `SPAWN=path` | host: four more enemies of that scene at t=13 (e.g. the DLC's pufferfish, stargazer, viperfish) |
| `CHARM_TEST=1` | host: at t=15 charms every spitter (needs a charm effect: `CHAR=character_romantic`) |
| `CURSE_ENEMIES=1` | host and join (DLC): vanilla's `DebugService.curse_enemy_spawn` on both sides; `log_sync`'s `outlines` line: cursed enemies' net ids, boosted and charmed counts, scene effect behaviours (clients: 0) |
| `RELOAD_RACE=1` | host and join: when the wave-end state arrives, every player is queued for a stats reload in main's `StatsManager` (as a stat change in the wave's last frames leaves it); without the drop before the solo view this raised script errors under the mod's path |

`WAVES=n` counts from the run's first wave, so it combines with `START_WAVE`. When the host's end steps are still in a wave (`WAVES=n` ends in wave n+1), it quits instead of calling `net.leave()`.

### Helpers and checks
- Between waves, every frame: `pick_upgrades` (first upgrade, or take the crate item on the host and recycle it on the client; logs the picked stat per player), `shop_actions` (buy one item, lock another, Go; the client goes Back and Go again; the host is last), `end_screen_actions` (log the end screen, Exit: the client first).
- `solo_view_test` (on `LanNet.wave_end_ready`) enters and leaves the solo view once and checks the run is unchanged.
- `progress_test` (t=16 in the first wave, both roles): the host completes a challenge with a reward it doesn't have (forwarded); the client tries one on its own (ignored in a wave, `(expected false)`); both add a jellyshield and log its angle against the wave time. `log_progress` (wave start, wave end, end screen, after the session): character challenges of every lobby character, challenges new in the session, lifetime counters (host and client must match after the wave end). `progress_after_session`: each session challenge's reward and whether it is in the own unlock lists. With `START_WAVE=20` each machine's end screen shows only its own character's challenge done.
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
- **In the wave:** `get_tree().current_scene` is `main`; read `_players`, `_players_ui`, `_wave_timer`, `get_node("%LifeContainerP12")`; move the host with `Input.action_press("button_move_right_0")` (device 0: the local player in a session, keyboard and gamepad); kill a player with `_players[i].die()`; Quit with `_pause_menu.get_node("Menus/MenuConfirm")._on_ConfirmButton_pressed()`.
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
| `CLIENT_QUITS=3 WAVES=2`, `CLIENT_QUITS=4 WAVES=2`, `SHOP_QUIT=2 WAVES=2`, `HOST_QUITS=1` | rejoin after a lost connection (host log: "rejoined as player 1"; the client's player is alive in wave 2), the host's goodbye |
| `START_WAVE=20 FAKE_SAVED_RUN=1` | run won; own "Continue" run untouched |
| `ROUNDS=2 KILL_ALL=1` | stale wave-end state across runs |
| `FAIL_ACK=1 WAVES=2` | next-wave digest mismatch doesn't freeze |
| `TIMER_LAG=0.3` | no wave-timer ticking in the upgrade screen |
| `CHOICE_TIME=20 IDLE_CHOICE=2`, `CHOICE_TIME=25 IDLE_CHOICE=1`, `CHOICE_TIME=15 IDLE_CHOICE=3` | choice time: random upgrades and crates, Go in the shop, the host going on without a stuck client |
| `AIM_TEST=1 FAKES=5` | remote manual aim, off-screen arrows, skulls |
| role `lobby` | lobby layout, previews and the settings page |
| role `solo` | vanilla solo play outside a session |
| `PUSH_TEST=1` | a client walking into the host's player doesn't push it (host position unchanged, the client stops ~48 px away) |
| `PET_TEST=1` | pets spawn on both sides at the same positions |
| `LOAD_STALL=8`, `LOAD_STALL=20` | the host waits for a slow client ("every client loaded" after ~8 s) and starts after 15 s without it ("timed out"); the late client plays on |
| `RELOAD_RACE=1`, `RELOAD_RACE=1 FAKES=5 WAVES=2` | no script errors when stats reloads are pending at the solo view |
| `MODE=coop ZONE=1 WAVES=3 CURSE_TEST=1` with `CHAR=` DLC characters, `ZONE=1 START_WAVE=20`, `ZONE=1 CURSE_ENEMIES=1` | DLC: Abyss waves, cursed gear through the shop merge (equal `gear_md5`), the Abyss boss and run won, cursed enemies' outlines on the client |
| `MODE=coop ZONE=1` with `BOSS=…/giant/giant.tscn SPAWN=…/viperfish/viperfish.tscn`, `BOSS=…/eel/eel.tscn BOSS_HP2=1500`, `CHARM_TEST=1 SPAWN=…/pufferfish/pufferfish.tscn` (host `CHAR=character_romantic`), `SPAWN=…/stargazer/stargazer.tscn` | DLC enemies on the client (`dlc` line, compare at the same `time_left`: also mirrored lungs, angry stargazers, charmed enemies): pivot directions equal and angles ~0.1 s behind, Pursuer sizes equal, `hue` > 0 on both after the charm, `local=0` on the client, full lungs |
| `MODE=coop ZONE=1 WAVES=2 START_WAVE=6 DLC_ITEMS=k` for k = 0..6, each with two DLC characters (`CHAR`, `JOIN_ENV="CHAR=… CLIENT_WALK=1"`) | DLC characters and all DLC items and weapons: no script errors, equal digests and `gear_md5` |
| `CHAR=character_hiker JOIN_ENV="CLIENT_WALK=1"` | `steps` line: the host counts the client's steps (about the client's own count) |
| `CHAR=character_romantic CHARM_BOOST=1 START_WAVE=8 ENEMY_MULT=2 WAVE_DURATION=40 DLC_LOG=5` | charm in a real fight: charmed enemies on both sides |
| host in a DLC copy, `join` in a `DLCS=abyssal_terrors` copy | the client is turned away ("different set of DLCs") |
| shipped build ([below](#shipped-game-and-windows)): `quit`, `solo`, host + join `WAVES=2` | the mod in compiled vanilla scripts: no script errors, every extended base's subclasses inherit the extension |

## Log check
- `grep -a "SCRIPT\|ERROR"` the logs. Nothing from mod code is allowed: any `ERROR:` mentioning `mods-unpacked` makes the crash reporter disable mods on the next launch.
- Ignore (vanilla prints them too, check with `--disable-mods`): engine shutdown errors (`_first != nullptr`, `self_list.h`, resources/MemoryPool still in use, ObjectDB leaks) and `WARNING: Node './Attach' was modified from inside an instance` on wave load.
- A stray background instance from an earlier run can mix into results; check `ps` first.
- Twice (2026-10-23/24, once each on the code before and after the run-over hint) a test client quit cleanly mid-run without a driver step or error (normal shutdown lines, the host logs "left"); a rerun passed. Cause unknown; rerun before suspecting a change. Also seen in back-to-back runs (2026-10-27): the client never finds the host's game (no `join first row` line), the host starts without it and the client quits normally; a rerun passed.

## Two machines
Host here, join on the second PC (same layout, its own test copy from `tools/make_test_copy.sh`, the driver copied over with `scp`). Start the client over `ssh` with `DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth.*)` (GNOME Wayland session), pass the test options in that environment too, and start the host 1 s later; discovery finds the host across the LAN. Run `ping` alongside for RTT. Interface byte counters are useless for bandwidth when the other PC syncs files in the background; work it out from `snapshot_bytes` × 20 Hz.

## Shipped game and Windows
The test copy runs the decompiled `.gd` sources. The shipped game (Steam/GOG, any OS) runs compiled `.gdc` scripts, and some script handling differs there (the 1.12.0 zip didn't start in it at all: [lan-coop-mod.md](lan-coop-mod.md#pitfalls-learned), early extensions). Run the shipped build after changing `mod_main.gd`, adding an extension, or touching script loading, and before a release.
- **The driver as a mod:** `tools/make_driver_mod.sh <zip>` packs `tools/lan_test_driver.gd` as `Moolt-LanTestDriver.zip` (it adds the driver to the root as `LanTestDriver`). Put it next to `dist/Moolt-Lan_Coop.zip` (`./build.sh`) in the game's `mods/`. Roles and options work as in the test copy.
- **Shipped build on Linux:** the GOG Windows `.pck` (e.g. `~/Downloads/Brotato - Multiplayer/Brotato.pck`) runs with this repo's Godot binary: copy it as `Brotato.x86_64` next to the `.pck`, then `XDG_DATA_HOME=<dir>/xdg ./Brotato.x86_64 --main-pack Brotato.pck --mods-path=<mods dir> -- <role>`. `--mods-path` is needed: the editor binary has the `editor` feature tag, so ModLoader looks in `res://mods` and loads nothing. DLC ownership there: the `<id>.dlc` markers next to the binary, as in the GOG install (not yet tried with 1.2.0.1), and two instances on one PC run with vsync on, which stalls covered windows under XWayland (the join page's entry comes and goes, the client is choppy, the first join can fail); use one instance per PC for anything about smoothness.
- **Windows PC** over OpenSSH (cmd.exe login shell; send PowerShell as `powershell -NoProfile -EncodedCommand <base64 of UTF-16LE>` to avoid cmd quoting): a test copy of the shipped game in `<dir>\game` (`Brotato.exe`, both `.pck`, the store's dlls, `mods\` with both zips). `tools/win_run.ps1` copied to `<dir>` (`<dir>\win_run.ps1 <name> <role> "K=V …" "--resolution 1280x720"`) starts the game as a scheduled task in the logged-in desktop session (a process started from ssh has no window or OpenGL), with its own `APPDATA` per name (the real save in `%APPDATA%\Brotato` stays untouched) and stdout in `logs\<name>.log`, ending with `exit <code>` when the game quit. Wait for that line, then `scp` the log. The user must be logged in on the desktop.
- Don't use an `override.cfg` next to `Brotato.exe` (e.g. for the user dir): ModLoader then believes it was installed through it ("override.cfg setup detected, ModLoader will be the last autoload loaded") and loads differently from players' games.
- **Cross-platform:** host here (test copy) and `join` on Windows started 1 s earlier, or the other way round; both copies have the DLC, so they match. Windows Firewall didn't ask (2026-10-28).

## Many real players
`tools/run12.sh` (with `SCRATCH=<scratchpad>`) runs the host and `ND` clients (default 6) on this PC and `NN` (default 5) on the second PC, every client in its own user dir (`XDG_DATA_HOME`) and joining by `JOIN_ADDR` through `tools/netsim.py`, a UDP proxy with one port and link profile per client: `lan`, `wifi` (2–8 ms, 0.3 % loss, occasional 20–60 ms holds), `wifips` (power saving: a 50–170 ms hold about every second, 1 % loss), `bad` (15–45 ms, 3 % loss, 80–250 ms holds, 1 % reorder). Packets of a flow stay in order, so jitter arrives as bursts like on WiFi. Clients walk (`CLIENT_WALK=1`) and log `JITTER_LOG`; pass `PERF_LOG=1`, `WAVES=n`, `HOST_EXTRA="START_WAVE=18 WAVE_DURATION=60"`, `CLIENT_ENV=TARGET_FPS=60`. `DIRECT=1` lets the second PC's clients join the host without the proxy. With `WAVES=20` the driver plays a whole run: after wave 20's end screen both sides note the run is over and leave. Results of 2026-10-24 are in [lan-coop-plan.md](lan-coop-plan.md#performance).
- **Host performance needs the host alone on its PC.** Six client instances on the host's PC (even capped at 60 FPS) push the host's physics ticks past 16.7 ms and into catch-up (2–8 ticks per frame, 5–45 FPS). With the clients elsewhere (`ND=0`, fakes for the other slots: `HOST_EXTRA="FAKES=6 EXPECT=12"`) the same wave runs at ~200 FPS. Measure the host with `ND=0`; use `ND>0` for sync and flow checks.
- Cap the clients with `CLIENT_ENV=TARGET_FPS=60`; uncapped instances run at several hundred FPS and starve each other and the host.
- The second PC (laptop, RTX 3060 Mobile) crashed in the NVIDIA GL driver (SIGABRT) with 10 instances open; 5 run fine. Before a run, check that no instance of an earlier run is left there.

## Manual test by the user
Two windows, `--resolution 1280x720 --position 0,0` and `--position 1280,0`, no role argument (the driver stays idle), started with `nohup` and logging to files. Check the logs afterwards.
`tools/play2.sh [game copy]` does this: it builds a test copy at `~/.cache/brotato-lan-test/game` on first use (`make_test_copy.sh`), closes that copy's open windows, starts both and logs to `~/.cache/brotato-lan-test/logs/left.log` / `right.log`. `GODOT` overrides the binary (default `../Godot/Godot_v3.7-dev1_x11.64` next to the repo), `WIDTH` / `HEIGHT` the window size.

## Pitfalls
- `log_lobby` prints `dlcs=[primal_dread, abyssal_terrors] sets=[…]`; vanilla's lines `DLC marker res://<id>.dlc found: …` (stdout and `~/.local/share/BrotatoLanTest/GOG-Saves/log.txt`) show what was found. `ZoneService.zones` always has all three zones; a lobby zone whose DLC isn't owned is refused (`LobbyRules.is_valid_zone`).
- The test profile's save is `~/.local/share/BrotatoLanTest/GOG-Saves/save_v3_0.json` since 1.2.0.1 (copied once from `user/`). Two instances share it and can corrupt it (a shorter write over a longer one: `Error parsing JSON at line …: Expected 'EOF'` at startup); vanilla then starts from an empty save, which is fine for tests.
- The test profile remembers lobby settings (`lan_coop.cfg`, e.g. `last_mode` from a manual test); pass `MODE=coop` when a run must be plain co-op.
- The session scratchpad can be emptied between sessions. Godot started with `--path` to a missing copy opens the editor on the last project, `Game/1.2.0.1/Decompiled/`, which may re-save vanilla files. Rebuild the copy first and check `git status` in that `Decompiled/` afterwards.
- Stopping instances: list the PIDs in one command (`ps -eo pid,args | grep "[G]odot_v3.7-dev1_x11.64 --path game"`) and kill them in a separate one. In the same command line as the game's invocation the pattern matches the shell itself, which then kills itself. Don't `pkill -f` with such a pattern either.
- `rm` of a glob after a `cd` in the same command is refused by Claude Code's safety check (the whole command doesn't run). Screenshots overwrite by name, so there is no need to clear them.
- Instances on one PC: a second join-page listener can't bind the discovery port (the page says so; manual join works), and clients load within 0.1 s, so load timeouts can't be hit.
- A kill command whose `grep`/`pkill -f` pattern contains a script name (e.g. `run12.sh`) also matches the shell running it, which then dies before the rest of the command (e.g. the `ssh` to the second PC) runs. Collect PIDs first, kill in a separate command, on each machine.
- The driver moves players with the device 0 actions (`button_move_left_0` …): in a session the local player has device 0. The device 7 actions it used before 2026-10-24 moved nobody, so `PUSH_TEST` and the paused-client check passed without movement.
- Shop: the driver locks only an item that isn't locked yet. Vanilla's `change_lock_status(true)` on a locked item adds it to the locked list again (the real button toggles), which grew the list past the shop's 4 slots and raised errors in vanilla `is_shop_item_locked_visually`.
- If a player leaves the lobby while Start waits for the run acks, the built run is dropped (every lobby change makes it stale) and the host has to press Start again; the driver doesn't.

## Acceptance checks (per area)
- **Lobby:** names, characters and ready flags show on every instance; Start is disabled until all players are ready.
- **Wave:** client movement shows on the host and the other way round, no delay on the own player; enemies, hits, deaths and gold match; killing the client process mid-wave doesn't crash the host.
- **Between waves:** shops on different machines finish in any order; bought items persist into the next wave on all peers (compare `log_run_check`).
- **Scale:** 12 slots (fake players), check FPS and bandwidth with about 300 enemies, the arena size and spawn counts against the formulas in [lan-coop-mod.md](lan-coop-mod.md#scaling-and-12-players-steps-45).
- **Input:** keyboard-only and gamepad-only on host and client, including menus and lobby.
