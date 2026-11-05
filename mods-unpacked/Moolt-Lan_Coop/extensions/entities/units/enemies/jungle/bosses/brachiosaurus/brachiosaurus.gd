extends "res://entities/units/enemies/jungle/bosses/brachiosaurus/brachiosaurus.gd"

# Primal Dread's brachiosaurus in a LAN session (net/wave_sync.gd). Its state timer runs every
# second and moves it between the map's edges with tweens, starts its lasers and adds its pivots.
# Only the host's runs: it reports each state change, and a client's copy applies the visible
# part (lan_apply_host_state); its position comes from the snapshot.
# LanGame comes from the enemy.gd extension.


func _on_CheckStateTimer_timeout() -> void :
	if LanGame.is_wave_client():
		return
	._on_CheckStateTimer_timeout()


func on_state_changed(new_state: int) -> void :
	.on_state_changed(new_state)
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_brachiosaurus_state(self, new_state)


# Client: what on_state_changed shows, without the moves and attacks (the host's come as the
# snapshot and events). The pivots' directions follow as EVENT_PIVOTS.
func lan_apply_host_state(new_state: int) -> void :
	current_state = new_state + 1
	is_laser_attack = new_state == 0
	if new_state == 1 and pivots == null:
		pivots = pivots_scene.instance()
		add_child(pivots)
		for child in pivots.get_bullets():
			register_additional_projectile(child)
