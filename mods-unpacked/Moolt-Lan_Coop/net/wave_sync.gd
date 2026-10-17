extends Node

# In-wave sync, a child of main during a LAN session (added by the main.gd extension).
# Each machine moves its own player; the host decides everything else (see the plan, Step 6).
# RPCs go through LanNet, which has the same path on every peer and forwards them here.
#
# Host:
#   - Remote players are driven by their clients: every physics frame a client sends
#     {pos, move, aim, manual_aim}. The host places the player there (players are kinematic
#     bodies) and feeds move to its animation and moving/not-moving item effects.
#   - Every entity the spawner creates during the wave (enemies, bosses, trees, structures,
#     pets) gets a net id. Spawns, births (the spawn markers) and deaths go out as reliable
#     events, collected per physics frame.
#   - Weapon attacks (player, weapon index, rotation, distance, melee attack type) and
#     projectiles (spawn: scene, position, velocity, rotation, speed and range; stop) are events
#     too. Projectiles inside a group (GroupOfBullet, bullet hell) aren't synced.
#   - Every SNAPSHOT_INTERVAL physics frames (20 Hz) it sends a snapshot to all clients:
#     wave time left; per player position, movement, speed, HP and death; per entity (trees
#     excluded, they don't move) position and HP ratio (0-255).
# Client:
#   - The wave manager and the entity spawner don't run. Entities come from the host's events,
#     spawned through the normal spawner (and its pools), then made inert: no physics, kinematic,
#     no areas. They die on the host's death event and slide with its knockback.
#   - The own player moves locally at the speed the host reports, takes no damage and doesn't
#     regenerate; HP and death come from the host.
#   - Weapons show the host's attacks: melee weapons swing (the real swing, which hits nothing
#     because client entities are inert), ranged weapons recoil and play their sound.
#     Projectiles are copies with their areas off; they fly on their own and stop on the host's
#     stop event (or at their range).
#   - Other players and entities are puppets, interpolated between snapshots
#     INTERP_DELAY_MS in the past.
#   - The wave timer follows the host's. The wave ends when the host says so.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const SNAPSHOT_INTERVAL: = 3
const INTERP_DELAY_MS: = 100
const MAX_BUFFERED_SNAPSHOTS: = 20
const TIMER_RESYNC_THRESHOLD: = 0.5
const MOVE_SCALE: = 127.0
const HP_SCALE: = 255.0
const FLAG_DEAD: = 1
const SNAPSHOT_HEADER_SIZE: = 13
const SNAPSHOT_PLAYER_SIZE: = 23
const SNAPSHOT_ENTITY_SIZE: = 7
const MAX_NET_ID: = 65535

const EVENT_SPAWN: = 0
const EVENT_DIE: = 1
const EVENT_BIRTH: = 2
const EVENT_WEAPON: = 3
const EVENT_PROJECTILE: = 4
const EVENT_PROJECTILE_STOP: = 5
const RANGED_ATTACK: = - 1

var is_host: = false

var _net: Node = null
var _main: Node = null
var _local_index: = - 1
var _frame: = 0

# Net id -> entity, on both sides. Ids are u16 and wrap; a wave never gets near 65535 alive.
var _entities: = {}

# Host: latest state per remote player_index: {pos, move, aim, manual_aim}.
var _remote_states: = {}
var _snapshot_seq: = 0
var _next_net_id: = 0
var _events: = []
# Projectiles shot since the last flush; their spawn events are built at flush time, when
# position and velocity are set (enemy projectiles shoot once in _ready, before they're placed).
var _pending_projectiles: = []
var _next_projectile_id: = 0

# Projectile net id -> projectile, on both sides (host: shot and not yet returned to the pool).
var _projectiles: = {}
var _scene_cache: = {}

# Client: received snapshots, oldest first:
# {time (host msec), players: [{pos, move}], entities: {net id: pos}}.
var _snapshots: = []
var _last_seq: = - 1
# Local msec minus host msec, tracked from below (the smallest delay seen, slowly forgotten).
var _clock_offset = null
var _spawn_args = null


func _init() -> void :
	name = "LanWaveSync"
	pause_mode = PAUSE_MODE_PROCESS


func _ready() -> void :
	_net = LanGame.get_lan_net()
	_main = get_parent()
	is_host = _net.is_host
	_local_index = _net.local_player_index
	_net.wave_sync = self

	if is_host:
		for player in _main._players:
			if player.player_index != _local_index:
				player.lan_net_driven = true
	else:
		_spawn_args = EntitySpawner.SpawnEntityArgs.new(Vector2.ZERO, EntityType.ENEMY)
		_main._wave_manager.set_physics_process(false)
		_main._entity_spawner.set_physics_process(false)
		_main._entity_spawner._structure_timer.stop()
		# Bullet hell events shoot from here; enemy projectiles come from the host later (6c).
		for child in _main._enemy_projectiles.get_children():
			child.queue_free()
		for player in _main._players:
			player.disable_hurtbox()
			player._item_pickup_area.set_deferred("monitoring", false)
			player._item_attract_area.set_deferred("monitoring", false)
			player.lan_no_regen = true
			if player.player_index != _local_index:
				player.set_physics_process(false)


func _exit_tree() -> void :
	if _net != null and _net.wave_sync == self:
		_net.wave_sync = null


func _physics_process(_delta: float) -> void :
	_frame += 1
	if is_host:
		_apply_remote_states()
		_flush_pending_projectiles()
		if not _events.empty():
			_net.send_events(_events)
			_events = []
		if _frame % SNAPSHOT_INTERVAL == 0:
			_net.send_snapshot(_build_snapshot())
	else:
		_send_own_state()
		_update_puppets()



# Host

func on_player_state(player_index: int, pos: Vector2, move: Vector2, aim: Vector2, manual_aim: bool) -> void :
	if player_index == _local_index or player_index < 0 or player_index >= _main._players.size():
		return
	_remote_states[player_index] = {"pos": pos, "move": move.clamped(1.0), "aim": aim, "manual_aim": manual_aim}


# Manual aim of a remote player as its client reported it, null for others.
func get_remote_manual_aim(player_index: int):
	if not is_host or not _remote_states.has(player_index):
		return null
	return _remote_states[player_index].manual_aim


# Called by the entity_spawner.gd extension for every non-player entity it spawns.
func on_entity_spawned(entity: Node, scene: PackedScene, type: int, pos: Vector2, player_index: int, data: Resource, charmed_by: int) -> void :
	_next_net_id = _next_net_id % MAX_NET_ID + 1
	var net_id: = _next_net_id
	entity.set_meta("lan_net_id", net_id)
	_entities[net_id] = entity
	if not entity.is_connected("died", self, "_on_host_entity_died"):
		var _e = entity.connect("died", self, "_on_host_entity_died")
	_events.append([EVENT_SPAWN, net_id, type, scene.resource_path, pos, player_index, _get_data_ref(data, player_index), charmed_by])


# Called by the entity_spawner.gd extension when a spawn marker appears.
func on_birth(type: int, pos: Vector2, charmed_by: int) -> void :
	_events.append([EVENT_BIRTH, type, pos, charmed_by])


func on_weapon_shot(weapon: Node, distance: float) -> void :
	var player = weapon._parent
	if not is_instance_valid(player) or not player is Player:
		return
	var weapon_index: int = player.current_weapons.find(weapon)
	if weapon_index < 0:
		return
	var attack_type: int = weapon.next_attack_type if weapon is MeleeWeapon else RANGED_ATTACK
	_events.append([EVENT_WEAPON, player.player_index, weapon_index, weapon.rotation, distance, attack_type])


# Called by the projectile.gd extension. Only projectiles that sit directly in main's
# projectile containers are synced (bullets inside a GroupOfBullet move with their group).
func on_projectile_shot(projectile: Node) -> void :
	if projectile.lan_net_id != 0 or projectile is GroupOfBullet:
		return
	var parent: = projectile.get_parent()
	if parent != _main._player_projectiles and parent != _main._enemy_projectiles:
		return
	_next_projectile_id = _next_projectile_id % MAX_NET_ID + 1
	projectile.lan_net_id = _next_projectile_id
	_projectiles[_next_projectile_id] = projectile
	_pending_projectiles.append(projectile)


func on_projectile_stopped(projectile: Node) -> void :
	if not is_host:
		return
	if _pending_projectiles.has(projectile):
		# Never sent: forget it.
		_pending_projectiles.erase(projectile)
		var _erased = _projectiles.erase(projectile.lan_net_id)
		projectile.lan_net_id = 0
		return
	_events.append([EVENT_PROJECTILE_STOP, projectile.lan_net_id, projectile.global_position])


func on_projectile_returned(projectile: Node) -> void :
	var net_id: int = projectile.lan_net_id
	if _projectiles.get(net_id) != projectile:
		return
	var _erased = _projectiles.erase(net_id)
	if not is_host:
		return
	if _pending_projectiles.has(projectile):
		_pending_projectiles.erase(projectile)
	elif projectile._hitbox.active:
		# Pooled without stop() (stop() clears active): tell the clients.
		_events.append([EVENT_PROJECTILE_STOP, net_id, projectile.global_position])


func _flush_pending_projectiles() -> void :
	for projectile in _pending_projectiles:
		if not is_instance_valid(projectile) or projectile.lan_net_id == 0:
			continue
		var speed: float = projectile.velocity.length()
		var max_range: = 0
		if projectile is PlayerProjectile and projectile._weapon_stats != null:
			speed = projectile._weapon_stats.projectile_speed
			max_range = projectile._max_range
		var is_enemy: bool = projectile.get_parent() == _main._enemy_projectiles
		_events.append([EVENT_PROJECTILE, projectile.lan_net_id, projectile.filename, projectile.global_position, projectile.velocity, projectile.rotation, speed, max_range, is_enemy])
	_pending_projectiles.clear()


func _on_host_entity_died(entity: Node, args: Entity.DieArgs) -> void :
	var net_id = entity.get_meta("lan_net_id") if entity.has_meta("lan_net_id") else null
	if net_id == null or _entities.get(net_id) != entity:
		return
	var _erased = _entities.erase(net_id)
	# The clients' own clean_up_room kills everything at the end of the wave.
	if not args.cleaning_up:
		_events.append([EVENT_DIE, net_id, args.knockback_vector])


# Structures and pets get their data (StructureEffect, PetEffect) from the player's effects,
# which every peer holds in the same order. Other data is sent as a resource path.
func _get_data_ref(data: Resource, player_index: int):
	if data == null:
		return null
	if player_index >= 0 and player_index < RunData.get_player_count():
		var effects: Dictionary = RunData.get_player_effects(player_index)
		for key in [Keys.structures_hash, Keys.stat_pets_hash]:
			if effects.has(key) and typeof(effects[key]) == TYPE_ARRAY:
				var index: int = effects[key].find(data)
				if index >= 0:
					return [key, index]
	if not data.resource_path.empty() and data.resource_path.find("::") < 0:
		return data.resource_path
	return null


func _apply_remote_states() -> void :
	var zone_rect: Rect2 = ZoneService.get_current_zone_rect()
	for player_index in _remote_states:
		var player = _main._players[player_index]
		if not is_instance_valid(player) or player.dead:
			continue
		var state: Dictionary = _remote_states[player_index]
		player.global_position = Vector2(
			clamp(state.pos.x, zone_rect.position.x, zone_rect.end.x),
			clamp(state.pos.y, zone_rect.position.y, zone_rect.end.y)
		)
		player.lan_move = state.move
		if state.aim != Vector2.ZERO:
			player.gamepad_attack_vector = state.aim.normalized()


func _build_snapshot() -> PoolByteArray:
	_snapshot_seq += 1
	var buffer: = StreamPeerBuffer.new()
	buffer.put_u32(_snapshot_seq)
	buffer.put_u32(OS.get_ticks_msec())
	buffer.put_float(_main._wave_timer.time_left)
	buffer.put_u8(_main._players.size())
	for player in _main._players:
		buffer.put_float(player.global_position.x)
		buffer.put_float(player.global_position.y)
		var move: Vector2 = player._current_movement.clamped(1.0)
		buffer.put_8(int(round(move.x * MOVE_SCALE)))
		buffer.put_8(int(round(move.y * MOVE_SCALE)))
		buffer.put_float(player.get_move_speed())
		buffer.put_32(player.current_stats.health)
		buffer.put_32(player.max_stats.health)
		buffer.put_u8(FLAG_DEAD if player.dead else 0)

	var moving: = []
	for net_id in _entities:
		var entity = _entities[net_id]
		if is_instance_valid(entity) and not entity.dead and not entity is Neutral:
			moving.append(net_id)
	buffer.put_u16(moving.size())
	for net_id in moving:
		var entity = _entities[net_id]
		buffer.put_u16(net_id)
		buffer.put_16(int(clamp(entity.global_position.x, - 32768, 32767)))
		buffer.put_16(int(clamp(entity.global_position.y, - 32768, 32767)))
		var hp_ratio: = 1.0
		if entity is Unit and entity.max_stats.health > 0:
			hp_ratio = clamp(float(entity.current_stats.health) / entity.max_stats.health, 0.0, 1.0)
		buffer.put_u8(int(round(hp_ratio * HP_SCALE)))
	return buffer.data_array



# Client

func on_snapshot(data: PoolByteArray) -> void :
	if data.size() < SNAPSHOT_HEADER_SIZE:
		return
	var buffer: = StreamPeerBuffer.new()
	buffer.data_array = data
	var seq: = buffer.get_u32()
	if seq <= _last_seq:
		return
	var host_time: = buffer.get_u32()
	var time_left: = buffer.get_float()
	var count: = buffer.get_u8()
	var entities_offset: = SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_PLAYER_SIZE
	if count != _main._players.size() or data.size() < entities_offset + 2:
		return
	buffer.seek(entities_offset)
	var entity_count: = buffer.get_u16()
	if data.size() != entities_offset + 2 + entity_count * SNAPSHOT_ENTITY_SIZE:
		return
	buffer.seek(SNAPSHOT_HEADER_SIZE)
	_last_seq = seq

	var offset: = OS.get_ticks_msec() - host_time
	if _clock_offset == null or offset < _clock_offset:
		_clock_offset = offset
	else:
		_clock_offset += 1

	var positions: = []
	for player_index in count:
		var pos: = Vector2(buffer.get_float(), buffer.get_float())
		var move: = Vector2(buffer.get_8(), buffer.get_8()) / MOVE_SCALE
		var speed: = buffer.get_float()
		var health: = buffer.get_32()
		var max_health: = buffer.get_32()
		var flags: = buffer.get_u8()
		positions.append({"pos": pos, "move": move})
		_apply_player_state(_main._players[player_index], speed, health, max_health, (flags & FLAG_DEAD) != 0)

	var entity_positions: = {}
	var _count = buffer.get_u16()
	for _i in entity_count:
		var net_id: = buffer.get_u16()
		entity_positions[net_id] = Vector2(buffer.get_16(), buffer.get_16())
		_apply_entity_health(_entities.get(net_id), buffer.get_u8())

	_snapshots.append({"time": host_time, "players": positions, "entities": entity_positions})
	if _snapshots.size() > MAX_BUFFERED_SNAPSHOTS:
		_snapshots.pop_front()

	if not _main._cleaning_up and abs(_main._wave_timer.time_left - time_left) > TIMER_RESYNC_THRESHOLD and time_left > 0.0:
		_main._wave_timer.start(time_left)


func _apply_player_state(player, speed: float, health: int, max_health: int, dead: bool) -> void :
	if not is_instance_valid(player) or player.dead:
		return
	player.lan_move_speed = speed
	if player.current_stats.health != health or player.max_stats.health != max_health:
		player.max_stats.health = max_health
		player.current_stats.health = health
		player.emit_signal("health_updated", player, health, max_health)
	if dead:
		player.die()


# Boss and other over-head life bars follow health_updated. The client's max HP can differ from
# the host's (elite stats, buffs), so the client copy uses the 0-255 ratio as its HP.
func _apply_entity_health(entity, health: int) -> void :
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity is Unit:
		return
	if health != entity.current_stats.health or entity.max_stats.health != HP_SCALE:
		entity.max_stats.health = int(HP_SCALE)
		entity.current_stats.health = health
		entity.emit_signal("health_updated", entity, health, entity.max_stats.health)


func on_events(events: Array) -> void :
	for event in events:
		if typeof(event) != TYPE_ARRAY or event.empty() or typeof(event[0]) != TYPE_INT:
			continue
		if event[0] == EVENT_SPAWN and event.size() == 8:
			_client_spawn(event)
		elif event[0] == EVENT_DIE and event.size() == 3:
			_client_die(event)
		elif event[0] == EVENT_BIRTH and event.size() == 4:
			_client_birth(event)
		elif event[0] == EVENT_WEAPON and event.size() == 6:
			_client_weapon_shot(event)
		elif event[0] == EVENT_PROJECTILE and event.size() == 9:
			_client_projectile(event)
		elif event[0] == EVENT_PROJECTILE_STOP and event.size() == 3:
			_client_projectile_stop(event)


func _client_spawn(event: Array) -> void :
	# [EVENT_SPAWN, net_id, type, scene path, pos, player_index, data ref, charmed_by]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_STRING:
		return
	if typeof(event[4]) != TYPE_VECTOR2 or typeof(event[5]) != TYPE_INT or typeof(event[7]) != TYPE_INT:
		return
	if _main._cleaning_up or not ResourceLoader.exists(event[3]):
		return
	var scene = load(event[3])
	if not scene is PackedScene:
		return
	var type: int = event[2]
	var player_index: int = event[5]
	var data = _resolve_data_ref(event[6], player_index)
	if data == null and (type == EntityType.STRUCTURE or type == EntityType.PET):
		return

	_spawn_args._init(event[4], type)
	_spawn_args.player_index = player_index
	var entity = _main._entity_spawner.spawn_entity(scene, _spawn_args, data, null, event[7])
	if entity == null:
		return
	_make_inert(entity)
	_entities[event[1]] = entity


func _resolve_data_ref(ref, player_index: int):
	if typeof(ref) == TYPE_STRING:
		return load(ref) if ResourceLoader.exists(ref) else null
	if typeof(ref) != TYPE_ARRAY or ref.size() != 2 or typeof(ref[0]) != TYPE_INT or typeof(ref[1]) != TYPE_INT:
		return null
	if player_index < 0 or player_index >= RunData.get_player_count():
		return null
	var effects: Dictionary = RunData.get_player_effects(player_index)
	if not effects.has(ref[0]) or typeof(effects[ref[0]]) != TYPE_ARRAY:
		return null
	var list: Array = effects[ref[0]]
	if ref[1] < 0 or ref[1] >= list.size() or not list[ref[1]] is Resource:
		return null
	return list[ref[1]]


# The host simulates; the client copy only shows. Kinematic, so setting the position moves it.
func _make_inert(entity: Node) -> void :
	entity.set_physics_process(false)
	entity.mode = RigidBody2D.MODE_KINEMATIC
	for area in _find_areas(entity, []):
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)


func _find_areas(node: Node, result: Array) -> Array:
	if node is Area2D:
		result.append(node)
	for child in node.get_children():
		var _r = _find_areas(child, result)
	return result


func _client_die(event: Array) -> void :
	# [EVENT_DIE, net_id, knockback]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	var entity = _entities.get(event[1])
	var _erased = _entities.erase(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead:
		return
	var args: = Entity.DieArgs.new()
	# Not killed by a player here, so no loot, kill effects or stats on the client.
	args.enemy_killed_by_player = false
	args.knockback_vector = event[2]
	if entity is Unit:
		# Vanilla's physics slides the corpse with the knockback (enemies skip the rest when dead).
		entity.set_physics_process(true)
	entity.die(args)


func _client_birth(event: Array) -> void :
	# [EVENT_BIRTH, type, pos, charmed_by]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2 or typeof(event[3]) != TYPE_INT:
		return
	if not _main._cleaning_up:
		_main._entity_spawner.spawn_entity_birth(event[1], null, event[2], null, - 1, null, event[3])


func _client_weapon_shot(event: Array) -> void :
	# [EVENT_WEAPON, player_index, weapon_index, rotation, distance, attack type]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[5]) != TYPE_INT:
		return
	if typeof(event[3]) != TYPE_REAL or typeof(event[4]) != TYPE_REAL:
		return
	if event[1] < 0 or event[1] >= _main._players.size():
		return
	var player = _main._players[event[1]]
	if not is_instance_valid(player) or player.dead or event[2] < 0 or event[2] >= player.current_weapons.size():
		return
	var weapon = player.current_weapons[event[2]]
	if not is_instance_valid(weapon) or weapon._is_shooting:
		return
	weapon.rotation = event[3]
	if weapon is MeleeWeapon and event[5] != RANGED_ATTACK:
		weapon.next_attack_type = event[5]
		weapon._shooting_behavior.shoot(event[4])
	else:
		_client_ranged_recoil(weapon)


# The visible part of RangedWeaponShootingBehavior.shoot, without the projectiles.
func _client_ranged_recoil(weapon: Node) -> void :
	var stats = weapon.current_stats
	SoundManager.play(Utils.get_rand_element(stats.shooting_sounds), stats.sound_db_mod, 0.2)
	var initial_position: Vector2 = weapon.sprite.position
	weapon.set_shooting(true)
	weapon.tween.interpolate_property(weapon.sprite, "position", initial_position, Vector2(initial_position.x - stats.recoil, initial_position.y), stats.recoil_duration, Tween.TRANS_EXPO, Tween.EASE_OUT)
	weapon.tween.start()
	yield(weapon.tween, "tween_all_completed")
	if not is_instance_valid(weapon):
		return
	weapon.tween.interpolate_property(weapon.sprite, "position", weapon.sprite.position, initial_position, stats.recoil_duration, Tween.TRANS_EXPO, Tween.EASE_OUT)
	weapon.tween.start()
	yield(weapon.tween, "tween_all_completed")
	if is_instance_valid(weapon):
		weapon.set_shooting(false)


func _client_projectile(event: Array) -> void :
	# [EVENT_PROJECTILE, net_id, scene path, pos, velocity, rotation, speed, max range, is_enemy]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_STRING or typeof(event[3]) != TYPE_VECTOR2 or typeof(event[4]) != TYPE_VECTOR2:
		return
	if typeof(event[5]) != TYPE_REAL or typeof(event[6]) != TYPE_REAL or typeof(event[7]) != TYPE_INT or typeof(event[8]) != TYPE_BOOL:
		return
	if _main._cleaning_up:
		return
	var scene = _load_scene(event[2])
	if scene == null:
		return
	var container = _main._enemy_projectiles if event[8] else _main._player_projectiles
	if not is_instance_valid(container):
		return
	var pool_id: int = scene.get_instance_id()
	var projectile = _main.get_node_from_pool(pool_id, container)
	if not is_instance_valid(projectile):
		projectile = scene.instance()
		if not projectile is Projectile or projectile is GroupOfBullet or (not event[8] and not projectile is PlayerProjectile):
			projectile.free()
			return
		projectile.set_meta("pool_id", pool_id)
		if event[8]:
			_main.add_enemy_projectile(projectile)
		else:
			_main.add_player_projectile(projectile)

	projectile.global_position = event[3]
	projectile.velocity = event[4]
	projectile.rotation = event[5]
	if projectile is PlayerProjectile:
		# PlayerProjectile.shoot reads speed and range from the weapon stats.
		var stats: = RangedWeaponStats.new()
		stats.projectile_speed = int(event[6])
		stats.max_range = event[7]
		projectile.set_weapon_stats(stats)
		projectile.spawn_position = event[3]
	projectile.shoot()
	for area in _find_areas(projectile, []):
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	projectile.lan_net_id = event[1]
	_projectiles[event[1]] = projectile


func _client_projectile_stop(event: Array) -> void :
	# [EVENT_PROJECTILE_STOP, net_id, pos]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	var projectile = _projectiles.get(event[1])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1]:
		return
	projectile.global_position = event[2]
	projectile.stop()


func _load_scene(path: String):
	if not _scene_cache.has(path):
		var scene = load(path) if ResourceLoader.exists(path) else null
		_scene_cache[path] = scene if scene is PackedScene else null
	return _scene_cache[path]


func _send_own_state() -> void :
	if _local_index < 0 or _local_index >= _main._players.size():
		return
	var player = _main._players[_local_index]
	if not is_instance_valid(player) or player.dead:
		return
	# is_manual_aim returns null rather than false when manual aim is off.
	_net.send_player_state(player.global_position, player._current_movement, player.gamepad_attack_vector, Utils.is_manual_aim(_local_index) == true)


# Puppets show where the host had them INTERP_DELAY_MS ago, between the two snapshots around
# that time (or the newest one if none is newer).
func _update_puppets() -> void :
	if _snapshots.empty() or _clock_offset == null:
		return
	var render_time: float = OS.get_ticks_msec() - _clock_offset - INTERP_DELAY_MS
	while _snapshots.size() > 2 and _snapshots[1].time <= render_time:
		_snapshots.pop_front()
	var from: Dictionary = _snapshots[0]
	var to: Dictionary = _snapshots[1] if _snapshots.size() > 1 else from
	var weight: = 1.0
	if to.time > from.time:
		weight = clamp((render_time - from.time) / float(to.time - from.time), 0.0, 1.0)

	for player_index in _main._players.size():
		var player = _main._players[player_index]
		if player_index == _local_index or not is_instance_valid(player) or player.dead:
			continue
		var a: Dictionary = from.players[player_index]
		var b: Dictionary = to.players[player_index]
		player.global_position = a.pos.linear_interpolate(b.pos, weight)
		player.update_animation(b.move)

	for net_id in _entities:
		var entity = _entities[net_id]
		if not is_instance_valid(entity) or entity.dead:
			continue
		var a = from.entities.get(net_id)
		var b = to.entities.get(net_id)
		if a == null and b == null:
			continue
		if a == null:
			a = b
		elif b == null:
			b = a
		entity.global_position = a.linear_interpolate(b, weight)
		if entity is Unit:
			entity.update_animation(b - a)


# Host event: the wave ends (time out or everyone dead).
func on_wave_cleanup() -> void :
	_main.lan_clean_up_from_host()
