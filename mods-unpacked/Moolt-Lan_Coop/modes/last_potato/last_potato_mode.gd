extends "res://mods-unpacked/Moolt-Lan_Coop/modes/elimination_mode.gd"

# Last Potato Standing: endless waves, last one alive wins (elimination_mode.gd). A storm closes
# in during every wave: the safe circle shrinks from the whole arena to END_RADIUS between
# SHRINK_FROM and SHRINK_TO of the wave, around a centre that drifts across the map; outside it
# players lose STORM_DAMAGE_PERCENT of their max HP (more in later waves) every STORM_TICK
# seconds, through armor, dodge and invincibility. The enemy count keeps scaling for every player of the
# run, so the survivors face more and more.
# Centre and radius come from the wave number, the run's seed (state.seed) and the wave timer,
# so every machine draws the same storm without traffic; only the host deals the damage.

const Storm = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/last_potato/storm.gd")

const SHRINK_FROM: = 0.15
const SHRINK_TO: = 1.0
const END_RADIUS: = 280.0
const END_RADIUS_PER_PLAYER: = 20.0
# The centre drifts on a Lissajous path (phases per wave): how far it swings from the map centre,
# as a share of the arena's size, and the seconds per swing on each axis. It stays far enough
# from the walls for the final circle to fit.
const DRIFT_EXTENT: = 0.3
const DRIFT_PERIOD_X: = 43.0
const DRIFT_PERIOD_Y: = 61.0
const STORM_TICK: = 0.5
const STORM_DAMAGE_PERCENT: = 4.0
const STORM_DAMAGE_PERCENT_PER_WAVE: = 0.25
const STORM_NAME: = "LanStorm"

const STRINGS: = {
	"en": {
		"LAN_MODE_LAST_POTATO": "Last Potato Standing",
		"LAN_MODE_LAST_POTATO_DESC": "Endless waves and a storm that closes in during each wave; outside the circle you lose HP. Whoever dies is out. The last one alive wins.",
		"LAN_STORM_OUTSIDE": "Get into the circle!",
	},
	"de": {
		"LAN_MODE_LAST_POTATO": "Die letzte Kartoffel",
		"LAN_MODE_LAST_POTATO_DESC": "Endlose Wellen und ein Sturm, der in jeder Welle näher kommt; außerhalb des Kreises verlierst du LP. Wer stirbt, ist raus. Wer zuletzt lebt, gewinnt.",
		"LAN_STORM_OUTSIDE": "Zurück in den Kreis!",
	},
}

var _tick: = 0.0


func start(players: Array) -> void :
	.start(players)
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	state.seed = rng.randi()


func on_wave_started(main: Node) -> void :
	.on_wave_started(main)
	_tick = 0.0
	if main.has_node(STORM_NAME):
		return
	var storm: = Storm.new()
	storm.name = STORM_NAME
	storm.init(self, main)
	main.add_child(storm)
	# On the floor: right above the tile map, under the entities.
	main.move_child(storm, main._tile_map.get_index() + 1)


func on_wave_physics(main: Node, delta: float) -> void :
	if not is_host():
		return
	_tick += delta
	if _tick < STORM_TICK:
		return
	_tick -= STORM_TICK
	var storm: = get_storm(main)
	var percent: float = STORM_DAMAGE_PERCENT + STORM_DAMAGE_PERCENT_PER_WAVE * RunData.current_wave
	for player in main._players:
		if not is_instance_valid(player) or player.dead or player.global_position.distance_to(storm[0]) <= storm[1]:
			continue
		var args: = TakeDamageArgs.new(RunData.DUMMY_PLAYER_INDEX)
		args.dodgeable = false
		args.armor_applied = false
		args.bypass_invincibility = true
		# No hit effect (white slashes at the player): every 0.5 s it looked like the player was
		# fighting the storm. The flash, sound and damage number stay; clients get the scale with
		# the damage event.
		args.base_effect_scale = 0.0
		var _taken = player.take_damage(int(max(1.0, ceil(player.max_stats.health * percent / 100.0))), args)


# [centre, radius] of the safe circle right now.
func get_storm(main: Node) -> Array:
	var rect: Rect2 = ZoneService.get_current_zone_rect()
	var end_radius: float = END_RADIUS + END_RADIUS_PER_PLAYER * get_player_count()
	var center: Vector2 = _get_center(main, rect, end_radius)
	var start_radius: float = 0.0
	for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		start_radius = max(start_radius, center.distance_to(corner))
	var shrink: float = clamp((get_wave_progress(main) - SHRINK_FROM) / (SHRINK_TO - SHRINK_FROM), 0.0, 1.0)
	return [center, lerp(start_radius, end_radius, shrink)]


func _get_center(main: Node, rect: Rect2, end_radius: float) -> Vector2:
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash([state.get("seed", 0), RunData.current_wave])
	var phase_x: = rng.randf_range(0.0, TAU)
	var phase_y: = rng.randf_range(0.0, TAU)
	var time: float = get_wave_elapsed(main)
	var middle: Vector2 = rect.position + rect.size / 2.0
	var center: Vector2 = middle + rect.size * DRIFT_EXTENT * Vector2(sin(TAU * time / DRIFT_PERIOD_X + phase_x), sin(TAU * time / DRIFT_PERIOD_Y + phase_y))
	# Keep the final circle inside the walls (on a small arena: the middle on that axis).
	var reach_x: float = max(0.0, rect.size.x / 2.0 - end_radius)
	var reach_y: float = max(0.0, rect.size.y / 2.0 - end_radius)
	return Vector2(clamp(center.x, middle.x - reach_x, middle.x + reach_x), clamp(center.y, middle.y - reach_y, middle.y + reach_y))


func get_banner(main: Node) -> String:
	var local_index: = get_local_index()
	if local_index >= 0 and local_index < main._players.size() and not main._cleaning_up:
		var player = main._players[local_index]
		var storm: = get_storm(main)
		if is_instance_valid(player) and not player.dead and player.global_position.distance_to(storm[0]) > storm[1]:
			return tr("LAN_STORM_OUTSIDE")
	return .get_banner(main)
