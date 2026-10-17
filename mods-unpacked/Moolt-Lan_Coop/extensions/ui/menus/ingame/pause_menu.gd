extends "res://ui/menus/ingame/pause_menu.gd"

# During a LAN session the pause menu only opens the menu: the game keeps running on every
# machine, so get_tree().paused stays false (pausing the tree would also stop the physics
# server). LanNet.pause_menu_open tells the local player's movement to stand still meanwhile.
# Vanilla's _input decides open/closed by get_tree().paused, so with the menu open it calls
# pause() again on the pause button: that closes the menu here. This _input runs before
# vanilla's for the same event and handles cancel; _lan_skip_pause keeps vanilla from reopening
# the menu when one key is both cancel and pause.
# The FocusEmulator (couch coop's per-player menu focus) stays off: it marks every input it
# doesn't handle as handled, mouse motion and clicks included, so the mouse couldn't reach the
# menu. With one player per machine, native focus works as in solo play; the menu still belongs
# to the local player (inventory, pause and cancel keys).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

var _lan_open: = false
var _lan_skip_pause: = false


func _input(event: InputEvent) -> void :
	_lan_skip_pause = false
	if not _lan_open:
		return
	if Utils.is_player_cancel_released(event, _player_index) or Utils.is_player_pause_released(event, _player_index):
		if codex_is_opened:
			return
		var was_open: bool = _main_menu.visible
		manage_back()
		_lan_skip_pause = true
		if not was_open:
			get_viewport().set_input_as_handled()


func pause(player_index: int) -> void :
	if not LanGame.in_session():
		.pause(player_index)
		return
	if _lan_skip_pause:
		_lan_skip_pause = false
		return
	if _lan_open:
		manage_back()
		return
	set_process_input(true)
	if not enabled:
		return
	_player_index = player_index
	_lan_set_open(true)
	emit_signal("paused")
	show()
	Utils.set_default_cursor()
	_main_menu.init(player_index)


func unpause() -> void :
	if not _lan_open:
		.unpause()
		return
	set_process_input(false)
	_focus_emulator.set_process_input(false)
	_focus_emulator.player_index = - 1
	hide()
	_lan_set_open(false)
	_menus.reset()
	emit_signal("unpaused")


func _lan_set_open(value: bool) -> void :
	_lan_open = value
	var lan_net = LanGame.get_lan_net()
	if lan_net != null:
		lan_net.pause_menu_open = value


func _exit_tree() -> void :
	if _lan_open:
		_lan_set_open(false)
