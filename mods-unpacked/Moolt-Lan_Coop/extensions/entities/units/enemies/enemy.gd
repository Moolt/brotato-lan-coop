extends "res://entities/units/enemies/enemy.gd"

# On LAN clients, enemies play the host's attack animations (net/wave_sync.gd). Their method
# tracks call start_shoot()/shoot(), which would run the attack locally (projectiles, charges,
# summons); on clients the host's events show those instead.
# In a session the hitbox leaves the enemies layer for LanGame.ENEMY_HITBOX_BIT (perf: no pairs
# with enemy bodies and weapon ranges). Only hurtboxes look for it (area_entered), and
# extensions/overlap/hurtbox.gd adds the bit to theirs. (Not an extension of hitbox.gd: reloading
# it breaks its inner class HitboxArgs.)

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _ready() -> void :
	if LanGame.in_session() and _hitbox.collision_layer & Utils.ENEMIES_BIT:
		_hitbox.collision_layer = (_hitbox.collision_layer & ~Utils.ENEMIES_BIT) | LanGame.ENEMY_HITBOX_BIT


func start_shoot() -> void :
	if LanGame.is_wave_client():
		return
	.start_shoot()


func shoot() -> void :
	if LanGame.is_wave_client():
		return
	.shoot()
