extends "res://entities/units/player/player.gd"

# LAN session hooks, set by LanWaveSync (net/wave_sync.gd):
# - lan_net_driven (host, remote players): the client moves this player. The host places it
#   at the reported position, so vanilla adds no velocity; get_movement() returns the
#   reported direction for the animation and the moving/not-moving item effects.
# - lan_move_speed (client): the speed the host reports, which includes in-wave buffs and
#   slows the client doesn't simulate. Negative = vanilla.
# - lan_no_regen (client): HP comes from the host, so no local regeneration.
# The game mode decides on the host which hits hurt a player (LanMode.can_hit) and how much
# (scale_player_damage); in PvP modes the hurtbox also takes player hits.

var lan_net_driven: = false
var lan_move: = Vector2.ZERO
var lan_move_speed: = - 1.0
var lan_no_regen: = false

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


# Runs after vanilla's _ready.
func _ready() -> void :
	var mode = LanGame.get_mode()
	if mode != null and mode.uses_pvp():
		_hurtbox.collision_mask |= Utils.PLAYER_PROJECTILES_BIT


func _on_Hurtbox_area_entered(hitbox: Area2D) -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host and not LanGame.get_mode().can_hit(self, hitbox):
		return
	._on_Hurtbox_area_entered(hitbox)


# A player's hit has its weapon as `from`; vanilla's riposte (damage on dodge) calls
# from.take_damage, so for that call the attacker is the weapon's player.
func take_damage(value: int, args: TakeDamageArgs) -> Array:
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync == null or not wave_sync.is_host or not LanGame.get_mode().uses_pvp():
		return .take_damage(value, args)
	value = LanGame.get_mode().scale_player_damage(self, value, args)
	var hitbox = args.hitbox
	var from = hitbox.from if hitbox != null else null
	if from != null and is_instance_valid(from) and not from.has_method("take_damage") and from.get("_parent") is Unit:
		hitbox.from = from._parent
		var result: Array = .take_damage(value, args)
		if is_instance_valid(hitbox):
			hitbox.from = from
		return result
	return .take_damage(value, args)


func get_movement() -> Vector2:
	if lan_net_driven:
		return lan_move
	return .get_movement()


func get_next_velocity() -> Vector2:
	if lan_net_driven:
		return Vector2.ZERO
	return .get_next_velocity()


func get_move_speed() -> float:
	if lan_move_speed >= 0.0:
		return lan_move_speed
	return .get_move_speed()


func on_health_regen(loop_count: int) -> void :
	if lan_no_regen:
		return
	.on_health_regen(loop_count)


# Heal over time (fruit with the DLC's jerky, for example) ticks on SceneTreeTimers that outlive
# the wave. In the solo view between waves RunData holds only the own player, so a tick for a
# player beyond it raised script errors (vanilla's heal reads that player's effects). A session's
# wave is over by then: no more healing.
func on_heal_over_time_timer_timeout() -> void :
	if LanGame.in_session() and (player_index >= RunData.get_player_count() or Utils.get_scene_node().get("_cleaning_up") != false):
		return
	.on_heal_over_time_timer_timeout()
