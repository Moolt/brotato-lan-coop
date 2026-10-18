extends "res://singletons/utils.gd"

# Grows the per-player arrays to 12 slots (see LanGame), also after the functions that reassign
# them with 4 slots. _process resets _manual_aim_cache to 4 slots every frame (deferred), so
# is_manual_aim grows it on demand. On the host, remote players' manual aim is what their
# client reports (net/wave_sync.gd). Vanilla coop has no mouse aim (the players share one
# mouse); in a session the local player has its own, so it aims as in solo play.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	LanGame.grow(last_elt_selected, null)
	LanGame.grow(_stat_caches, {})
	LanGame.grow(_manual_aim_cache, null)


func reset_stat_caches() -> void :
	.reset_stat_caches()
	LanGame.grow(_stat_caches, {})


func reset_last_elt_selected() -> void :
	.reset_last_elt_selected()
	LanGame.grow(last_elt_selected, null)


func is_manual_aim(player_index: int) -> bool:
	var lan_net = LanGame.get_lan_net()
	if lan_net != null and lan_net.wave_sync != null:
		var remote_manual_aim = lan_net.wave_sync.get_remote_manual_aim(player_index)
		if remote_manual_aim != null:
			return remote_manual_aim
	if player_index >= _manual_aim_cache.size():
		LanGame.grow(_manual_aim_cache, null)
	if lan_net != null and lan_net.active and RunData.is_coop_run and player_index == lan_net.local_player_index:
		return _lan_is_local_manual_aim(player_index)
	return .is_manual_aim(player_index)


# Vanilla's is_manual_aim with its solo rules for the mouse.
func _lan_is_local_manual_aim(player_index: int) -> bool:
	var is_manual = _manual_aim_cache[player_index]
	if is_manual != null:
		return is_manual

	is_manual = false
	if ProgressData.settings.manual_aim_on_mouse_press or (on_console and ProgressData.settings.manual_aim):
		var is_mouse_pressed = Input.is_mouse_button_pressed(BUTTON_LEFT)
		var is_gamepad_pressed = is_player_using_gamepad(player_index) and get_player_rjoy_vector(player_index).length_squared() > 0.05
		is_manual = is_mouse_pressed or is_gamepad_pressed
	elif ProgressData.settings.manual_aim:
		is_manual = true

	_manual_aim_cache[player_index] = is_manual
	return is_manual
