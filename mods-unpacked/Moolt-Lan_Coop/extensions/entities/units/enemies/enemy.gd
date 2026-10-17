extends "res://entities/units/enemies/enemy.gd"

# On LAN clients, enemies play the host's attack animations (net/wave_sync.gd). Their method
# tracks call start_shoot()/shoot(), which would run the attack locally (projectiles, charges,
# summons); on clients the host's events show those instead.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func start_shoot() -> void :
	if LanGame.is_wave_client():
		return
	.start_shoot()


func shoot() -> void :
	if LanGame.is_wave_client():
		return
	.shoot()
