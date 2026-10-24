extends StaticBody2D

# Team Race's wall between the two halves of the arena: an obstacle for players and enemies
# (vanilla's obstacle layer), drawn as a dark strip with each side's team colour at its edge.

const WALL_COLOR: = Color(0.05, 0.05, 0.08, 0.92)
const EDGE_WIDTH: = 6.0
# Beyond the arena's top and bottom, so nothing slips around it.
const OVERHANG: = 400.0

var _rect: = Rect2()
var _colors: = []


func init(rect: Rect2, left_color: Color, right_color: Color) -> void :
	_rect = rect.grow_individual(0, OVERHANG, 0, OVERHANG)
	_colors = [left_color, right_color]
	collision_layer = Utils.OBSTACLES_BIT
	collision_mask = 0
	var shape: = RectangleShape2D.new()
	shape.extents = _rect.size / 2.0
	var collision: = CollisionShape2D.new()
	collision.shape = shape
	collision.position = _rect.position + _rect.size / 2.0
	add_child(collision)


func _draw() -> void :
	draw_rect(_rect, WALL_COLOR)
	draw_rect(Rect2(_rect.position, Vector2(EDGE_WIDTH, _rect.size.y)), _colors[0])
	draw_rect(Rect2(Vector2(_rect.end.x - EDGE_WIDTH, _rect.position.y), Vector2(EDGE_WIDTH, _rect.size.y)), _colors[1])
