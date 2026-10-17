extends "res://weapons/weapon.gd"

# On LAN clients weapons never fire: the host simulates the attacks (shown on clients in 6c).
# They still turn towards their targets.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func should_shoot() -> bool:
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and not wave_sync.is_host:
		return false
	return .should_shoot()
