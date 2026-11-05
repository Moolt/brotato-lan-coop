extends "res://global/gpe_spawner.gd"

# Primal Dread's ground effects (GPE) in a LAN session (net/wave_sync.gd):
# - The holes of a jungle wave come from one of several prepared layouts, picked at random. In a
#   session every machine picks the same one, from the host's wave seed
#   (lobby_settings.wave_seed, new for each run the host sends) and the wave number: holes are
#   obstacles, so the own player must meet the same ones as on the host.
# - Acid, petrol and fire puddles: only the host spawns them and reports each one to LanWaveSync,
#   which shows a copy without areas on the clients. Clients don't spawn their own: evolved enemy
#   copies, projectile copies and the fire trail would leave puddles there that the host doesn't
#   have. Vanilla's callers all accept null.
# - A single hole (the brachiosaurus foot's stomp) is spawned by the host and sent the same way.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

# Set while LanWaveSync spawns the host's hole on a client.
var lan_from_host: = false


func spawn_holes_full_scene() -> void :
	var lan_net = LanGame.get_lan_net()
	if lan_net == null or not lan_net.active:
		.spawn_holes_full_scene()
		return
	# Vanilla's choice of layouts, with a seeded pick instead of pick_random.
	var map_size = RunData.sum_all_player_effects(Keys.map_size_hash)
	var scenes: Array = holes_scene
	if map_size == 33:
		scenes = holes_explorer_scene
	elif map_size != 0:
		scenes = holes_old_scene
	if scenes.empty():
		return
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash([lan_net.lobby_settings.get("wave_seed", 0), RunData.current_wave])
	var hole_instance = scenes[rng.randi() % scenes.size()].instance()
	hole_instance.global_position = Vector2.ONE
	_gpe_container.add_child(hole_instance)


func spawn_single_hole_at_position(position: Vector2) -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and not wave_sync.is_host and not lan_from_host:
		return
	.spawn_single_hole_at_position(position)
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_hole_spawned(position)


func get_new_acid_puddle_at_pos(pos: Vector2, no_lifeTime: bool, small_acid: bool) -> Node2D:
	if _lan_is_client():
		return null
	return _lan_report(.get_new_acid_puddle_at_pos(pos, no_lifeTime, small_acid), 0)


func get_new_petrol_puddle_at_pos(pos: Vector2, no_lifeTime: bool, small_petrol: bool) -> Node2D:
	if _lan_is_client():
		return null
	return _lan_report(.get_new_petrol_puddle_at_pos(pos, no_lifeTime, small_petrol), 1)


func get_new_fire_puddle_at_pos(pos: Vector2, burning_data: BurningData, size: Vector2 = FIRE_PUDDLE_SCALE, puddle_lifetime: float = FIRE_PUDDLE_LIFETIME, player_index: = - 1) -> Node2D:
	if _lan_is_client():
		return null
	return _lan_report(.get_new_fire_puddle_at_pos(pos, burning_data, size, puddle_lifetime, player_index), 2)


# A client in a session, also between the wave's end and the next scene (the wave sync is gone
# by then, but clients still don't spawn puddles).
func _lan_is_client() -> bool:
	var lan_net = LanGame.get_lan_net()
	return lan_net != null and lan_net.active and not lan_net.is_host


func _lan_report(puddle: Node2D, kind: int) -> Node2D:
	if puddle != null:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null and wave_sync.is_host:
			wave_sync.on_puddle_spawned(puddle, kind)
	return puddle
