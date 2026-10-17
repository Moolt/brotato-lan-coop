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


func stop() -> void :
	var already_stopping: = _enable_stop_delay
	.stop()
	if lan_net_id != 0 and not already_stopping:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null and wave_sync.is_host:
			wave_sync.on_projectile_stopped(self)


func _return_to_pool() -> void :
	if lan_net_id != 0:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null:
			wave_sync.on_projectile_returned(self)
		lan_net_id = 0
	._return_to_pool()
