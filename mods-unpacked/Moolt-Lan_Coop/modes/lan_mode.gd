extends Reference

# A LAN session's game mode: the rules of a run beyond plain co-op (docs/lan-coop-modes.md).
# Shared code asks the mode at fixed hook points (LanGame.get_mode()) and never checks which mode
# is active. This base class is the co-op run: every hook answers with today's behaviour, so a
# mode overrides only what it changes. Each mode lives in its own folder under modes/.
#
# One instance per run on every machine (LanNet.mode). The host builds it from
# lobby_settings.mode at Start (start()); clients build theirs from the host's first mode state.
# Hooks marked (host) run only on the host, which simulates the wave; (both) on every machine.
#
# State: what clients need (scores, who is out, the boss, the draft pool) lives in `state`,
# plain values only. The host changes it and calls mark_dirty(); LanNet sends it at most every
# NetProtocol.MODE_STATE_INTERVAL and clients take it over (set_state, state_changed). Requests
# and answers that are no state go as messages (send_message / send_message_to / on_message).

signal state_changed()

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const Scoreboard = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/scoreboard.gd")

const KILLS: = "kills"
const SCOREBOARD_NAME: = "LanScoreboard"

var id: = ""
# Which run this instance belongs to (the host counts runs; a client rebuilds on a new one).
var serial: = 0
var net: Node = null
var state: = {}
# Host: state changed since it was last sent.
var dirty: = false


# Called by ModeRegistry.create (GDScript 1 doesn't hand constructor arguments to an inherited
# _init).
func setup(p_net: Node, p_id: String) -> void :
	net = p_net
	id = p_id



# Lifecycle

# (host) Start: RunData holds the run built from the lobby; the mode sets up its state and may
# change the run (e.g. endless). players: the lobby entries, by player_index.
func start(players: Array) -> void :
	state = {"scores": {}, "player_count": players.size()}


# (both) A client takes over the host's state.
func set_state(new_state: Dictionary) -> void :
	state = new_state
	emit_signal("state_changed")


func mark_dirty() -> void :
	dirty = true
	emit_signal("state_changed")


# (both) LanWaveSync is up: the wave's players exist. Adds the scoreboard if the mode has scores.
func on_wave_started(main: Node) -> void :
	if not get_score_columns().empty() and not main.get_node("UI/HUD").has_node(SCOREBOARD_NAME):
		var scoreboard: = Scoreboard.new()
		scoreboard.name = SCOREBOARD_NAME
		scoreboard.init(self, main)
		main.get_node("UI/HUD").add_child(scoreboard)


# (both) Every physics frame of the wave, until it is cleaned up.
func on_wave_physics(_main: Node, _delta: float) -> void :
	pass


# (both) A player died in the wave (main._on_player_died).
func on_player_died(_main: Node, _player: Node, _args) -> void :
	pass


# (host) A synced entity died, not at the wave's cleanup. Counts kills by players.
func on_entity_died(_main: Node, entity: Node, args) -> void :
	if not entity is Enemy or args == Utils.default_die_args or not args.enemy_killed_by_player:
		return
	var killer: int = args.killed_by_player_index
	if killer >= 0 and killer < get_player_count():
		on_enemy_killed(entity, killer)


# (host) A player's attack killed an enemy.
func on_enemy_killed(_enemy: Node, killer: int) -> void :
	add_score(KILLS, killer, 1)


# (host) clean_up_room's verdict [wave failed, run lost, run won]; returns the one to use.
func adjust_run_states(_main: Node, states: Array) -> Array:
	return states


# (host) The wave is over (not failed), before the run goes to the clients: RunData is still the
# whole coop run.
func on_wave_end() -> void :
	pass


# (both) The player sits out between waves (no upgrades, Go at once) and stays dead in waves.
func is_player_out(_player_index: int) -> bool:
	return false



# Combat (host)

# Players' weapons and hurtboxes also see other players (PvP): weapon ranges get the player
# layer, player hurtboxes the player projectile layer. can_target and can_hit then decide.
func uses_pvp() -> bool:
	return false


# Whether a weapon may aim at a body that entered its range.
func can_target(_weapon: Node, _body: Node) -> bool:
	return true


# Whether a hitbox (attack, projectile, explosion) may hurt a unit.
func can_hit(_target: Node, _hitbox: Node) -> bool:
	return true


# Damage a player takes from a hit, after can_hit.
func scale_player_damage(_target: Node, value: int, _args) -> int:
	return value


# The players an enemy may chase; null = all of them.
func get_enemy_targets(_enemy: Node, _players: Array):
	return null



# Loot (host)

# The players a picked-up material is split over (one material and one XP each, round-robin);
# null = everyone, as vanilla coop.
func get_material_receivers(_picker: int):
	return null


# Whether crates go to any player (vanilla's share_coop_loot option) or to the picker.
func shares_crates() -> bool:
	return ProgressData.settings.share_coop_loot


# A player picked up materials worth value (before the split).
func on_materials_collected(_player_index: int, _value: float) -> void :
	pass



# Arena and spawns (both: every machine builds the same arena)

# The player count enemy count, HP and damage scale for.
func get_scaling_player_count(player_count: int) -> int:
	return player_count


# The enemy cap factor (LanGame.get_enemy_cap_factor for the scaling count).
func get_enemy_cap_factor(player_count: int, default_factor: float) -> float:
	return default_factor


# The arena's size in tiles from vanilla's: it grows with the player count (LanGame).
func get_arena_size(size: Vector2, player_count: int) -> Vector2:
	return (size * LanGame.get_arena_factor(player_count)).round()


# Where a player starts the wave; default is the session's spawn circle.
func get_player_spawn_position(_player_index: int, default_position: Vector2) -> Vector2:
	return default_position


# (host) The spawner spawned a non-player entity with this data (spawn_entity).
func on_entity_spawned(_entity: Node, _data) -> void :
	pass


# (host) A wave group was queued: queue entries from sizes_before[i] on are new, for
# spawner.queue_to_spawn, queue_to_spawn_bosses and queue_to_spawn_trees.
func on_group_queued(_spawner: Node, _sizes_before: Array) -> void :
	pass



# Shop (both, in the solo view: RunData index 0 is the own player)

func on_shop_ready(_shop: Node) -> void :
	pass


# The shop's new items ([item data, wave value] each); null = vanilla's.
func get_shop_items(_shop: Node, _count: int, _just_entered: bool):
	return null


# True if the mode takes over a purchase (the shop then waits for complete_buy).
func intercept_shop_buy(_shop: Node, _shop_item: Node) -> bool:
	return false


func blocks_reroll() -> bool:
	return false


# The mode's state changed while the shop is open (shops connected in on_shop_ready).
func on_shop_state_changed(_shop: Node) -> void :
	pass


func allows_item_locking() -> bool:
	return true



# Messages

# Client -> host.
func send_message(payload: Array) -> void :
	net.send_mode_message(payload)


# Host -> one client (or the host itself).
func send_message_to(player_index: int, payload: Array) -> void :
	net.send_mode_message_to(player_index, payload)


# (both) from_index: the sender's player index (the host is 0 to clients).
func on_message(_from_index: int, _payload: Array) -> void :
	pass



# Scores and results

# [[score key, translation key], ...] for the scoreboard and the results; empty = no scoreboard.
func get_score_columns() -> Array:
	return []


# What a row shows under the name ("" = nothing): out, boss, team, ...
func get_player_note(_player_index: int) -> String:
	return ""


# Sort key per player, larger first (an array compares element by element).
func get_rank_key(player_index: int) -> Array:
	var key: = []
	for column in get_score_columns():
		key.append(get_score(column[0], player_index))
	return key


# Player indices, best first.
func get_ranking() -> Array:
	var ranking: Array = range(get_player_count())
	ranking.sort_custom(self, "_ranks_before")
	return ranking


func _ranks_before(a: int, b: int) -> bool:
	var key_a: Array = get_rank_key(a)
	var key_b: Array = get_rank_key(b)
	for i in min(key_a.size(), key_b.size()):
		if key_a[i] != key_b[i]:
			return key_a[i] > key_b[i]
	return a < b


# A line under the wave timer for the local player ("" = none).
func get_banner(_main: Node) -> String:
	return ""


# The run's winner (so far): the first of the ranking, -1 while nobody scored or with one player.
func get_leader() -> int:
	if get_player_count() < 2:
		return - 1
	var ranking: = get_ranking()
	if ranking.empty():
		return - 1
	for value in get_rank_key(ranking[0]):
		if value > 0:
			return ranking[0]
	return - 1


# The end screen's title for the local player; "" = vanilla's.
func get_end_title() -> String:
	var leader: = get_leader()
	if leader < 0:
		return ""
	if leader == get_local_index():
		return tr("LAN_END_YOU_WIN")
	return tr("LAN_END_YOU_LOSE").replace("{0}", get_player_name(leader))


# The winner line on the end screen.
func get_result_text() -> String:
	var leader: = get_leader()
	return tr("LAN_RESULT_WINNER").replace("{0}", get_player_name(leader)) if leader >= 0 else tr("LAN_RESULT_DRAW")


# Whether the end screen's player list shows the winner, ranks and scores (end_run_player_list.gd).
func has_results() -> bool:
	return not get_score_columns().empty() and get_player_count() >= 2


# (both) The end screen: competitive modes set the title.
func on_end_screen(end_run: Node) -> void :
	if not has_results():
		return
	var title: String = get_end_title()
	if not title.empty():
		end_run._title.text = title


# Helpers

func get_player_count() -> int:
	return int(state.get("player_count", 0))


func get_local_index() -> int:
	return net.local_player_index


func is_host() -> bool:
	return net.is_host


func get_score(key: String, player_index: int) -> int:
	var scores: Array = state.get("scores", {}).get(key, [])
	return scores[player_index] if player_index >= 0 and player_index < scores.size() else 0


# (host)
func add_score(key: String, player_index: int, amount: int) -> void :
	if player_index < 0 or player_index >= get_player_count():
		return
	var scores: Dictionary = state.scores
	if not scores.has(key):
		var values: = []
		values.resize(get_player_count())
		for i in values.size():
			values[i] = 0
		scores[key] = values
	scores[key][player_index] += amount
	mark_dirty()


func get_player_name(player_index: int) -> String:
	var entry = net.get_player(player_index)
	return entry.name if entry != null else "?"


# The player whose weapon, projectile or explosion a hitbox belongs to, -1 for enemies.
static func get_attacker_index(hitbox: Node) -> int:
	if hitbox == null or not is_instance_valid(hitbox.from):
		return - 1
	var from = hitbox.from
	if from is Enemy:
		return - 1
	var player_index = from.get("player_index")
	return player_index if typeof(player_index) == TYPE_INT else - 1


# (host) Kills a player as the session does (no killer, fresh die args).
static func kill_player(main: Node, player_index: int) -> void :
	if player_index < 0 or player_index >= main._players.size() or main._cleaning_up:
		return
	var player = main._players[player_index]
	if is_instance_valid(player) and not player.dead:
		var args: = Entity.DieArgs.new()
		args.enemy_killed_by_player = false
		player.die(args)


# Seconds of the wave played so far (the same on every machine: clients follow the host's
# timer), 0 while it waits for clients.
static func get_wave_elapsed(main: Node) -> float:
	var timer: Timer = main._wave_timer
	return max(0.0, timer.wait_time - timer.time_left)


# 0..1 of the wave played so far.
static func get_wave_progress(main: Node) -> float:
	var timer: Timer = main._wave_timer
	return clamp(get_wave_elapsed(main) / max(1.0, timer.wait_time), 0.0, 1.0)
