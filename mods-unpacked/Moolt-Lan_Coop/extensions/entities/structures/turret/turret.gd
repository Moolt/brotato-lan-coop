extends "res://entities/structures/turret/turret.gd"

# On LAN clients, turrets play the host's shoot animation (net/wave_sync.gd), whose method track
# calls shoot(). There it only plays the sound; the projectiles come from the host.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func shoot() -> void :
	if LanGame.is_wave_client():
		SoundManager2D.play(Utils.get_rand_element(stats.shooting_sounds), global_position, stats.sound_db_mod, 0.2)
		return
	.shoot()
