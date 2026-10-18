extends "res://overlap/hurtbox.gd"

# In a session hurtboxes that are hit by enemies (players, scapegoat) also listen to
# LanGame.ENEMY_HITBOX_BIT, where enemy hitboxes are then (extensions/.../enemies/enemy.gd).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _ready() -> void :
	if LanGame.in_session() and collision_mask & Utils.ENEMIES_BIT:
		collision_mask |= LanGame.ENEMY_HITBOX_BIT
