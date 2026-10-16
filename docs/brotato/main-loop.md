# main.gd: the wave scene (`main.tscn`, ~1800 lines)

## `_ready()` (~L121-285), in order
1. Connect `_entity_spawner.players_spawned` to `_on_EntitySpawner_players_spawned`.
2. `RunData.on_wave_start(_wave_timer)`. Set `_next_gold_player = Utils.randi() % player_count`.
3. Load the zone and wave data: `current_zone = ZoneService.get_zone_data(RunData.current_zone).duplicate()` and `current_wave_data = ZoneService.get_wave_data(zone, wave)`.
4. Map size (~L155-161): `map_size_coef` comes from the `map_size` item effect. Width and height are clamped to `MIN_MAP_SIZE = 12`. Then `ZoneService.set_current_zone(current_zone)`, `_tile_map.init`, `_tile_map_limits.init`.
5. Set `_wave_timer.wait_time = current_wave_data.wave_duration` and start the timer.
6. Connect `_wave_manager.group_spawn_timing_reached` to `_entity_spawner.on_group_spawn_timing_reached`. Then `_wave_manager.init(timer, zone, wave_data)`.
7. Camera init (~L202-205).
8. Loop over `%UIThingsToProcessPlayerContainer%s`.
9. `_entity_spawner.init(zone_min, zone_max, wave_data, timer)` spawns the players **synchronously** and emits `players_spawned`. Then `EntityService.reset_cache()`.
10. Call `player.land()` on wave 1, set up bullet-hell mode, then `_init_half_second_timers()` (one timer per player).

## `_on_EntitySpawner_players_spawned(players)` (~L1361-1430)
- Sets `_camera.targets = players`.
- Builds `PlayerUIElements` (`ui/hud/player_ui_elements.gd`) from the `%LifeContainerP{i+1}`, `%UILifeBarP{i+1}`, `%UIXPBarP{i+1}`, `%UIGoldP{i+1}`, and `%PlayerLifeBarContainerP{i+1}` nodes. Only P1–P4 exist.
- Sets starting HP.
- Connects `health_updated`, `healed`, `died`, `took_damage`, `wanted_to_spawn_gold`.

## Timers (`main.tscn`)
- `WaveTimer` (`ui/hud/wave_timer.gd`) has child timers `TickTimer` (ticks under 6 s) and `HalfWaveTimer`.
- `WaveManager` polls `wave_timer.time_left` itself.
- `EndWaveTimer.timeout` calls `_on_EndWaveTimer_timeout`.

## End of wave
1. `_on_WaveTimer_timeout` (~L1221) handles challenges and per-player end-of-wave stats, emits `end_of_the_wave`, calls `manage_harvesting()`, then `clean_up_room()`.
2. `clean_up_room()` (~L946):
   - `_set_run_states()` sets `_is_wave_failed`, `_is_run_lost`, `_is_run_won`.
   - Stops the timer, frees enemy projectiles, starts `EndWaveTimer` (0.5 s on a loss, 4 s otherwise).
   - Pulls gold into the bag, calls `_entity_spawner.clean_up_room()` and `_wave_manager.clean_up_room()`.
   - On a win: `player.won()`, then yields on `run_won_screen`. Shows the wave-cleared label.
3. `_on_EndWaveTimer_timeout()` (~L1117):
   - A failed wave shows `_retry_wave`.
   - Otherwise it calls `RunData.on_wave_end()`, then the upgrades UI. Coop uses `_coop_upgrades_ui.show_options(...)` and yields `options_processed`; solo uses `_upgrades_ui`. Both draw on `_upgrades_to_process` / `_consumables_to_process`.
   - Then `_change_scene(RunData.get_shop_scene_path())`, or the end-run scene if the run is over.
- Game over: `_on_player_died` (~L466) returns while any player is alive. Once all are dead it calls `clean_up_room()` and `ProgressData.reset_and_save_new_run_state()`.
- Killing the final boss sets `_wave_timer.wait_time = 0.1` (`_on_enemy_died` ~L510).

## Loot, gold, pools
- `_on_enemy_died` (~L503) calls `spawn_loot` (~L624). Other spawners: `spawn_consumables` (~L651), `spawn_gold` (~L735), `get_gold_value` (~L786, applies the coop materials factor).
- `on_gold_picked_up` (~L827): materials are split round-robin across players via `_next_gold_player`. It uses local `player_gold/player_xp = [0,0,0,0]` (~L879).
- `on_consumable_picked_up` (~L694).
- Pools: `get_node_from_pool`, `add_node_to_pool` (~L1716-1767). Adders: `add_player_projectile`, `add_enemy_projectile`, `add_entity`, `add_explosion`.

## Pause
- `_pause_menu = $UI/PauseMenu` (`ui/menus/ingame/pause_menu.gd`).
  - `pause(player_index)` sets `get_tree().paused = true` and shows the menu. `unpause()` undoes it.
  - `enabled` turns the menu on or off.
  - `on_game_lost_focus()` pauses if `ProgressData.settings.pause_on_focus_lost` is set.
- PauseMenu, Camera and StatsManager have `pause_mode = 2`, so they keep processing while paused.
- The shop pauses through `base_shop.gd` `_input`. Its `on_paused` saves the run state.
- Other writers of `get_tree().paused`: bug_reporter, streamplay, run_data (~L1878), menu_confirm, menu_restart.
