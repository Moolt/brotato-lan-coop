extends "res://projectiles/projectile.gd"

# In-wave sync (net/wave_sync.gd). On the host, shot and stopped projectiles are reported to
# LanWaveSync, which sends them to the clients. On clients these are copies from the host's
# events, and returning one to the pool frees its net id. lan_net_id is 0 while not synced.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

var lan_net_id: = 0


func shoot() -> void :
	.shoot()
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_projectile_shot(self)


# Id and position are taken before vanilla's stop(): without a stop delay (enemy bullets) it
# returns the projectile to the pool at once, which clears lan_net_id.
func stop(from_screen_border: bool = false) -> void :
	var already_stopping: = _enable_stop_delay
	var net_id: = lan_net_id
	var stopped_at: = global_position
	.stop(from_screen_border)
	if net_id != 0 and not already_stopping:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null and wave_sync.is_host:
			wave_sync.on_projectile_stopped(self, net_id, stopped_at)


# Primal Dread's ankylosaurus turns player bullets a random way: the host sends the new course.
func deflect(enemy_position: Vector2, deflect_angle_deg: float):
	.deflect(enemy_position, deflect_angle_deg)
	var wave_sync = LanGame.get_wave_sync()
	if lan_net_id != 0 and wave_sync != null and wave_sync.is_host:
		wave_sync.on_projectile_redirected(self)


func _return_to_pool() -> void :
	if lan_net_id != 0:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null:
			wave_sync.on_projectile_returned(self)
		lan_net_id = 0
	._return_to_pool()
