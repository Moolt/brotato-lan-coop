extends "res://singletons/weapon_service.gd"

# On the LAN host, every explosion is reported to LanWaveSync (net/wave_sync.gd), which shows it
# on the clients.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func explode(effect: ExplodingEffect, args: WeaponServiceExplodeArgs) -> Node:
	var instance = .explode(effect, args)
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host and instance != null:
		wave_sync.on_explosion(instance, effect)
	return instance
