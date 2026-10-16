# Waves, spawning, zones, camera

## Data (`zones/`)
- `ZoneData` (`zones/zone_data.gd`): `width = 32` and `height = 24`, in tiles. All three zones use 32×24.
- `Utils.TILE_SIZE = 64` and `EDGE_MAP_DIST = 64`, so the arena is 2048×1536 px.
- `WaveData` (`wave_data.gd`): `wave_duration`, `max_enemies = 100`, `groups_data`, `conditional_groups_data`.
- `WaveGroupData`: `spawn_timing`, `repeating`, `repeating_interval`, `area`, `spawn_edge_of_map`, `wave_units_data`, `is_boss`, `is_loot`, `is_neutral`, and more.
- `WaveUnitData`: `type`, `unit_scene`, `min_number`, `max_number`, `spawn_chance`, `additional_min_distance_from_player`.
- Per-wave files: `zones/zone_N/001..020/*.tres`, plus `000_all`, `000_hordes`, `000_loot`.

## ZoneService (`singletons/zone_service.gd`)
- `get_zone_data(id)`.
- `get_wave_data(zone, wave)` (~L33-73) also handles endless-mode scaling.
- `set_current_zone(zone)` (~L24): sets `current_zone_max_position = (width*64, height*64)` and `current_zone_rect`. `current_zone_min_position` is always (0,0).
- Position helpers: `get_rand_pos`, `get_rand_pos_in_area`, `get_map_center`, `get_anchor_position`. `current_zone_max_camera_rect` is set from main.

**Arena size.** It is computed only in `main.gd` ~L155-161, from the `map_size` item effect. Player count does not affect it in vanilla.
- To enlarge it, scale `zone.width/height` before `ZoneService.set_current_zone`.
- Main passes the same zone object to `_tile_map.init` (`global/my_tile_map.gd`), `_tile_map_limits.init` (`global/my_tile_map_limits.gd`, the walls), and `_wave_manager.init`.
- `Unit._integrate_forces` clamps entities to `ZoneService.get_current_zone_rect()`.

## WaveManager (`zones/wave_manager.gd`)
- `init` (~L24-174) collects the groups: wave groups, all-wave groups, loot aliens, bosses/elites, item-driven extras, DLC.
- `_physics_process` checks every second of `wave_timer.time_left`. When a group's time comes, it rolls `get_chance_success(group.spawn_chance)` and emits `group_spawn_timing_reached(group_data)`. Repeating groups go through `emit_and_update_repeat_group`.
- Endless mode uses `add_groups`.

## EntitySpawner (`global/entity_spawner.gd`)
**Players.** `init(zone_min, zone_max, wave_data, timer)` (~L75-115) spawns players at `(max.x/2 - 100 + (i%2)*100, max.y/2 + ((i/2)%2)*100)`. Only 4 distinct spots exist. It sets the movement device in coop, then emits `players_spawned`.

**Groups.** `on_group_spawn_timing_reached(group)` (~L149-199) computes spawn counts:
```gdscript
var max_enemies = int(wave.max_enemies + (n-1) * wave.max_enemies/8.0)   # cap; excess enemies get killed
var coop_factor = (n-1) * CoopService.additional_enemies_per_coop_player
number = randi_range(min,max) * DebugService.nb_enemies_mult
if ENEMY and not loot: number += number*coop_factor; number = max(1, number + number*enemy_modifier)
```

**Spawn pipeline**
1. Entries go into `queue_to_spawn`, `queue_to_spawn_bosses`, or `queue_to_spawn_trees`.
2. `_physics_process` pops 1–2 entries every 3 frames and calls `spawn_entity_birth`.
3. That creates an `EntityBirth` (`entities/birth/entity_birth.gd`), which calls `on_entity_birth_timeout`, then `spawn_entity(scene, args)` (~L346).

**`spawn_entity`** sets `player_index` on players, pets and structures, calls `entity.init(zone_min, zone_max, players, self)`, then `apply_items_effects()`. Spawned nodes are reused from the pool.

**Registries and other functions**
- Arrays: `enemies`, `bosses`, `neutrals`, `structures`, `pets`, `charmed_enemies`. `get_all_enemies()` returns them.
- `clean_up_room()` kills everything with `cleaning_up = true`.
- Position helpers: `get_group_pos`, `get_group_pos_away_from_players`, `get_spawn_pos_in_area`.

## Enemy stat scaling (`singletons/entity_service.gd`)
- `get_final_enemy_health`: factor `1 + (n-1)*additional_enemy_health_per_coop_player`.
- `get_final_enemy_damage`: factor `1 + (n-1)*additional_enemy_damage_per_coop_player`.
- Both factors are cached in `factor_cache`, which `reset_cache()` clears.
- `DebugService.nb_enemies_mult` is a global multiplier on spawn counts.

## Camera (`global/my_camera.gd`, class MyCamera)
- `main.gd` sets `max_bounds = zone_rect.grow_individual(96, 192, 96, 96)`, calls `_camera.init(max_bounds, 96)`, then sets `targets = players`.
- **Follow:** the camera tracks the average position of the alive targets, lerped (`move_speed_factor 0.98`). With one target left alive it snaps over `snap_duration_secs` (5).
- **Zoom:** `_adjust_zoom` fits all targets. It zooms in when the targets cover less than 40% of the screen; otherwise it keeps `zoomed_out_margin = 500`. Zoom is clamped to `[1.0, _max_zoom]`, where `_max_zoom` comes from the bounds.
- **Lock setting:** `ProgressData.settings.lock_coop_camera` pins the camera to the centre at max zoom (`main.on_lock_coop_camera_changed`).
