extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

# Remote players of a LAN session get device -1 (see LanNet._fill_coop_players), which has no
# input actions. Until Step 6 feeds their network input, they stand still.


func get_vector_for_input_prefix(prefix: String) -> Vector2:
	if RunData.is_coop_run and device < 0:
		return Vector2.ZERO
	return .get_vector_for_input_prefix(prefix)
