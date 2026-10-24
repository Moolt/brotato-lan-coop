extends "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd"

# King of the Hill: co-op waves, plus a zone that wanders through the arena. Every HILL_TICK
# seconds the living players inside it share HILL_BASE + HILL_PER_WAVE * wave materials per
# second (split evenly; alone you get it all). Materials and XP from enemies are shared as in
# co-op. Whoever earned the most on the hill over the run wins.
# The zone follows a Lissajous path from the run's seed and the wave timer, the same on every
# machine without traffic; the host pays out.

const Hill = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/king_of_the_hill/hill.gd")

const HILL_RADIUS: = 150.0
const HILL_TICK: = 1.0
const HILL_BASE: = 1.0
const HILL_PER_WAVE: = 0.4
# The path spans this share of the arena; periods in seconds.
const PATH_EXTENT: = 0.35
const PERIOD_X: = 37.0
const PERIOD_Y: = 53.0
const HILL: = "hill"
const HILL_NAME: = "LanHill"

const STRINGS: = {
	"en": {
		"LAN_MODE_HILL": "King of the Hill",
		"LAN_MODE_HILL_DESC": "Co-op waves and a wandering zone: standing in it earns materials, shared by everyone inside. Whoever earns the most on the hill wins.",
		"LAN_SCORE_HILL": "Hill",
		"LAN_HILL_YOURS": "The hill is yours!",
		"LAN_HILL_SHARED": "Sharing the hill",
		"LAN_HILL_HELD": "{0} holds the hill",
	},
	"de": {
		"LAN_MODE_HILL": "König des Hügels",
		"LAN_MODE_HILL_DESC": "Koop-Wellen und eine wandernde Zone: Wer darin steht, verdient Materialien, geteilt unter allen darin. Wer auf dem Hügel am meisten verdient, gewinnt.",
		"LAN_SCORE_HILL": "Hügel",
		"LAN_HILL_YOURS": "Der Hügel gehört dir!",
		"LAN_HILL_SHARED": "Du teilst den Hügel",
		"LAN_HILL_HELD": "{0} hält den Hügel",
	},
}

var _tick: = 0.0
# Host: materials earned but not paid yet (fractions), per player.
var _owed: = {}


func start(players: Array) -> void :
	.start(players)
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	state.seed = rng.randi()


func on_wave_started(main: Node) -> void :
	.on_wave_started(main)
	_tick = 0.0
	if main.has_node(HILL_NAME):
		return
	var hill: = Hill.new()
	hill.name = HILL_NAME
	hill.init(self, main)
	main.add_child(hill)
	main.move_child(hill, main._tile_map.get_index() + 1)


func on_wave_physics(main: Node, delta: float) -> void :
	if not is_host():
		return
	_tick += delta
	if _tick < HILL_TICK:
		return
	_tick -= HILL_TICK
	var players_inside: = get_players_inside(main, get_hill_position(main))
	if players_inside.empty():
		return
	var share: float = (HILL_BASE + HILL_PER_WAVE * RunData.current_wave) * HILL_TICK / players_inside.size()
	for player_index in players_inside:
		var owed: float = _owed.get(player_index, 0.0) + share
		var paid: = int(owed)
		_owed[player_index] = owed - paid
		if paid > 0:
			RunData.add_gold(paid, player_index)
			add_score(HILL, player_index, paid)


func get_hill_position(main: Node) -> Vector2:
	var rect: Rect2 = ZoneService.get_current_zone_rect()
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash([state.get("seed", 0), RunData.current_wave])
	var phase_x: = rng.randf_range(0.0, TAU)
	var phase_y: = rng.randf_range(0.0, TAU)
	var time: float = get_wave_elapsed(main)
	return rect.position + rect.size / 2.0 + rect.size * PATH_EXTENT * Vector2(sin(TAU * time / PERIOD_X + phase_x), sin(TAU * time / PERIOD_Y + phase_y))


func get_hill_radius() -> float:
	return HILL_RADIUS


func get_players_inside(main: Node, center: Vector2) -> Array:
	var result: = []
	if main._cleaning_up:
		return result
	for player in main._players:
		if is_instance_valid(player) and not player.dead and player.global_position.distance_to(center) <= HILL_RADIUS:
			result.append(player.player_index)
	return result


func get_score_columns() -> Array:
	return [[HILL, "LAN_SCORE_HILL"], [KILLS, "LAN_SCORE_KILLS"]]


func get_banner(main: Node) -> String:
	var players_inside: = get_players_inside(main, get_hill_position(main))
	if players_inside.has(get_local_index()):
		return tr("LAN_HILL_YOURS") if players_inside.size() == 1 else tr("LAN_HILL_SHARED")
	if players_inside.size() == 1:
		return tr("LAN_HILL_HELD").replace("{0}", get_player_name(players_inside[0]))
	return ""
