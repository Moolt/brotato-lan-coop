extends "res://singletons/focus_emulator_signal.gd"

# In-wave menus of a LAN session use native focus (see the pause_menu.gd extension), so no
# FocusEmulator reports which player focused a control. Coop UI code (inventory popups, stat
# panels) asks anyway and push_errors on -1; in a session the answer is the local player.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func get_player_index(expected_control: Control) -> int:
	var player_index: = .get_player_index(expected_control)
	if player_index < 0:
		var lan_net = LanGame.get_lan_net()
		if lan_net != null and lan_net.active and lan_net.local_player_index >= 0:
			return lan_net.local_player_index
	return player_index
