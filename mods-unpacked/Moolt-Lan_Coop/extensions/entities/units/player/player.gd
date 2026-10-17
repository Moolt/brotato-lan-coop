extends "res://entities/units/player/player.gd"

# LAN session hooks, set by LanWaveSync (net/wave_sync.gd):
# - lan_net_driven (host, remote players): the client moves this player. The host places it
#   at the reported position, so vanilla adds no velocity; get_movement() returns the
#   reported direction for the animation and the moving/not-moving item effects.
# - lan_move_speed (client): the speed the host reports, which includes in-wave buffs and
#   slows the client doesn't simulate. Negative = vanilla.
# - lan_no_regen (client): HP comes from the host, so no local regeneration.

var lan_net_driven: = false
var lan_move: = Vector2.ZERO
var lan_move_speed: = - 1.0
var lan_no_regen: = false


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
