# Game modes: ideas, effort, architecture

Modes beyond the standard co-op run (Step 9). Decisions and progress go into the checklists below; once a mode exists, its as-built detail moves to [lan-coop-mod.md](lan-coop-mod.md#game-modes). Assessment from 2026-10-23; the mode layer and modes 1–7 of [More mode ideas](#more-mode-ideas-roughly-cheapest-first) were built on 2026-10-24 (not playtested yet).

## What the current design gives us
- **The host is the single authority.** It simulates every entity, fires every player's weapons (client weapons never fire) and sends damage to players as events. Rules like "who may hurt whom" or "who gets the kill" live in one place, so there is no client disagreement or cheating to handle in any mode.
- **Vanilla building blocks for competitive play:**
  - Gold is per player (`RunData.add_gold(value, player_index)`); crate sharing is a switch (`ProgressData.settings.share_coop_loot`, `main.gd` ~714).
  - Charmed enemies fight for a player: `charmed_by` in the spawn event, `Enemy.get_charmed_by_player_index()` / `set_charmed()`, `closest_enemy_target_behavior.gd`. The core of any "units fight for a player or team" mode.
  - Structures and turrets are already spawned, synced and owned by a player.
- **What gets expensive** is breaking vanilla's basic assumptions: weapons auto-aim only at the enemy collision layer, enemies chase players, the arena is an empty rectangle, a run is fixed timed waves with a shop between them.

## Architecture: modes as isolated objects
Built this way (2026-10-24); the hook list as it ended up is in [lan-coop-mod.md](lan-coop-mod.md#game-modes). Differences to the plan below: the mode's own traffic is a separate RPC pair (`_rpc_mode_state`, `_rpc_mode_message`) on `LanNet`, not an event code in `LanWaveSync`, since modes also talk between waves (draft shop); scores, banner and results are shared components the modes fill (`modes/scoreboard.gd`, `modes/results_panel.gd`).
Rule: **the code asks the mode questions; it never checks which mode is active.**
- `modes/lan_mode.gd`: base class whose defaults are today's co-op behaviour. Example hooks: `uses_wave_spawner()`, `can_damage(attacker, target) -> bool`, `on_kill(enemy, killer_index)`, `loot_owner(pickup, player_index)`, `wants_shop()`, `is_run_over()`, `extra_hud(main)`, `on_wave_start()` / `on_wave_end()`.
- One subclass per mode in its own folder (`modes/pvp/`, `modes/castle_fight/`, …) with all its scenes, HUD and logic.
- `lobby_settings.mode` selects it; host and every client build the same mode object at run start.
- Extensions call `LanNet.mode.<hook>(…)` at fixed hook points. **Never `if mode == "pvp"`** in an extension, `wave_sync.gd` or `net_manager.gd`. Most extensions already go through `game/lan_game.gd`, the natural home for these calls.
- Mode-specific network traffic uses one generic event code (`mode event, payload`) that `LanWaveSync` forwards to the mode untouched. The protocol table in lan-coop-mod.md stays stable; each mode documents its own payloads.
- Add hooks when a real mode needs them, not up front. The first mode defines the interface, the second or third shows whether it was right.
- Modes must stay host-authoritative. A mode that needs client authority doesn't fit the sync model.

## Requested modes
| Mode | Effort | Notes |
|---|---|---|
| Own loot + kill scoreboard | Small | Gold is already per player; turn sharing off and credit the killer. Needs killer attribution (host), a score field in the snapshot or a kill event, a scoreboard HUD. Good first mode to prove the mode layer. |
| PvP, no enemies | Medium | Weapon range areas and player projectiles must see and hit other players (collision layers, targeting in `closest_enemy_target_behavior`); wave spawner off. Clients already get player damage from the host, so the network side is mostly there. The real problem is balance: auto-aim against moving players, late-game builds one-shotting each other. Needs its own scaling and playtesting. |
| Castle Fight (WC3) | Medium–large | Fits better than expected: the shop phase becomes the build phase. Buy "barracks" structures that keep spawning charmed units marching to the other team's side. New: team-owned charm (charm belongs to one player today), units walking to a goal instead of the nearest player, a castle with HP, a win condition. No direct player-vs-player, so no PvP balance problem. |
| MOBA (2 teams, 3 lanes) | Large | Needs a real map (lanes, walls, larger camera area), towers, respawn, continuous mob spawns instead of waves, buying during play, a camera for 12 players. Reuses engine, netcode and content, but nearly every system bends. A separate project, at best after Castle Fight proves teams and charm. |

## More mode ideas (roughly cheapest first)
1. **Last Potato Standing:** endless waves, shrinking arena, rising enemy count; last one alive wins. Competitive without any PvP code. *Built:* the arena shrinks as a storm inside each wave (decided 2026-10-24: a safe circle, HP loss outside), not as smaller walls; the enemy count keeps scaling for all players of the run, so it rises for the survivors.
2. **Send-back (Tetris attack):** your kills spawn elites next to your opponents. Uses the existing spawner; free-for-all or two teams. *Built:* free-for-all on the elimination rules of 1; every 5 kills send one enemy of the killed kind with 1.5× HP (real elites would be too strong at that rate).
3. **Draft shop:** shared, limited shop stock; whoever buys first takes it from everyone. Changes only the shop phase. *Built:* a pool per wave, the same first shop for everyone, personal rerolls through the pool (decided 2026-10-24), purchases claimed at the host, no locking.
4. **King of the Hill:** standing in a moving zone earns materials, enemies keep coming. A zone node and a gold tick. *Built:* split between everyone inside; most hill materials wins.
5. **Boss player:** one player is the boss with huge stats and charmed adds, everyone else teams up against them. Needs PvP damage. *Built:* a random boss each wave (decided 2026-10-24), the wave's enemies fight for the boss (they ignore it rather than being charmed), PvP through `can_target` / `can_hit` filters on the player layers.
6. **Gold Rush:** loot not shared; dying drops part of your materials for others to grab. Builds on the scoreboard mode. *Built*, with kills counted for every mode by the base class.
7. **Team Race:** two teams play identical waves (same seed) in one session; best score or highest wave wins. *Built:* a split arena (decided 2026-10-24) with twinned spawns rather than a shared seed (no lockstep RNG); both halves together keep the normal enemy cap, so the load stays as in co-op.

## Earlier mode ideas (from the plan)
- **Teams:** players split into teams in the lobby, each sharing materials, compared by a score at the end (kills, waves survived, damage).
- **Last man standing:** the run goes on while players die off; the last one alive wins. Needs decisions on spectating, how waves scale as players drop out, and whether players can hurt each other. Overlaps with Last Potato Standing above.

## Suggested order
- [x] Mode layer (`lan_mode.gd`, `lobby_settings.mode`, lobby picker, mode RPCs), kill counting and scoreboard (2026-10-24). A plain "own loot + kill scoreboard" mode wasn't added: Gold Rush is that plus death drops.
- [x] **Last Potato Standing** and **Send-back** (2026-10-24)
- [x] **PvP damage** (Boss player, 2026-10-24): only between the sides a mode allows; open for a free-for-all PvP mode: its own balance (damage factor, HP)
- [x] **Teams** (Team Race, 2026-10-24): lobby entry `team`, "Switch team" button
- [x] Draft shop, King of the Hill, Gold Rush (2026-10-24)
- [ ] Playtest every mode with real players and tune the constants at the top of each mode file
- [ ] **PvP, no enemies** (requested mode): the Boss player's PvP filters for every player against every other
- [ ] **Castle Fight**
- [ ] MOBA: separate project, decide after Castle Fight
