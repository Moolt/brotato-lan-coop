extends "res://main.gd"

# LAN session changes to the wave scene.
# Remote players have device -1 (see LanNet._fill_coop_players), so the pause check skips them.
# Temporary until Step 7: the end of a wave goes back to the title screen (and its lobby)
# instead of the coop upgrade UI and shop, which only have 4 slots.


func _check_for_pause() -> void :
	if not _is_lan_session() or RunData.is_streamplay_run:
		._check_for_pause()
		return
	if _skip_pause_check:
		_skip_pause_check = false
		return
	for player_index in RunData.get_player_count():
		var remapped_device = CoopService.get_remapped_player_device(player_index)
		if remapped_device >= 0 and Input.is_action_just_released("ui_pause_%s" % remapped_device):
			_pause_menu.pause(player_index)
			break


func _on_EndWaveTimer_timeout() -> void :
	if not _is_lan_session():
		._on_EndWaveTimer_timeout()
		return
	SoundManager.clear_queue()
	SoundManager2D.clear_queue()
	InputService.set_gamepad_echo_processing(true)
	_end_wave_timer_timedout = true
	_change_scene(MenuData.title_screen_scene)


func _is_lan_session() -> bool:
	var lan_net = get_node_or_null("/root/LanNet")
	return lan_net != null and lan_net.active
