extends Node2D

# King of the Hill's zone on the floor: a filled circle with a ring, in the colour of the player
# holding it alone, gold when nobody or several stand in it (from the mode, on every machine).

const FREE_COLOR: = Color(1.0, 0.85, 0.3)
const FILL_ALPHA: = 0.18
const RING_WIDTH: = 5.0
const POINTS: = 64

var _mode: Reference = null
var _main: Node = null


func init(mode: Reference, main: Node) -> void :
	_mode = mode
	_main = main


func _process(_delta: float) -> void :
	update()


func _draw() -> void :
	if _mode == null or not is_instance_valid(_main):
		return
	var center: Vector2 = _mode.get_hill_position(_main)
	var players_inside: Array = _mode.get_players_inside(_main, center)
	var color: = FREE_COLOR
	if players_inside.size() == 1:
		color = CoopService.get_player_color(players_inside[0])
	var fill: = color
	fill.a = FILL_ALPHA * (2.0 if not players_inside.empty() else 1.0)
	draw_circle(center, _mode.get_hill_radius(), fill)
	draw_arc(center, _mode.get_hill_radius(), 0.0, TAU, POINTS, color, RING_WIDTH, true)
