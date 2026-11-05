extends "res://entities/gpe/poacher_zone/poacher_zone.gd"

# A poacher zone belongs to a player. When the game mode gives players a part of the arena
# (Team Race: their team's half), the zone stays in its owner's part: placed or moved into the
# other half, it moves to the same spot in the owner's. On every machine alike (clients place the
# zones from the shared seed and get the host's moves).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func set_owner_player(p_player_index: int) -> void :
	.set_owner_player(p_player_index)
	global_position = _lan_in_owner_region(global_position)


func relocate(new_position: Vector2) -> void :
	.relocate(_lan_in_owner_region(new_position))


func _lan_in_owner_region(pos: Vector2) -> Vector2:
	var mode = LanGame.get_mode()
	if mode == null:
		return pos
	var region = mode.get_player_region(player_index)
	if region == null or region.has_point(pos):
		return pos
	var from: Rect2 = mode.get_play_region(pos)
	return Vector2(pos.x - from.position.x + region.position.x, pos.y)
