extends Control

# Arrows at the screen edge pointing at teammates the camera doesn't show, in their colour. A
# machine's camera follows only its own player, so the others can be off-screen. Added to main's
# UI layer by the main.gd extension during a session.

const EDGE_MARGIN: = 36.0
const ARROW_LENGTH: = 30.0
const ARROW_WIDTH: = 28.0
const OUTLINE_SIZE: = 4.0
const OUTLINE_COLOR: = Color(0.0, 0.0, 0.0, 0.8)

var _main: Node
var _local_index: = - 1


func init(main: Node, local_index: int) -> void :
	_main = main
	_local_index = local_index


func _ready() -> void :
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(PRESET_WIDE)


func _process(_delta: float) -> void :
	update()


func _draw() -> void :
	if _main == null or _main._cleaning_up:
		return
	var screen: Rect2 = get_viewport_rect()
	var center: Vector2 = screen.size / 2.0
	var half_inner: Vector2 = center - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	for player in _main._players:
		if not is_instance_valid(player) or player.dead or player.player_index == _local_index:
			continue
		var screen_pos: Vector2 = player.get_global_transform_with_canvas().origin
		if screen.has_point(screen_pos):
			continue
		var direction: Vector2 = (screen_pos - center).normalized()
		# Where the line from the centre towards the player leaves the inner rectangle.
		var scale_x: float = half_inner.x / abs(direction.x) if direction.x != 0.0 else INF
		var scale_y: float = half_inner.y / abs(direction.y) if direction.y != 0.0 else INF
		var tip: Vector2 = center + direction * min(scale_x, scale_y)
		_draw_arrow(tip, direction, CoopService.get_player_color(player.player_index))


func _draw_arrow(tip: Vector2, direction: Vector2, color: Color) -> void :
	var side: Vector2 = direction.tangent()
	var base: Vector2 = tip - direction * ARROW_LENGTH
	var points: = PoolVector2Array([tip, base + side * ARROW_WIDTH / 2.0, base - side * ARROW_WIDTH / 2.0])
	var outline: = PoolVector2Array([
		tip + direction * OUTLINE_SIZE * 2.0,
		base + (side * (ARROW_WIDTH / 2.0 + OUTLINE_SIZE * 2.0)) - direction * OUTLINE_SIZE,
		base - (side * (ARROW_WIDTH / 2.0 + OUTLINE_SIZE * 2.0)) - direction * OUTLINE_SIZE,
	])
	draw_colored_polygon(outline, OUTLINE_COLOR)
	draw_colored_polygon(points, color)
