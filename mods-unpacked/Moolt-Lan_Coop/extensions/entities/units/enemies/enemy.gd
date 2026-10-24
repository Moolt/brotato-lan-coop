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


func update_target() -> void :
	var mode = LanGame.get_mode()
	var targets = mode.get_enemy_targets(self, players_ref) if mode != null else null
	# Vanilla keeps the old target when it finds none; with no allowed player, all may be chased.
	if targets == null or targets.empty():
		.update_target()
		return
	var all_players: Array = players_ref
	players_ref = targets
	.update_target()
	players_ref = all_players


func _on_Hurtbox_area_entered(hitbox: Area2D) -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host and not LanGame.get_mode().can_hit(self, hitbox):
		return
	._on_Hurtbox_area_entered(hitbox)
