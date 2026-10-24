extends Node2D

# Last Potato Standing's storm, drawn on the floor under the entities: everything outside the
# safe circle is tinted, with a bright ring at its edge. The circle comes from the mode
# (get_storm), the same on every machine.

const OUTSIDE_COLOR: = Color(0.35, 0.05, 0.45, 0.4)
const RING_COLOR: = Color(0.85, 0.35, 1.0, 0.9)
const RING_WIDTH: = 6.0
const POINTS: = 96

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
	var storm: Array = _mode.get_storm(_main)
	var center: Vector2 = storm[0]
	var radius: float = storm[1]
	# A band wide enough to cover the whole arena outside the circle, as quads that only share
	# edges (one thick draw_arc overlaps itself where it closes: a darker wedge on the right).
	var outer: float = radius + ZoneService.get_current_zone_rect().size.length() * 2.0
	var colors: = PoolColorArray([OUTSIDE_COLOR, OUTSIDE_COLOR, OUTSIDE_COLOR, OUTSIDE_COLOR])
	var previous: = Vector2.RIGHT
	for i in range(1, POINTS + 1):
		var direction: = Vector2.RIGHT.rotated(TAU * i / POINTS)
		draw_polygon(PoolVector2Array([center + previous * radius, center + direction * radius, center + direction * outer, center + previous * outer]), colors)
		previous = direction
	draw_arc(center, radius, 0.0, TAU, POINTS * 2, RING_COLOR, RING_WIDTH, true)
