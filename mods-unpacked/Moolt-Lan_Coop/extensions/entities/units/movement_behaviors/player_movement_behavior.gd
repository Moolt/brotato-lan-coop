extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

# Remote players of a LAN session get device -1 (see LanNet._fill_coop_players), which has no
# input actions. Their own machine moves them (net/wave_sync.gd, the player.gd extension).
# The local player stands still while the pause menu is open (it doesn't pause a session).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func get_movement() -> Vector2:
	if device >= 0 and RunData.is_coop_run:
		var lan_net = LanGame.get_lan_net()
		if lan_net != null and lan_net.active and lan_net.pause_menu_open:
			return Vector2.ZERO
	return .get_movement()


func get_vector_for_input_prefix(prefix: String) -> Vector2:
	if RunData.is_coop_run and device < 0:
		return Vector2.ZERO
	return .get_vector_for_input_prefix(prefix)
