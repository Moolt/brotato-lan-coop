extends "res://ui/menus/run/base_end_run.gd"

# At the end of a LAN run every machine shows the solo end screen for its own player (RunData is
# the solo view, game/solo_view.gd). Restart and New Run would start a local run, so only Exit
# stays: back to the title screen and the session's lobby (LanNet.on_title_screen ends the solo
# view), where the host can start the next run.
# The game mode may change the title and add its results (LanMode.on_end_screen).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


# Runs after vanilla's _ready.
func _ready() -> void :
	if not LanGame.in_session():
		return
	_restart_button.hide()
	_new_run_button.hide()
	_exit_button.text = "LAN_BACK_TO_LOBBY"
	LanGame.get_mode().on_end_screen(self)
	# end_run.gd's _ready (after this one) sets up the rest; focus Exit once it's done.
	call_deferred("_lan_focus_exit")


func _lan_focus_exit() -> void :
	_exit_button.grab_focus()
