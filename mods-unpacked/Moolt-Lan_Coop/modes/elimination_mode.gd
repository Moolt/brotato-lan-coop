extends "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd"

# Base of the last-one-standing modes (Last Potato Standing, Send-back). The run is endless. A
# player who dies in a wave is out for the rest of the run: killed again at the start of each
# later wave (the camera then follows the others), no upgrades, Go at once. Once at most one
# player is left, the wave ends and so does the run: the survivor wins, or, if the last ones
# fell together, the last to fall. With one player it is a plain endless run. Everyone plays for
# themselves: materials and crates go to whoever picks them up.
# A won run here credits nothing on the own save (the verdict is "run lost" for everyone; the
# title and the results say who won).
# state: out (per player the wave they fell in, 0 = still in), out_order (first out first),
# winner (-1 until decided).
# Texts: mode_registry.gd (STRINGS), shared by the subclasses.

# Loot is never shared (ModeRegistry.get_fixed_settings, which also reads it for the subclasses).
const FIXED_SETTINGS: = ["share_materials", "share_crates"]


func start(players: Array) -> void :
	.start(players)
	RunData.is_endless_run = true
	var out: = []
	for _entry in players:
		out.append(0)
	state.out = out
	state.out_order = []
	state.winner = - 1


func get_material_receivers(picker: int):
	return [picker]


func shares_crates() -> bool:
	return false


func is_player_out(player_index: int) -> bool:
	var out: Array = state.get("out", [])
	return player_index >= 0 and player_index < out.size() and out[player_index] > 0


func get_players_in() -> Array:
	var result: = []
	for player_index in get_player_count():
		if not is_player_out(player_index):
			result.append(player_index)
	return result


func on_wave_started(main: Node) -> void :
	.on_wave_started(main)
	if is_host():
		# Like the disconnected players (LanWaveSync._kill_disconnected_players).
		call_deferred("_kill_out_players", main)


func _kill_out_players(main: Node) -> void :
	if not is_instance_valid(main):
		return
	for player_index in get_player_count():
		if is_player_out(player_index):
			kill_player(main, player_index)


func on_player_died(main: Node, player: Node, _args) -> void :
	if not is_host() or get_player_count() < 2 or main._cleaning_up or is_player_out(player.player_index):
		return
	state.out[player.player_index] = RunData.current_wave
	state.out_order.append(player.player_index)
	mark_dirty()
	if get_players_in().size() <= 1:
		# After every death of this frame (several can fall at once).
		main.call_deferred("lan_end_wave_now")


func adjust_run_states(_main: Node, states: Array) -> Array:
	if get_player_count() < 2:
		return states
	var players_in: = get_players_in()
	if players_in.size() > 1:
		return states
	if state.winner < 0:
		if players_in.size() == 1:
			state.winner = players_in[0]
		elif not state.out_order.empty():
			state.winner = state.out_order.back()
		mark_dirty()
	return [false, true, false]


func get_rank_key(player_index: int) -> Array:
	var out: Array = state.get("out", [])
	var out_wave: int = out[player_index] if player_index < out.size() else 0
	var order: int = state.get("out_order", []).find(player_index)
	return [1 if state.get("winner", - 1) == player_index else 0, 0 if out_wave > 0 else 1, order] + .get_rank_key(player_index)


func get_score_columns() -> Array:
	return [[KILLS, "LAN_SCORE_KILLS", KILLS_ICON]]


# The winner gets the crown, players who are out the skull and their wave.
func get_player_status(player_index: int) -> Dictionary:
	if state.get("winner", - 1) == player_index:
		return {"icon": WINNER_ICON}
	if is_player_out(player_index):
		return get_out_status(state.out[player_index])
	return {}


func get_banner(_main: Node) -> String:
	if get_player_count() < 2:
		return ""
	if is_player_out(get_local_index()):
		return tr("LAN_ELIM_YOU_ARE_OUT")
	return tr("LAN_ELIM_LEFT").replace("{0}", str(get_players_in().size()))


func get_leader() -> int:
	return state.get("winner", - 1)
