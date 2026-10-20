# Brotato LAN Co-op Mod (Moolt-Lan_Coop): Plan

Goals, design decisions, progress and **open work**. How the mod is built (files, flow, protocol, pitfalls): [lan-coop-mod.md](lan-coop-mod.md). How to test: [testing.md](testing.md). The detailed history of each step is in the git log.

Keep this file current: tick items when they are done (with a one-line note of where it lives), add new gaps and todos as they come up, and move as-built detail to [lan-coop-mod.md](lan-coop-mod.md) rather than here.

## Goal
Brotato 1.1.15.4 (Godot 3.7, ModLoader 6.3.0, which has no hooks, only `install_script_extension` / `take_over_path`) ships local couch co-op for up to 4 players. The mod turns it into LAN co-op:
- [x] up to 12 players, one per machine
- [x] keyboard and gamepad (controller text entry still open, see [Polish](#polish))
- [x] host/join by IP or from discovered games, via a "Multiplayer" main-menu button
- [x] player names, over the players' heads in the wave
- [x] a lobby with every player, character and weapon select, ready-up
- [x] a larger arena and more enemies as the player count grows
- [x] upgrades and shop per machine between waves

## Design decisions
These hold for all further work; changing one is a design change, note it here.
- **Host-authoritative state sync.** Lockstep is impossible: RNG is spread over 250+ call sites using global `randf` / `rand_range`, and physics is RigidBody2D.
- **The host runs the real game as a vanilla coop run with N players.** Clients run `main.tscn` in puppet mode: they spawn copies of the host's entities through vanilla code, make them inert, and render them from snapshots and events.
- **Each machine moves its own player.** Rendering the own player from 20 Hz snapshots would add 60–120 ms of input delay, and removing that later would need client-side prediction. A client faking its position doesn't matter in LAN co-op. Consequences: the host sees a client's position 1–5 ms late (over WiFi with power saving its states come in bursts; the host dead-reckons in between, so only direction changes show late), a client sees enemies 100–300 ms behind (interpolation, adaptive to the snapshots' lateness), so a last-moment dodge can occasionally count differently. Speed, HP, death, gold and XP still come from the host.
- **Between waves every machine runs the vanilla *solo* upgrade UI, shop and end screen** on a 1-player view of `RunData` (the solo view) and sends its `PlayerRunData` back; the host merges. The coop UIs are hardcoded to 4 slots and one screen.
- **Runs travel as JSON through vanilla's save loader** and are checked with a digest (`RunBuilder`). At Start a mismatch keeps everyone in the lobby; between waves the host's run wins.
- **Everything unlocked during a session** on every peer (item pools match), saves blocked, own progress and "Continue" run restored on leave.
- **4-slot arrays grow to 12 always**, not only in a session (vanilla never reads beyond the player count).
- **Everyone dead ends the run** in a session (no retry screen yet, see [Features](#features)).
- **Never edit vanilla files**; only script extensions. **No `push_error` or script errors from mod code** (the crash reporter disables mods on the next launch).

## Progress
- [x] **Step 0: Context docs.** `CLAUDE.md` index and `docs/brotato/*.md`.
- [x] **Step 1: Networking core.** `LanNet`: ENet, handshake, lobby state, unlocks, disconnects.
- [x] **Step 2: Menus and discovery.** Multiplayer, Join and Lobby pages; UDP beacon.
- [x] **Step 3: Lobby.** Picks, ready, host settings, run build and sync (3a–3c).
- [x] **Step 4: 12 players.** Caps lifted, HUD P5–P12, spawn circle, names and bars over heads (4a–4c).
- [x] **Step 5: Arena and enemy scaling.** Knobs in `[scaling]`, camera on the own player.
- [x] **Step 6: In-wave sync.** Players, entities, combat visuals, loot, pause, dropouts, run end (6a–6f).
- [x] **Step 7: Between waves.** Wave-end state, solo view, solo upgrades and shop, host merge, end screens (7a–7f).
- [ ] **Step 8: Polish** (in progress). Done: 8a in-wave visuals and aim, 8b lobby layout. Open: [Polish](#polish), [Performance](#performance), [Tests](#tests).
- [ ] **Step 9: Feature additions.** [Features](#features).

Milestones:
- [x] 1 docs, 2 connect, 3 synced start, 4 full wave, 5 between waves
- [ ] 6 scale: 12 players, arena, enemy scaling and disconnects done; the [perf pass](#performance) is left

## Open work

### Bugs
Reported in play (2026-10-19), not reproduced yet.
- [ ] **Left stick stops working in a session:** in the level-up upgrade selection, the shop, and also in the wave (the player can't be moved with it). It works in single player; in a test on 2026-10-20 it worked in the first level-up and then stopped. Sessions use native focus instead of the FocusEmulator between waves (see the pitfalls in [lan-coop-mod.md](lan-coop-mod.md#pitfalls-learned)); the D-pad works there, so check how vanilla maps the stick to UI navigation.
- [x] **Enemy bullets fly through players without hitting** (fixed 2026-10-20, two causes). The host applied the damage (driver `HIT_LOG`: 25 of 26 bullets on the host player, 6 of 9 on the client's), but (1) a bullet that hit was never reported as stopped: vanilla `stop()` pools enemy bullets at once and clears their net id, so clients' copies flew on; (2) the host's copy of the client's player froze for up to ~200 ms at a time (WiFi power saving sends the client's states in bursts), so enemies aimed at and hit a stale position. Now `projectile.gd` reports with the id taken before `stop()`, and the host dead-reckons remote players.
- [x] **Client player lags on the host** (fixed 2026-10-20). See above: states arrive at 7–30 per second in bursts. With dead reckoning (age from a client timestamp, protocol 16; velocity from the last two states) the shown player no longer stalls (36–77 frozen ticks per 2 s → 0–1), per-tick step change median 0–1 %, p90 3–13 % with turns every second (`CLIENT_WALK=1 JITTER_LOG=1`).
- [x] **The client's player pushes the host's** (fixed 2026-10-20, from the dead reckoning above): the host extrapolated the client's player along the pressed direction, also while the client was blocked by the host player (which it sees 100–300 ms in the past), so its copy was moved into the host's player and the host's kinematic movement pushed itself out (`PUSH_TEST=1`: ~340 px in 4 s). Now the host extrapolates with the velocity between the client's last two states (0 when blocked): the host moved 5 px at contact, then stayed; still slightly pushable in play (overlap while the client is still moving or sliding along). So the host also moves the client's copy with `test_motion` and a slide, as vanilla moves units, instead of placing it: it stops at the host's player. `PUSH_TEST=1`, twice: the host's player doesn't move at all, the client stops at 48 px.
- [x] **Freed killer in `Utils.default_die_args`** (fixed 2026-10-20): the session's `die()` calls for players (left client, dead in the snapshot) used vanilla's shared default args, whose `from` can be a freed killer; `main._on_player_died` then raised a script error under the mod's path (crash reporter). Reproduced with `STALE_DIE_ARGS=1 CLIENT_QUITS=2`: 3 errors before, 0 after.

### Polish
Visuals, controls and menus with what exists (Step 8). Done so far:
- [x] Names over players (4c); everything unlocked in multiplayer (Step 1).
- [x] Off-screen teammate arrows (8a, `game/offscreen_arrows.gd`).
- [x] Coloured outlines: obsolete, vanilla coop already highlights each player in their colour.
- [x] Skull under dead players' names (8a).
- [x] Mouse aim for keyboard players, remote aim point on the host (8a, protocol 15).
- [x] Lobby layout: both previews, starting items with popups, grids fill the height (8b).
- [x] End screen player dropdown: any player's stats, weapons and items, own player first.
- [x] Default player names: a random potato name (`net_config.gd` `DEFAULT_NAMES`); the host appends " 2", " 3", … to a name already in the lobby.

Open:
- [ ] **Name overlap.** 12 names overlap when players stand close, e.g. on the spawn circle at wave start. Options: fade names while they overlap, or shorten long names.
- [ ] **Lobby hint for a client that quit to the lobby.** It shows "A wave is in progress" until the host is back from its end screen, because it gets no end-of-run notice (`LanNet.run_over` is only set in `main`). The host's wave-end state at the run's end, or the lobby broadcast, could carry it.
- [ ] **Controller text entry.** An on-screen keyboard for the name and the join address. Until then controller players keep the default name and join from the discovered games list.
- [ ] **End screen sorted by kills.** The player dropdown lists players by index. Vanilla only counts kills globally (`ProgressData` `enemies_killed`, `main.gd`), not per player. Count kills per player on the host (the killer's player index from the hit), carry them in the run state, then sort the dropdown by them and show the count.
- [ ] **End screen focus.** Vanilla `end_run.gd` gives the focus to the New Run button (hidden in a session) after an inventory element is pressed; with a gamepad the focus is lost until the mouse or a direction moves it.

### Performance
Milestone 6's perf pass.
- [x] **Snapshot size.** Above about 170 entities (12 slots) a snapshot exceeds ENet's 1392-byte MTU and is fragmented (8 bytes per entity, 33 per player; the engine warns once). Measured over WiFi between two machines (2026-10-18): no drops at 2 or 3 packets (207 of 207 at 3 packets, 400+ entities), so no split needed.
- [x] **Spawn rate.** `EntitySpawner` releases queued enemies at a fixed 20–40/s whatever the player count. Measured (2026-10-18): 12 slots, normal wave 18, the cap (then 375) is reached within ~20 s, so the queue doesn't limit the count.
- [x] **Load check at scale.** 12 slots, wave 15, `ENEMY_MULT=10`, host Ryzen 7 5800X3D (wired), client Ryzen 5 5600H laptop (5 GHz WiFi), uncapped: ~300 entities: host 260 FPS, client 63 FPS; snapshots 2.7 KB at 20 Hz (~54 KB/s per client). Mod cost is small: `_build_snapshot` ~1 ms per 400 entities every 3rd tick, client `_update_puppets` ~1.4 ms per frame at 300.
- [x] **Physics cliff at high enemy counts** (measured 2026-10-18, driver `PERF_LOG=1`, host alone with 11 fake players, normal wave 18). A normal 12-slot wave reaches the cap (~390) within ~20 s; vanilla physics then takes 38–45 ms per tick (60 Hz needs < 16.7) and the host runs at ~4 FPS (laptop host: ~2). Vanilla solo hits the same wall (238 FPS at 359 enemies, 17 at 443), the sync doesn't matter (`NO_SYNC=1`: same). Cause: collision pairs (~42k at 400), mostly from two vanilla quirks, both fixable without a gameplay change:
  - [x] **Burning `SpreadArea` always on.** Every unit's `BurningParticles/SpreadArea` (r = 128, mask 4) starts enabled and is only disabled after a burn (`deactivate_spread`), so it pairs with every enemy body and hitbox within ~170 px and fires `body_entered`/`body_exited` in GDScript. It only matters while burning with spread; `unit.gd` `apply_burning` turns it on then. Fix: disable it on spawn/respawn for units that aren't burning. Alone: 41 → 18.6 ms per tick at 330–450 enemies. Done in a session (`burning_particles.gd`); checked: fire still spreads (driver `burn_spread_test`, 4 of 4).
  - [x] **Enemy hitboxes on the enemies layer.** `Hitbox` (layer 4) shares the layer with enemy bodies (mask 132) and weapon/turret ranges (mask 5), so every nearby enemy pair also makes two body–hitbox pairs, and every weapon range pairs with hitboxes too. Only hurtboxes need them (`area_entered`; player and scapegoat, mask 20); everything else on mask 4 uses `body_entered`. Fix: hitbox layer 4 → unused layer 20 (bit 19) on enemies, add bit 19 to hurtbox masks that have bit 4. Alone: 24.8 ms. Done in a session (`enemy.gd`, `overlap/hurtbox.gd`); checked: contact hits still land (`MORTAL=1`).
  - Both together (desktop host, 330–450 enemies): 4 → ~90 FPS, 8k pairs, ~18 ms worst tick per second. Laptop host: 150–250 enemies 28 → 113 FPS, 250–330 4 → 44, 330–450 2 → 8.
  - Tried, no real gain: solver iterations 4/2 (`Physics2DServer.set_collision_iterations`), cell size 64/256, `thread_model=2`, BVH (`use_bvh=false` in vanilla; only helps without the fixes, and needs `override.cfg`), pausing idle `BurningParticles` scripts, enemies not colliding with each other (17.2 vs 17.9 ms with both fixes). Enemy scripts ~1.5 ms, weapon target scans ~0.05 ms per weapon at 400 (~3.5 ms with 72 weapons).
  - Left after the fixes: per-body integration and the `_integrate_forces` GDScript callback (~6 ms at 400), players, gold, projectiles. Note: `TIME_PHYSICS_PROCESS` is the longest tick of the last second, updated once a second.
- [x] **Clients: puppets without a collision mask.** Puppets are inert (`_make_inert`) but keep layer and mask, so the client pairs them like the host. Mask 0 (keep layer 4: client weapons turn towards targets via their `Range` areas) plus the two fixes above: laptop client at 330–450 enemies 5 → 41 FPS, 250–330 34 → 109. Layer 0 as well would give ~95 but stops client weapons from tracking targets. Done: `_make_inert` keeps only the walls bit (dying units slide with knockback and still stop at walls).
- [x] **Host: keep the enemy count under the cliff.** Even with the fixes a laptop host falls behind past ~300. Done: cap factor at most 2.5 (`LanGame.MAX_ENEMY_CAP_FACTOR`, 250 enemies). With all fixes, 12 slots, normal wave 18 at 250–330 enemies: desktop host 216 FPS, laptop client 100, laptop host 49 (was 6 / 5 / 2–4).
- [x] **Balance beyond 7 players: count up to the cap, the rest as enemy HP** (2026-10-19). `LanGame.apply_enemy_scaling`: the spawn count stops at the player count where the cap factor reaches its max (`get_count_players`, 7), and enemy HP takes the cut-off count factor (12 players: count 4.3 → 2.8×, HP 3.5 → 5.4×, count × HP unchanged). Vanilla's material bonus follows the lower count (12: 2.4 → 3.6× per enemy). 12 slots, normal wave 18, host alone with standing fake players: enemies culled without loot in 44 s 643 → 384, FPS unchanged (~200). Up to 7 players nothing changes.
- [ ] **Culling with real players at 8–12.** Even with the count stopped, standing fake players with one weapon kill too slowly and the cap still culls. Check `removed_for_perf` (driver `PERF_LOG` line) in a real 8+ player late wave; if it stays high, let the count follow the cap more closely (count factor = cap factor) or raise the cap a little now that physics is cheaper.
- [x] **Interpolation delay on WiFi** (2026-10-19, micro-stutters on the laptop client). No snapshot loss, but with WiFi power saving on (on the notebook with NetworkManager's default setting; ping 2–170 ms, median ~5) snapshots arrive in bursts up to ~170 ms late, so the fixed 100 ms buffer ran dry and puppets stalled. Also puppets were placed by `OS.get_ticks_msec()` at the moment each tick ran (steps of 16 or 17 ms: a constant 6 % wobble), and the clock offset crept up 20 ms/s and snapped back several times a second. Not a regression (1.2.0 the same). Now: adaptive delay (largest lateness of 5 s + 10 ms, 100–300 ms), a render clock that advances by the physics step and steers ±10 %, offset drift 1 ms/s. Driver `JITTER_LOG`, laptop client: frames with a dry buffer from up to ~1000 per 2 s to 0 in most windows, per-tick speed change median 6 % → 0–1 %, p90 14–98 % → 3–31 %.
- [ ] **Discovery over WiFi with power saving.** Broadcast beacons (`net_discovery.gd`, every 1 s, a game drops after 3.5 s) reach a power-saving laptop unreliably: 10 of 39 broadcasts lost, gaps up to 4.9 s, so the game list flickers or comes up empty. Unicast to the same laptop: 40 of 40, gaps at most 1.2 s. Fix: the join page broadcasts a query (sending isn't affected) and the host answers it with a unicast beacon; keep the broadcast beacons as they are. Until then the driver's join step retries for up to 10 s.
- [ ] **Interpolation delay across waves.** Each wave's `LanWaveSync` starts at 100 ms again, so the first late snapshots of a wave still stall puppets briefly. Keep the last delay in `LanNet` for the next wave.

### Tests
What the driver and manual tests haven't covered yet ([testing.md](testing.md)).
- [ ] Full runs on separate machines (two players).
- [ ] More than two real players (the driver's fake players are never sent anything).
- [ ] Pets (same data-ref path as structures, which are tested).
- [ ] The 15 s client load timeout (clients on one PC load within 0.1 s; on two machines too: 0.2–0.3 s).
- [ ] Driver: its end steps assume the lobby by t=55, but after wave 1 and the shop it is in wave 2, so the host's `net.leave()` runs mid-wave. `_end_session("")` resets RunData without changing the scene, and with 12 players a fake player's weapon then errors in vanilla `get_player_effects` (reported under the mod's extension path). Not reachable in play (only menus call `leave()`); have the driver quit instead of leaving when it is still in a wave.
- [ ] Keyboard-only and gamepad-only on host and client, through lobby, wave, upgrades, shop and end screen.

### Known limitations
Accepted for now; tick one if it gets fixed, or promote it to a todo if it shows up in play.
- [ ] Entities spawned before `LanWaveSync` exists (jellyshields in `Player.init`) aren't synced; each machine keeps its own.
- [ ] `GroupOfBullet` bullet-hell patterns (`BulletHell_2` / `_3`) aren't synced; vanilla never picks them today.
- [ ] Weapon attack events that arrive while the client's copy is still busy are skipped.
- [ ] Progress from LAN runs: `RunData.apply_run_won` credits the character challenges and difficulty records of every player's character on every machine, and challenges completed in a session may be dropped when the own unlock lists are restored. Needs a decision (see [Features](#features)).

### Features
New mechanics, settings and modes (Step 9). Each needs a design decision first.
- [ ] **Mod config** in the manifest `config_schema` (ModLoader's mod settings): the scaling knobs (now `lan_coop.cfg` `[scaling]`), the port, and the host settings below.
- [ ] **Material sharing option.** Vanilla coop splits every picked-up material round-robin over all players (1 material and 1 XP per unit, `main.gd` `on_gold_picked_up`, also the mod's copy for > 4 players); only the picker's own pickup effects apply. A host lobby setting (synced like the scaling knobs) could keep materials and XP with the picker. Crates have vanilla's own option (`share_coop_loot`).
- [ ] **Upgrade countdown.** Waiting for everyone between waves gets tedious with many players. A countdown that starts once some players are done, or after a fixed time; when it runs out the host picks the remaining players' upgrades (first or random option) and presses Go with their wave-end state. Duration as a config knob, 0 = off. The host's waiting list is `LanNet._update_shop_waiting`.
- [ ] **Rejoin after a lost connection** (not after death). Today a disconnect kills the player and it stays dead in later waves. Instead: keep the player idle or protected for a grace period, let the same machine reconnect into its old slot (match by name or a session token from the hello), send it the current run and drop it into the running wave or the between-wave phase. Quitting to the lobby and rejoining with the next wave already works.
- [ ] **Retry in a session.** Vanilla's retry screen (`retry_wave` option) restarts the wave from `start_wave_state`; a session skips it. The host could offer the retry and send the start-of-wave run to everyone.
- [ ] **Endless runs** as a host lobby setting (the shop's Endless button at wave 19 is hidden in a session: `is_endless_run` is run-wide, the merge only takes per-player data).
- [ ] **What LAN runs count for** (see [Known limitations](#known-limitations)): credit only the own character on each machine, or nothing.
- [ ] **Game modes:**
  - [ ] Teams: players split into teams in the lobby, each sharing materials, compared by a score at the end (kills, waves survived, damage).
  - [ ] Last man standing: the run goes on while players die off; the last one alive wins. Needs decisions on spectating, how waves scale as players drop out, and whether players can hurt each other.
