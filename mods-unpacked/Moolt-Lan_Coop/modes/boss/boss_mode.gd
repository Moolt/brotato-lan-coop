extends "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd"

# Boss player: every wave the host picks a random player (not the last boss, if there is a
# choice) as the boss: BOSS_HP_PER_OPPONENT times their max HP more per other player, plus
# BOSS_DAMAGE_BONUS % damage, bigger and tinted. The wave's enemies fight for the boss: they chase
# only the others and can't hurt the boss, and the boss can't hurt them. Players' weapons aim at
# and hit the other side (PvP: weapon ranges see players, player hurtboxes take player hits);
# hits between players deal PVP_DAMAGE_FACTOR of their damage, except on the boss.
# The others win the round by killing the boss; the boss wins by surviving the wave or when
# everyone else is dead. Either ends the wave at once; players revive at the next wave as in
# co-op, and dying together never loses the run. Scores: rounds won as boss, boss kills (final
# blow), kills. With one player it is plain co-op.
# Balance needs playtesting: the factors are the knobs.

const BOSS_HP_PER_OPPONENT: = 6.0
const BOSS_DAMAGE_BONUS: = 25
const PVP_DAMAGE_FACTOR: = 0.35
const BOSS_SCALE: = 1.35
const BOSS_TINT: = Color(1.0, 0.7, 0.7)
const BOSS_WINS: = "boss_wins"
const BOSS_KILLS: = "boss_kills"
const BOSS_ICON = preload("res://ui/icons/misc/boss_icon.png")
const BOSS_WINS_ICON = preload("res://items/all/hunting_trophy/hunting_trophy_icon.png")

const STRINGS: = {
	"en": {
		"LAN_MODE_BOSS": "Boss player",
		"LAN_MODE_BOSS_DESC": "Each wave one random player is the boss: huge HP, and the enemies fight for them. Everyone else teams up to take the boss down. The boss wins by surviving the wave.",
		"LAN_SCORE_BOSS_WINS": "Boss wins",
		"LAN_SCORE_BOSS_KILLS": "Boss kills",
		"LAN_BOSS_YOU": "You are the boss! Survive the wave.",
		"LAN_BOSS_OTHER": "{0} is the boss! Take them down.",
		"LAN_BOSS_DOWN": "The boss is down!",
		"LAN_BOSS_WON": "The boss wins this round!",
	},
	"de": {
		"LAN_MODE_BOSS": "Boss-Spieler",
		"LAN_MODE_BOSS_DESC": "In jeder Welle ist ein zufälliger Spieler der Boss: riesige LP, und die Gegner kämpfen für ihn. Alle anderen tun sich zusammen, um den Boss zu besiegen. Der Boss gewinnt, wenn er die Welle übersteht.",
		"LAN_SCORE_BOSS_WINS": "Boss-Siege",
		"LAN_SCORE_BOSS_KILLS": "Boss besiegt",
		"LAN_BOSS_YOU": "Du bist der Boss! Überstehe die Welle.",
		"LAN_BOSS_OTHER": "{0} ist der Boss! Besiegt ihn.",
		"LAN_BOSS_DOWN": "Der Boss ist besiegt!",
		"LAN_BOSS_WON": "Der Boss gewinnt diese Runde!",
	},
}

var _main: Node = null
# Host: who hit each player last (player index -> attacker index), for the boss kill.
var _last_attacker: = {}


func start(players: Array) -> void :
	.start(players)
	state.boss = - 1
	# The round's result: 0 running, 1 the boss is down, 2 the boss won.
	state.round_result = 0


func uses_pvp() -> bool:
	return get_player_count() >= 2


func get_boss() -> int:
	return state.get("boss", - 1) if uses_pvp() else - 1


func on_wave_started(main: Node) -> void :
	_main = main
	if is_host() and uses_pvp():
		_pick_boss(main)
	.on_wave_started(main)
	_apply_boss_look()


func _pick_boss(main: Node) -> void :
	var candidates: = []
	for entry in net.players:
		if entry.connected and entry.player_index < main._players.size():
			candidates.append(entry.player_index)
	if candidates.size() > 1:
		candidates.erase(state.boss)
	var boss: int = Utils.get_rand_element(candidates) if not candidates.empty() else - 1
	state.boss = boss
	state.round_result = 0
	_last_attacker = {}
	mark_dirty()
	if boss < 0:
		return
	var player = main._players[boss]
	var opponents: int = int(max(1, get_player_count() - 1))
	TempStats.add_stat(Keys.stat_max_hp_hash, int(player.max_stats.health * BOSS_HP_PER_OPPONENT * opponents), boss)
	TempStats.add_stat(Keys.stat_percent_damage_hash, BOSS_DAMAGE_BONUS, boss)
	player.update_player_stats(true)
	ModLoaderLog.info("Boss of wave %d: player %d (%d HP)" % [RunData.current_wave, boss, player.max_stats.health], "Moolt-Lan_Coop")


func set_state(new_state: Dictionary) -> void :
	.set_state(new_state)
	_apply_boss_look()


func _apply_boss_look() -> void :
	if not is_instance_valid(_main) or _main._cleaning_up:
		return
	for player in _main._players:
		if is_instance_valid(player):
			var is_boss: bool = player.player_index == get_boss()
			player.scale = Vector2(BOSS_SCALE, BOSS_SCALE) if is_boss else Vector2.ONE
			player.modulate = BOSS_TINT if is_boss else Color.white



# Combat (host)

func can_target(weapon: Node, body: Node) -> bool:
	var boss: = get_boss()
	if boss < 0:
		return true
	var owner_is_boss: bool = weapon.player_index == boss
	if body is Player:
		return body.player_index != weapon.player_index and (body.player_index == boss) != owner_is_boss
	if body is Enemy:
		return not owner_is_boss
	return true


func can_hit(target: Node, hitbox: Node) -> bool:
	var boss: = get_boss()
	if boss < 0:
		return true
	var attacker: = get_attacker_index(hitbox)
	if target is Player:
		if attacker < 0:
			# Enemies fight for the boss; a player hit without a known owner hurts nobody.
			return target.player_index != boss and not (hitbox.collision_layer & Utils.PLAYER_PROJECTILES_BIT)
		var allowed: bool = attacker != target.player_index and (attacker == boss) != (target.player_index == boss)
		if allowed:
			_last_attacker[target.player_index] = attacker
		return allowed
	if target is Enemy:
		return attacker != boss
	return true


func scale_player_damage(target: Node, value: int, args) -> int:
	if get_boss() < 0 or target.player_index == get_boss() or args == null or args.hitbox == null:
		return value
	if get_attacker_index(args.hitbox) >= 0:
		return int(max(1.0, round(value * PVP_DAMAGE_FACTOR)))
	return value


func get_enemy_targets(_enemy: Node, players: Array):
	var boss: = get_boss()
	if boss < 0:
		return null
	var targets: = []
	for player in players:
		if player.player_index != boss:
			targets.append(player)
	return targets


func on_player_died(main: Node, player: Node, _args) -> void :
	var boss: = get_boss()
	if not is_host() or boss < 0 or main._cleaning_up or state.round_result != 0:
		return
	if player.player_index == boss:
		state.round_result = 1
		var killer: int = _last_attacker.get(boss, - 1)
		if killer >= 0:
			add_score(BOSS_KILLS, killer, 1)
	else:
		for other in main._players:
			if other.player_index != boss and not other.dead:
				return
		state.round_result = 2
		add_score(BOSS_WINS, boss, 1)
	mark_dirty()
	main.call_deferred("lan_end_wave_now")


# The wave ran out with the boss alive: the boss wins. Everyone dead (boss included) never loses
# the run here.
func adjust_run_states(main: Node, states: Array) -> Array:
	if get_boss() < 0:
		return states
	if state.round_result == 0:
		var boss_alive: bool = is_instance_valid(main._players[get_boss()]) and not main._players[get_boss()].dead
		state.round_result = 2 if boss_alive else 1
		if boss_alive:
			add_score(BOSS_WINS, get_boss(), 1)
		mark_dirty()
	if states[0]:
		return [false, false, RunData.current_wave >= RunData.nb_of_waves]
	return states



# Scores

func get_score_columns() -> Array:
	return [[BOSS_WINS, "LAN_SCORE_BOSS_WINS", BOSS_WINS_ICON], [BOSS_KILLS, "LAN_SCORE_BOSS_KILLS", BOSS_ICON], [KILLS, "LAN_SCORE_KILLS", KILLS_ICON]]


func get_player_status(player_index: int) -> Dictionary:
	return {"icon": BOSS_ICON} if player_index == get_boss() and is_instance_valid(_main) and not _main._cleaning_up else {}


func get_banner(_main_node: Node) -> String:
	var boss: = get_boss()
	if boss < 0:
		return ""
	match int(state.get("round_result", 0)):
		1:
			return tr("LAN_BOSS_DOWN")
		2:
			return tr("LAN_BOSS_WON")
	if boss == get_local_index():
		return tr("LAN_BOSS_YOU")
	return tr("LAN_BOSS_OTHER").replace("{0}", get_player_name(boss))
