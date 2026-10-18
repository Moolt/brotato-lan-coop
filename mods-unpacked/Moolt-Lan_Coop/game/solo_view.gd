extends Reference

# Between waves every machine shows the vanilla solo UIs (upgrades, shop) for its own player.
# enter() turns the coop run into the local player's solo run: RunData holds only that player
# (index 0), is_coop_run is false, CoopService.connected_players lists only the local device.
# leave() puts everything back, with whatever the solo phase changed in the own player.
# RunData's per-player arrays outside players_data move between slot player_index and 0; pure
# caches are reset instead, since index 0 means another player afterwards.

# RunData arrays that hold player state: slot player_index goes to 0 and back.
const MOVED_ARRAYS: = [
	"_players_die_args",
	"remove_speed_effect_cache",
	"max_consumable_stats_gained_this_wave",
	"tracked_item_effects",
	"current_charmed_enemies",
	"steps_taken_this_wave",
	"locked_shop_items",
]

var active: = false
# The own player's index in the coop run.
var player_index: = - 1

var _players_data: = []
var _arrays: = {}
var _is_coop_run: = false
var _connected_players: = []


# local_coop_player: the local device's CoopService.connected_players entry.
func enter(index: int, local_coop_player: Array) -> bool:
	if active or index < 0 or index >= RunData.get_player_count():
		return false
	active = true
	player_index = index
	_players_data = RunData.players_data.duplicate()
	_is_coop_run = RunData.is_coop_run
	_connected_players = CoopService.connected_players.duplicate(true)

	_arrays = {}
	for array_name in MOVED_ARRAYS:
		var coop_array: Array = RunData.get(array_name)
		_arrays[array_name] = coop_array
		var solo_array: = []
		for i in coop_array.size():
			solo_array.append(coop_array[index] if i == 0 else _default_slot(array_name))
		RunData.set(array_name, solo_array)

	RunData.players_data = [_players_data[index]]
	RunData.set_coop_run(false)
	_set_connected_players([local_coop_player])
	_reset_caches()
	return true


func leave() -> void :
	if not active:
		return
	# Vanilla may have replaced the arrays meanwhile; slot 0 is the own player either way.
	for array_name in MOVED_ARRAYS:
		var solo_array: Array = RunData.get(array_name)
		var coop_array: Array = _arrays[array_name]
		if not solo_array.empty():
			coop_array[player_index] = solo_array[0]
		RunData.set(array_name, coop_array)

	if not RunData.players_data.empty():
		_players_data[player_index] = RunData.players_data[0]
	RunData.players_data = _players_data
	RunData.set_coop_run(_is_coop_run)
	_set_connected_players(_connected_players)
	_clear()
	_reset_caches()


# Forgets the coop run without restoring it (the session ended and RunData is reset anyway).
func discard() -> void :
	_clear()


func _clear() -> void :
	active = false
	player_index = - 1
	_players_data = []
	_arrays = {}
	_connected_players = []


func _default_slot(array_name: String):
	match array_name:
		"_players_die_args":
			return Utils.default_die_args
		"remove_speed_effect_cache":
			return {}
		"tracked_item_effects":
			return RunData.init_tracked_effects()
		"current_charmed_enemies", "steps_taken_this_wave":
			return 0
	return []


func _set_connected_players(players: Array) -> void :
	CoopService.connected_players = players
	CoopService.emit_signal("connected_players_updated", CoopService.connected_players)


# Caches keyed by player index. TempStats only hold in-wave stats, which main resets in
# clean_up_room, so resetting them loses nothing. LinkedStats are recomputed from the effects.
func _reset_caches() -> void :
	RunData.reset_run_caches()
	for i in RunData._are_player_stats_dirty.size():
		RunData._are_player_stats_dirty[i] = true
	Utils.reset_stat_caches()
	Utils.reset_last_elt_selected()
	TempStats.reset()
	LinkedStats.reset()
