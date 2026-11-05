extends "res://entities/gpe/dig_site/dig_site.gd"

# On a LAN client the dig site only shows the host's digging: no player of its own digs
# (lan_digging comes from the host's events), and it is dug up on the host's word, without the
# crate (the host drops that one).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

var lan_digging: = false


func is_being_dug() -> bool:
	if LanGame.is_wave_client():
		return lan_digging
	return .is_being_dug()


func _on_body_entered(body) -> void :
	if not LanGame.is_wave_client():
		._on_body_entered(body)


func _on_body_exited(body) -> void :
	if not LanGame.is_wave_client():
		._on_body_exited(body)


func _complete() -> void :
	if LanGame.is_wave_client():
		return
	._complete()


# Client: the host's state. Digging starts or stops (particles, as a player entering or leaving),
# with the host's progress; dug_up completes it here.
func lan_apply_host_state(digging: bool, host_progress: float, host_dug_up: bool) -> void :
	if dug_up:
		return
	progress = clamp(host_progress, 0.0, dig_time)
	if host_dug_up:
		lan_digging = false
		var crate = crate_data
		crate_data = null
		._complete()
		crate_data = crate
		return
	if digging and not lan_digging:
		_dig_particles.emitting = true
		$"%AnimationPlayer".play("body_enter")
	elif not digging:
		_dig_particles.emitting = false
	lan_digging = digging
	update()
