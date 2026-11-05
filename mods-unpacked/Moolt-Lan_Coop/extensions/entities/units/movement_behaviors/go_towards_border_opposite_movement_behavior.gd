extends "res://entities/units/movement_behaviors/go_towards_border_opposite_movement_behavior.gd"

# Primal Dread's oviraptors and iguanodons charge across the map to its far side. Vanilla picks the
# side from the map's middle and runs a whole map's width. In a game mode that splits the arena
# (Team Race), they run across their own half (LanMode.get_play_region) and leave at its far
# edge, instead of crossing the wall into the other team's half. Runs on the host only (clients'
# copies don't move on their own).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const LAN_LEAVE_MARGIN: = 50.0


func get_target_position():
	var region = _lan_split_region()
	if region == null:
		return .get_target_position()
	var target: Vector2 = _parent.global_position
	target.y = rand_range(target.y - region.size.y / 2 / max_Y_diff, target.y + region.size.y / 2 / max_Y_diff)
	if target.x < region.position.x + region.size.x / 2.0:
		target.x += region.size.x
	else:
		target.x -= region.size.x
	return target


func get_movement() -> Vector2:
	var movement: Vector2 = .get_movement()
	var region = _lan_split_region()
	if region == null or not vector_done or not movement_started:
		return movement
	# At the wall side of its half it leaves (vanilla leaves past the map's outer edges, which
	# still holds there).
	var x: float = _parent.global_position.x
	var at_wall: = false
	if saved_vector.x > 0:
		at_wall = region.end.x < ZoneService.current_zone_max_position.x - 1.0 and x > region.end.x - LAN_LEAVE_MARGIN
	elif saved_vector.x < 0:
		at_wall = region.position.x > ZoneService.current_zone_min_position.x + 1.0 and x < region.position.x + LAN_LEAVE_MARGIN
	if at_wall:
		despawn_mob()
		return Vector2.ZERO
	return movement


# The play region the charger is in, null when the arena isn't split (vanilla's run).
func _lan_split_region():
	var mode = LanGame.get_mode()
	if mode == null or mode.get_play_regions().size() < 2:
		return null
	return mode.get_play_region(_parent.global_position)
