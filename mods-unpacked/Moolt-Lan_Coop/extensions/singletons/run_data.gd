extends "res://singletons/run_data.gd"

# Grows the per-player arrays to 12 slots (see LanGame), also after the functions that reassign
# them with 4 slots.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	_lan_grow_player_arrays()


func reset(restart: bool = false) -> void :
	.reset(restart)
	_lan_grow_player_arrays()


func _reset_per_wave_properties() -> void :
	._reset_per_wave_properties()
	_lan_grow_player_arrays()


func reset_run_caches() -> void :
	.reset_run_caches()
	_lan_grow_player_arrays()


func resume_from_state(state: Dictionary) -> void :
	.resume_from_state(state)
	_lan_grow_player_arrays()


func _lan_grow_player_arrays() -> void :
	LanGame.grow(_players_die_args, Utils.default_die_args)
	LanGame.grow(remove_speed_effect_cache, {})
	LanGame.grow(items_nb_cache, {})
	LanGame.grow(different_items_nb_cache, {})
	LanGame.grow(duplicate_items_cache, null)
	LanGame.grow(max_consumable_stats_gained_this_wave, [])
	LanGame.grow(tracked_item_effects, init_tracked_effects())
	LanGame.grow(_are_player_stats_dirty, false)
	LanGame.grow(current_charmed_enemies, 0)
	LanGame.grow(steps_taken_this_wave, 0)
	LanGame.grow(locked_shop_items, [])
