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
- **Each machine moves its own player.** Rendering the own player from 20 Hz snapshots would add 60–120 ms of input delay, and removing that later would need client-side prediction. A client faking its position doesn't matter in LAN co-op. Consequences: the host sees a client's position 1–5 ms late, a client sees enemies 50–100 ms behind (interpolation), so a last-moment dodge can occasionally count differently. Speed, HP, death, gold and XP still come from the host.
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
- [ ] **Snapshot size.** Above about 190 entities a snapshot exceeds one UDP packet and ENet fragments it (8 bytes per entity, 33 per player). Measure whether snapshots drop at high counts; if so, split them.
- [ ] **Spawn rate.** `EntitySpawner` releases queued enemies at a fixed 20–40/s whatever the player count. Measure 12 slots at a late wave (15–20) with the normal multiplier: queue length and enemies alive. If the queue limits the count, release `ceil(n / 4)` per tick before raising enemy HP; watch host CPU and snapshot size.
- [ ] **Load check at scale.** FPS and bandwidth on host and client with about 300 enemies and 12 slots (so far: 160 enemies, 300+ FPS uncapped; 166 entities, 1.45 KB snapshots).

### Tests
What the driver and manual tests haven't covered yet ([testing.md](testing.md)).
- [x] Full runs on separate machines (two players).
- [ ] More than two real players (the driver's fake players are never sent anything).
- [ ] Pets (same data-ref path as structures, which are tested).
- [ ] The 15 s client load timeout (clients on one PC load within 0.1 s).
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
