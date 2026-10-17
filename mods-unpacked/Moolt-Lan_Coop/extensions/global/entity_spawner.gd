extends "res://global/entity_spawner.gd"

# Grows the per-player arrays to 12 slots (see LanGame). During a LAN session, players spawn on a
# circle around the map centre instead of vanilla's 2x2 grid, which only has 4 spots.

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
	return .spawn_entity(scene, args, data, source, charmed_by)
