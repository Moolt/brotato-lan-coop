extends "res://singletons/progress_data.gd"

# Set by LanNet while a session is active: every peer runs with everything unlocked,
# and a net run must not end up in saved_run_state, so nothing is written to disk.
var lan_coop_saves_blocked: = false


func save() -> void :
	if lan_coop_saves_blocked:
		return
	.save()
