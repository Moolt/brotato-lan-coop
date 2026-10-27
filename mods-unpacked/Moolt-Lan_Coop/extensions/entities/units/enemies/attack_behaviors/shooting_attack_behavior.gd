extends "res://entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd"

# On LAN clients, enemies don't shoot: the host's projectile events show the shots. The enemy.gd
# extension blocks Enemy.shoot(), but some enemies call their behaviour's shoot() themselves, e.g.
# the DLC's pufferfish in die(), which clients call on their copies (a second, local volley).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func shoot() -> void :
	if LanGame.is_wave_client():
		return
	.shoot()
