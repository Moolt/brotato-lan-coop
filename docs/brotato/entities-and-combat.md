# Entities, combat, pickups, RNG

## Hierarchy
`Entity` (`entities/entity.gd`, **RigidBody2D**) → `Unit` (`entities/units/unit/unit.gd`) → `Player` (`entities/units/player/player.gd`) / `Enemy` (`entities/units/enemies/enemy.gd`) → `Boss`. `Neutral`, `Pet`, and `Structure` are also subclasses.

### Entity
- Signals: `died(entity, die_args)`, `stats_boosted`.
- `init(zone_min, zone_max, players_ref, spawner)`, `respawn()` (when reused from the pool), `die(args)`.
- Freeing: `death_animation_finished` → `free_entity` → `main.add_node_to_pool`.
- `class DieArgs`: `killed_by_player_index`, `cleaning_up`, `enemy_killed_by_player`, and more.

### Unit
- `players_ref`, `init`, `init_current_stats`.
- `_physics_process` calls `_current_movement_behavior.get_movement()`. `_integrate_forces` clamps to the zone rect.
- `take_damage(value, args)`, `die`, `_on_Hurtbox_area_entered`, `apply_burning`.
- Signal `took_damage(unit, value, knockback_dir, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)`.
- Stats: `current_stats.health`, `max_stats.health`.
- Some stats are randomised at init: speed (`unit.gd` ~L77/88) and enemy `_idle_playback_speed`.

### Player
- `player_index`.
- `player.tscn` sets `mode = 3` (`MODE_KINEMATIC`): `Unit._physics_process` moves it with `test_motion`, and `_integrate_forces` copies `global_position` into the body state. Setting `global_position` directly therefore moves a player (the LAN mod does this for remote players).
- `_physics_process` only runs HP regeneration (`_health_regen_timer` → `on_health_regen`). Movement and animation come from `Unit._physics_process` (`get_movement()` → `update_animation`, `get_next_velocity()`); `get_move_speed()` is `current_stats.speed + bonus_speed + decaying_bonus_speed`.
- `_movement_behavior` is a `PlayerMovementBehavior` (see coop-and-input.md).
- `gamepad_attack_vector` is used for manual aim.
- Pickups: `_on_ItemPickupArea_area_entered` calls `area.pickup(player_index)`.
- `take_damage`, `die`, `won` (emits `run_won_screen`), `heal`.

### Enemy
- `const player_index = -1`.
- With more than one player (or any pets), `update_target()` runs every 0.25 s and picks the nearest non-dead targetable player or pet as `current_target`.
- Movement behaviors (e.g. `follow_target_movement_behavior.gd`) read `current_target.global_position`.
- Attack behaviors are in `entities/units/enemies/attack_behaviors/`.
- Pet and structure targeting: `entities/units/target_behavior/*`.

## Weapons and projectiles
**Weapons** (`weapons/weapon.gd`): `_physics_process` → `should_shoot()` → `deferred_shoot` → `shoot()` → `_shooting_behavior.shoot(...)`. The ranged and melee behaviors are in `weapons/shooting_behaviors/`. Weapon stats come from `WeaponService.init_*_stats`.

**Player projectiles**
- `WeaponService.spawn_projectile(pos, weapon_stats, direction, from, args)` (~L366) takes a projectile from the pool in `main._player_projectiles`.
- It then calls `projectile.shoot_ex(from, pos, velocity, rotation, stats, tracking_key, effects, hitbox_args, knockback)`.
- Classes: `projectiles/player_projectile.gd`, with base `projectiles/projectile.gd` (Node2D).
- Explosions: `WeaponService.explode` and `main.add_explosion`.

**Enemy projectiles**
- `ShootingAttackBehavior.spawn_projectile(rot, pos, spd)` (~L191) adds to `main._enemy_projectiles`. Spread and speed use `rand_range`.
- `EnemyProjectile` is in `projectiles/bullet_enemy/enemy_projectile.gd`.

**Enemy damage and HP factors:** `singletons/entity_service.gd`.

## Pickups
- `Item` (`items/global/item.gd`, Area2D): signal `picked_up(item, player_index)`, methods `drop(pos, rot, push_back_dest)`, `attracted_by`, `pickup(player_index)`.
- `Gold` and `Consumable` extend `Item`. They are spawned by `main.spawn_gold` / `spawn_consumables`.
- Pickup handlers: `main.on_gold_picked_up` / `on_consumable_picked_up`.

## RNG (not centralized, so no lockstep determinism)
- `Utils._rng` (`RandomNumberGenerator`) is randomized in `_ready`. `Utils.set_rng_seed` exists but is unused. Other helpers: `Utils.randi_range`, `Utils.randi()`.
- `Utils.get_chance_success` uses the global `randf()`. `Utils.get_rand_element` uses the global RNG.
- Rough call counts: about 90 `rand_range`, 70 `get_rand_element`, 35 `get_chance_success`, plus scattered `randf`/`randi`/`shuffle`.
- Physics bodies are RigidBody2D, which are not deterministic across machines either.
