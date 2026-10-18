extends "res://singletons/progress_data.gd"

# Set by LanNet while a session is active: every peer runs with everything unlocked,
# and a net run must not end up in saved_run_state, so nothing is written to disk.
# Vanilla still changes the in-memory run state during a session (the shop saves it, losing a
# run resets it), so the player's own solo run ("Continue") is put aside when the session starts
# and restored when it ends; the next save after the session writes that one, not the LAN run.
var lan_coop_saves_blocked: = false setget lan_set_saves_blocked

var _lan_saved_run_state = null
var _lan_last_saved_run_state = null


func save() -> void :
	if lan_coop_saves_blocked:
		return
	.save()


func lan_set_saves_blocked(value: bool) -> void :
	if value == lan_coop_saves_blocked:
		return
	lan_coop_saves_blocked = value
	if value:
		_lan_saved_run_state = saved_run_state.duplicate(true)
		_lan_last_saved_run_state = last_saved_run_state.duplicate(true)
	elif _lan_saved_run_state != null:
		saved_run_state = _lan_saved_run_state
		last_saved_run_state = _lan_last_saved_run_state
		_lan_saved_run_state = null
		_lan_last_saved_run_state = null
