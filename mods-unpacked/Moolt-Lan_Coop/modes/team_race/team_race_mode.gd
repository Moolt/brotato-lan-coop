extends "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd"

# Team Race: two teams (picked in the lobby) play the same waves side by side. The arena is two
# halves, each sized for the bigger team, with a wall between them (divider.gd). Every enemy,
# tree and boss the wave spawns comes twice, at the same spot in each half; enemies chase only the
# players of their half, and weapons aim at and hurt only their own half. Scaling (enemy count,
# HP, damage) follows the bigger team; the enemy cap is the session's normal one for both halves
# together, so the load stays as in co-op. Materials are shared within the team, crates go to the
# picker.
# A team whose players are all dead at once is out: its half is cleared and gets no more
# enemies, its players stay dead. The run ends when both are out or the last wave is won; the
# team that lasted longer wins, then the one with more kills. With an empty team it is co-op.
# state: teams (per player 0/1), split (both teams have players), out_wave (per team, 0 = in),
# winner_team (-1 = none yet, 2 = draw).

const Divider = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/team_race/divider.gd")
const ModeRegistry = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/mode_registry.gd")
const GAP_TILES: = 6
# Mapped spawn positions keep this far from a half's side edges.
const SPAWN_EDGE: = 64.0
const SPAWN_RADIUS_BASE: = 60.0
const SPAWN_RADIUS_PER_PLAYER: = 15.0
const DIVIDER_NAME: = "LanTeamDivider"
const DRAW: = 2

const STRINGS: = {
	"en": {
		"LAN_MODE_TEAM_RACE": "Team Race",
		"LAN_MODE_TEAM_RACE_DESC": "Two teams play the same waves side by side, a wall between them. A team whose players all die is out. The team that lasts longer wins, then the one with more kills.",
		"LAN_TEAM_ALIVE": "{0}: {1} alive",
		"LAN_TEAM_OUT": "{0}: out",
		"LAN_TEAM_WINS": "{0} wins",
		"LAN_TEAM_YOU_WIN": "Your team wins!",
		"LAN_NOTE_TEAM_OUT": "out in wave {0}",
	},
	"de": {
		"LAN_MODE_TEAM_RACE": "Team-Rennen",
		"LAN_MODE_TEAM_RACE_DESC": "Zwei Teams spielen dieselben Wellen nebeneinander, getrennt durch eine Wand. Ein Team, dessen Spieler alle sterben, ist raus. Es gewinnt das Team, das länger durchhält, dann das mit mehr Kills.",
		"LAN_TEAM_ALIVE": "{0}: {1} am Leben",
		"LAN_TEAM_OUT": "{0}: raus",
		"LAN_TEAM_WINS": "{0} gewinnt",
		"LAN_TEAM_YOU_WIN": "Dein Team gewinnt!",
		"LAN_NOTE_TEAM_OUT": "raus in Welle {0}",
	},
}

var _main: Node = null


func start(players: Array) -> void :
	.start(players)
	var teams: = []
	var sizes: = [0, 0]
	for entry in players:
		var team: = int(entry.get("team", entry.player_index % 2)) % 2
		teams.append(team)
		sizes[team] += 1
	state.teams = teams
	state.split = sizes[0] > 0 and sizes[1] > 0
	state.out_wave = [0, 0]
	state.winner_team = - 1


func is_split() -> bool:
	return state.get("split", false)


func get_team(player_index: int) -> int:
	var teams: Array = state.get("teams", [])
	return teams[player_index] if player_index >= 0 and player_index < teams.size() else 0


func get_team_size(team: int) -> int:
	return state.get("teams", []).count(team)


func is_team_out(team: int) -> bool:
	return is_split() and state.out_wave[team] > 0


func is_player_out(player_index: int) -> bool:
	return is_team_out(get_team(player_index))


func get_team_color(team: int) -> Color:
	return ModeRegistry.TEAM_COLORS[team]


func get_team_name(team: int) -> String:
	return tr(ModeRegistry.TEAM_NAMES[team])



# Arena: [half width, gap] in px, and which half a position is in.

func _get_half_width() -> float:
	return (ZoneService.current_zone_max_position.x - GAP_TILES * Utils.TILE_SIZE) / 2.0


func _get_offset() -> float:
	return _get_half_width() + GAP_TILES * Utils.TILE_SIZE


func get_side(pos: Vector2) -> int:
	return 1 if pos.x > _get_half_width() + GAP_TILES * Utils.TILE_SIZE / 2.0 else 0


func get_scaling_player_count(player_count: int) -> int:
	if not is_split():
		return player_count
	return int(max(get_team_size(0), get_team_size(1)))


func get_enemy_cap_factor(player_count: int, default_factor: float) -> float:
	if not is_split():
		return default_factor
	return min(2.0 * LanGame.get_enemy_cap_factor(get_scaling_player_count(player_count)), LanGame.MAX_ENEMY_CAP_FACTOR)


func get_arena_size(size: Vector2, player_count: int) -> Vector2:
	if not is_split():
		return .get_arena_size(size, player_count)
	var half: Vector2 = (size * LanGame.get_arena_factor(get_scaling_player_count(player_count))).round()
	return Vector2(half.x * 2 + GAP_TILES, half.y)


func get_player_spawn_position(player_index: int, default_position: Vector2) -> Vector2:
	if not is_split():
		return default_position
	var team: = get_team(player_index)
	var members: = []
	for i in state.teams.size():
		if state.teams[i] == team:
			members.append(i)
	var half: = _get_half_width()
	var center: = Vector2(half / 2.0 + team * _get_offset(), ZoneService.current_zone_max_position.y / 2.0)
	if members.size() <= 1:
		return center
	var radius: float = SPAWN_RADIUS_BASE + SPAWN_RADIUS_PER_PLAYER * members.size()
	return center + Vector2(radius, 0).rotated(TAU * members.find(player_index) / members.size())


func on_wave_started(main: Node) -> void :
	_main = main
	.on_wave_started(main)
	if not is_split():
		return
	if not main.has_node(DIVIDER_NAME):
		var divider: = Divider.new()
		divider.name = DIVIDER_NAME
		var height: float = ZoneService.current_zone_max_position.y
		divider.init(Rect2(_get_half_width(), 0, GAP_TILES * Utils.TILE_SIZE, height), ModeRegistry.TEAM_COLORS[0], ModeRegistry.TEAM_COLORS[1])
		main.add_child(divider)
		main.move_child(divider, main._tile_map.get_index() + 1)
	if is_host():
		call_deferred("_kill_out_players", main)


func _kill_out_players(main: Node) -> void :
	if not is_instance_valid(main):
		return
	for player_index in get_player_count():
		if is_player_out(player_index):
			kill_player(main, player_index)


# Every new spawn goes into the first half, with a twin at the same spot in the second; a half
# whose team is out gets none.
func on_group_queued(spawner: Node, sizes_before: Array) -> void :
	if not is_split():
		return
	var queues: = [spawner.queue_to_spawn, spawner.queue_to_spawn_bosses, spawner.queue_to_spawn_trees]
	var half: = _get_half_width()
	var offset: = _get_offset()
	for i in queues.size():
		var queue: Array = queues[i]
		var added: Array = queue.slice(sizes_before[i], queue.size() - 1) if queue.size() > sizes_before[i] else []
		queue.resize(sizes_before[i])
		for entry in added:
			var pos: Vector2 = entry[2]
			if pos.x > half + (offset - half) / 2.0:
				pos.x -= offset
			pos.x = clamp(pos.x, SPAWN_EDGE, half - SPAWN_EDGE)
			for team in 2:
				if not is_team_out(team):
					var copy: Array = entry.duplicate()
					copy[2] = pos + Vector2(team * offset, 0)
					queue.append(copy)


# Enemies queued for a half before its team went out (summons, births under way) die at once.
func on_entity_spawned(entity: Node, _data) -> void :
	if is_split() and entity is Enemy and is_team_out(get_side(entity.global_position)):
		entity.call_deferred("die", _quiet_die_args())



# Combat (host)

func get_enemy_targets(enemy: Node, players: Array):
	if not is_split():
		return null
	var side: = get_side(enemy.global_position)
	var targets: = []
	for player in players:
		if get_team(player.player_index) == side:
			targets.append(player)
	return targets


func can_target(weapon: Node, body: Node) -> bool:
	return not is_split() or body is Player or get_side(body.global_position) == get_team(weapon.player_index)


func can_hit(target: Node, hitbox: Node) -> bool:
	if not is_split():
		return true
	var attacker: = get_attacker_index(hitbox)
	if target is Player:
		if attacker < 0 and is_instance_valid(hitbox.from):
			return get_side(hitbox.from.global_position) == get_team(target.player_index)
		return true
	if attacker >= 0:
		return get_side(target.global_position) == get_team(attacker)
	return true



# Loot (host)

func get_material_receivers(picker: int):
	if not is_split():
		return null
	var receivers: = []
	for player_index in state.teams.size():
		if state.teams[player_index] == get_team(picker):
			receivers.append(player_index)
	return receivers


func shares_crates() -> bool:
	return .shares_crates() if not is_split() else false



# Teams going out and the result (host)

func on_player_died(main: Node, player: Node, _args) -> void :
	if not is_host() or not is_split() or main._cleaning_up:
		return
	var team: = get_team(player.player_index)
	if is_team_out(team):
		return
	for other in main._players:
		if get_team(other.player_index) == team and not other.dead:
			return
	state.out_wave[team] = RunData.current_wave
	mark_dirty()
	ModLoaderLog.info("Team %d is out in wave %d" % [team, RunData.current_wave], "Moolt-Lan_Coop")
	call_deferred("_clear_half", main, team)


func _clear_half(main: Node, team: int) -> void :
	if not is_instance_valid(main) or main._cleaning_up:
		return
	var spawner: Node = main._entity_spawner
	for enemy in spawner.enemies.duplicate() + spawner.bosses.duplicate():
		if is_instance_valid(enemy) and not enemy.dead and get_side(enemy.global_position) == team:
			enemy.can_drop_loot = false
			enemy.die(_quiet_die_args())


func _quiet_die_args() -> Entity.DieArgs:
	var args: = Entity.DieArgs.new()
	args.enemy_killed_by_player = false
	return args


func adjust_run_states(_main: Node, states: Array) -> Array:
	if not is_split() or not (states[0] or states[1] or states[2]):
		return states
	if state.winner_team < 0:
		state.winner_team = _decide_winner()
		mark_dirty()
	return [false, true, false]


# The team that lasted longer (still in beats any out wave), then more kills.
func _decide_winner() -> int:
	var lasted: = []
	var kills: = [0, 0]
	for team in 2:
		lasted.append(Utils.LARGE_NUMBER if state.out_wave[team] == 0 else state.out_wave[team])
	for player_index in get_player_count():
		kills[get_team(player_index)] += get_score(KILLS, player_index)
	if lasted[0] != lasted[1]:
		return 0 if lasted[0] > lasted[1] else 1
	if kills[0] != kills[1]:
		return 0 if kills[0] > kills[1] else 1
	return DRAW



# Scores

func get_score_columns() -> Array:
	return [[KILLS, "LAN_SCORE_KILLS"]] if is_split() else []


func get_rank_key(player_index: int) -> Array:
	var team: = get_team(player_index)
	return [1 if team == state.get("winner_team", - 1) else 0, 1 - team] + .get_rank_key(player_index)


func get_player_note(player_index: int) -> String:
	var team: = get_team(player_index)
	if is_team_out(team):
		return get_team_name(team) + ", " + tr("LAN_NOTE_TEAM_OUT").replace("{0}", str(state.out_wave[team]))
	return get_team_name(team)


func get_banner(main: Node) -> String:
	if not is_split():
		return ""
	var parts: = []
	for team in 2:
		if is_team_out(team):
			parts.append(tr("LAN_TEAM_OUT").replace("{0}", get_team_name(team)))
			continue
		var alive: = 0
		for player in main._players:
			if is_instance_valid(player) and not player.dead and get_team(player.player_index) == team:
				alive += 1
		parts.append(tr("LAN_TEAM_ALIVE").replace("{0}", get_team_name(team)).replace("{1}", str(alive)))
	return PoolStringArray(parts).join("   ·   ")


func get_leader() -> int:
	return - 1


func get_end_title() -> String:
	var winner: int = state.get("winner_team", - 1)
	if winner < 0:
		return ""
	if winner == DRAW:
		return tr("LAN_RESULT_DRAW")
	if winner == get_team(get_local_index()):
		return tr("LAN_TEAM_YOU_WIN")
	return tr("LAN_TEAM_WINS").replace("{0}", get_team_name(winner))


func get_result_text() -> String:
	var winner: int = state.get("winner_team", - 1)
	if winner < 0 or winner == DRAW:
		return tr("LAN_RESULT_DRAW")
	return tr("LAN_TEAM_WINS").replace("{0}", get_team_name(winner))
