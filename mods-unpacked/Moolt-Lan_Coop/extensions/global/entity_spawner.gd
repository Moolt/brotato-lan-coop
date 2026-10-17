extends "res://global/entity_spawner.gd"

# Grows the per-player arrays to 12 slots (see LanGame). During a LAN session, players spawn on a
# circle around the map centre instead of vanilla's 2x2 grid, which only has 4 spots, and the
# enemy cap follows LanGame.get_enemy_cap_factor instead of vanilla's 1 + (n-1)/8.
# In-wave sync (net/wave_sync.gd): on the host, every non-player spawn and every spawn marker is
# reported to LanWaveSync. On clients, spawn markers only show; the entity comes from the host.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const SPAWN_RADIUS_BASE: = 60.0
const SPAWN_RADIUS_PER_PLAYER: = 15.0


func _init() -> void :
	LanGame.grow(lootworms, null)
	LanGame.grow(queues_to_spawn_structures, [])
	LanGame.grow(queues_to_spawn_pets, [])


func spawn_entity(scene: PackedScene, args: SpawnEntityArgs, data: Resource = null, source = null, charmed_by: int = - 1) -> KinematicBody2D:
	var player_count: int = RunData.get_player_count()
	if args.type == EntityType.PLAYER and player_count > 1 and LanGame.in_session():
		var radius: float = SPAWN_RADIUS_BASE + SPAWN_RADIUS_PER_PLAYER * player_count
		var angle: float = TAU * args.player_index / player_count
		args.position = _zone_max_pos / 2 + Vector2(radius, 0).rotated(angle)
	var entity = .spawn_entity(scene, args, data, source, charmed_by)
	if args.type != EntityType.PLAYER and entity != null:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null and wave_sync.is_host:
			wave_sync.on_entity_spawned(entity, scene, args.type, args.position, args.player_index, data, charmed_by)
	return entity


func spawn_entity_birth(type: int, scene: PackedScene, pos: Vector2, data: Resource = null, player_index: = - 1, source = null, charmed_by: = - 1) -> void :
	.spawn_entity_birth(type, scene, pos, data, player_index, source, charmed_by)
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_birth(type, pos, charmed_by)


func on_entity_birth_timeout(birth: EntityBirth) -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync == null or wave_sync.is_host:
		.on_entity_birth_timeout(birth)
		return
	active_births -= 1
	_main.add_node_to_pool(birth, _entity_birth_pool_id)


# Vanilla's cap is max_enemies * (1 + (n-1)/8). max_enemies is set for the call so that this
# comes out as max_enemies * LanGame.get_enemy_cap_factor(n). _current_wave_data is main's
# duplicate from ZoneService.get_wave_data; the value is restored anyway.
func on_group_spawn_timing_reached(group_data: WaveGroupData) -> void :
	var player_count: int = RunData.get_player_count()
	if player_count <= 1 or not LanGame.in_session() or _current_wave_data == null:
		.on_group_spawn_timing_reached(group_data)
		return
	var max_enemies: int = _current_wave_data.max_enemies
	var vanilla_factor: = 1.0 + (player_count - 1) / 8.0
	_current_wave_data.max_enemies = int(round(max_enemies * LanGame.get_enemy_cap_factor(player_count) / vanilla_factor))
	.on_group_spawn_timing_reached(group_data)
	_current_wave_data.max_enemies = max_enemies
