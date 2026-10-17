extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

# Remote players of a LAN session get device -1 (see LanNet._fill_coop_players), which has no
# input actions. Their own machine moves them (net/wave_sync.gd, the player.gd extension).


func get_vector_for_input_prefix(prefix: String) -> Vector2:
	if RunData.is_coop_run and device < 0:
		return Vector2.ZERO
	return .get_vector_for_input_prefix(prefix)
