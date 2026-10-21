extends "res://singletons/run_data.gd"

# Grows the per-player arrays to 12 slots (see LanGame), also after the functions that reassign
# them with 4 slots. In a LAN session a won run credits only the own character
# (game/session_progress.gd).

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


# Vanilla credits every player's character (one save in couch coop). In a session each machine
# credits its own: the run is the own player's solo run meanwhile, still recorded as coop.
func apply_run_won() -> void :
	var lan_net = LanGame.get_lan_net()
	if lan_net == null or not lan_net.active or lan_net.solo_view.active or not lan_net.enter_solo_view(false):
		.apply_run_won()
		return
	is_coop_run = true
	.apply_run_won()
	lan_net.leave_solo_view()


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
