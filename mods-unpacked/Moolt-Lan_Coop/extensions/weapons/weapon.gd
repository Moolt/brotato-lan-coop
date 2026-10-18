extends "res://weapons/weapon.gd"

# On LAN clients weapons never fire: the host simulates the attacks. They still turn towards
# their targets, and show the host's attacks (net/wave_sync.gd): melee weapons swing, ranged
# weapons recoil; their projectiles come as separate events.
# On the host, every attack is reported to LanWaveSync before vanilla runs it (melee weapons
# switch next_attack_type afterwards). A remote player's weapons aim (manual aim) at the point
# its client reports, not at the host's mouse.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func should_shoot() -> bool:
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and not wave_sync.is_host:
		return false
	return .should_shoot()


func shoot() -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		var distance: float = current_stats.max_range
		if not _manual_aim and _current_target.size() > 1 and is_instance_valid(_current_target[0]):
			distance = _current_target[1]
		wave_sync.on_weapon_shot(self, distance)
	.shoot()


# Vanilla's manual aim turns keyboard players' weapons towards the mouse. Remote players count as
# keyboard players on the host (device -1), so this covers their gamepad aim too.
func get_global_mouse_position() -> Vector2:
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		var aim_point = wave_sync.get_remote_aim_point(player_index)
		if aim_point != null:
			return aim_point
	return .get_global_mouse_position()
