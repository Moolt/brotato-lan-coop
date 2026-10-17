extends "res://ui/menus/ingame/ingame_main_menu.gd"

# Restart and End Run would leave the LAN run behind (a fresh local run, the 4-slot end screen),
# so they are hidden during a session. Quit returns to the title screen and its lobby.


func init(p_player_index: = 0) -> void :
	.init(p_player_index)
	var lan_net = get_node_or_null("/root/LanNet")
	if lan_net != null and lan_net.active:
		$"%RestartButton".hide()
		$"%EndRunButton".hide()
