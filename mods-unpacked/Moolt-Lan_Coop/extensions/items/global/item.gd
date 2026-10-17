extends "res://items/global/item.gd"

# In-wave sync (net/wave_sync.gd) for materials and consumables. On the host, drops and pickups
# by players are reported to LanWaveSync. On clients these items are copies from the host's
# events; client players can't pick anything up (their areas are off), only the gold bag at the
# end of the wave does, as in vanilla. lan_net_id is 0 while not synced.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

var lan_net_id: = 0


func drop(pos: Vector2, p_rotation: float, p_push_back_destiation: Vector2) -> void :
	.drop(pos, p_rotation, p_push_back_destiation)
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_item_dropped(self)


func pickup(player_index: int) -> void :
	if lan_net_id != 0:
		var wave_sync = LanGame.get_wave_sync()
		if wave_sync != null:
			wave_sync.on_item_picked_up(self, player_index)
		lan_net_id = 0
	.pickup(player_index)
