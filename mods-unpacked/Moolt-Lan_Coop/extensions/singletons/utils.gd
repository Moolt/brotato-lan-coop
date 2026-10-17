extends "res://singletons/utils.gd"

# Grows the per-player arrays to 12 slots (see LanGame), also after the functions that reassign
# them with 4 slots. _process resets _manual_aim_cache to 4 slots every frame (deferred), so
# is_manual_aim grows it on demand. On the host, remote players' manual aim is what their
# client reports (net/wave_sync.gd).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	LanGame.grow(last_elt_selected, null)
	LanGame.grow(_stat_caches, {})
	LanGame.grow(_manual_aim_cache, null)


func reset_stat_caches() -> void :
	.reset_stat_caches()
	LanGame.grow(_stat_caches, {})


func reset_last_elt_selected() -> void :
	.reset_last_elt_selected()
	LanGame.grow(last_elt_selected, null)


func is_manual_aim(player_index: int) -> bool:
	var lan_net = LanGame.get_lan_net()
	if lan_net != null and lan_net.wave_sync != null:
		var remote_manual_aim = lan_net.wave_sync.get_remote_manual_aim(player_index)
		if remote_manual_aim != null:
			return remote_manual_aim
	if player_index >= _manual_aim_cache.size():
		LanGame.grow(_manual_aim_cache, null)
	return .is_manual_aim(player_index)
