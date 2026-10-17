extends "res://ui/menus/ingame/ingame_main_menu.gd"

# Restart and End Run would leave the LAN run behind (a fresh local run, the 4-slot end screen),
# so they are hidden during a session. Quit returns to the title screen and its lobby.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func init(p_player_index: = 0) -> void :
	.init(p_player_index)
	if LanGame.in_session():
		$"%RestartButton".hide()
		$"%EndRunButton".hide()
