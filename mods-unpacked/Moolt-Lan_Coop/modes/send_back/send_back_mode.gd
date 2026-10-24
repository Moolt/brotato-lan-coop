extends "res://mods-unpacked/Moolt-Lan_Coop/modes/elimination_mode.gd"

# Send-back: endless waves, last one alive wins (elimination_mode.gd), and kills hurt the others.
# Every KILLS_PER_SEND kills a player sends one enemy of the kind they just killed to a random
# other player still in: it appears (with vanilla's spawn marker) SEND_DISTANCE away from them,
# with SENT_HEALTH_FACTOR times its HP. The target gets a toast with the sender's name.
# Scores: kills, sent, received.

const KILLS_PER_SEND: = 5
const SEND_DISTANCE: = 220.0
const SENT_HEALTH_FACTOR: = 1.5
const SENT: = "sent"
const RECEIVED: = "received"
const MSG_SENT: = "sent"

const STRINGS: = {
	"en": {
		"LAN_MODE_SEND_BACK": "Send-back",
		"LAN_MODE_SEND_BACK_DESC": "Endless waves; every 5 kills send an enemy to another player. Whoever dies is out. The last one alive wins.",
		"LAN_SCORE_SENT": "Sent",
		"LAN_SCORE_RECEIVED": "Got",
		"LAN_SENT_BY": "{0} sent you an enemy!",
	},
	"de": {
		"LAN_MODE_SEND_BACK": "Zurückschicken",
		"LAN_MODE_SEND_BACK_DESC": "Endlose Wellen; alle 5 Kills schickst du einem anderen Spieler einen Gegner. Wer stirbt, ist raus. Wer zuletzt lebt, gewinnt.",
		"LAN_SCORE_SENT": "Geschickt",
		"LAN_SCORE_RECEIVED": "Bekommen",
		"LAN_SENT_BY": "{0} hat dir einen Gegner geschickt!",
	},
}

# Host: kills since each player's last send.
var _pending_kills: = {}
var _main: Node = null
var _scene_cache: = {}
# Host: the spawn data that marks a sent enemy (vanilla ignores data for enemies).
var _sent_marker: = Resource.new()


func on_wave_started(main: Node) -> void :
	.on_wave_started(main)
	_main = main


func on_enemy_killed(enemy: Node, killer: int) -> void :
	.on_enemy_killed(enemy, killer)
	if get_player_count() < 2 or not is_instance_valid(_main) or _main._cleaning_up or enemy is Boss:
		return
	_pending_kills[killer] = _pending_kills.get(killer, 0) + 1
	if _pending_kills[killer] < KILLS_PER_SEND:
		return
	_pending_kills[killer] = 0
	var targets: = []
	for player_index in get_players_in():
		var player = _main._players[player_index]
		if player_index != killer and is_instance_valid(player) and not player.dead:
			targets.append(player_index)
	if targets.empty() or enemy.filename.empty():
		return
	var target: int = Utils.get_rand_element(targets)
	_send(enemy.filename, killer, target)


func _send(scene_path: String, sender: int, target: int) -> void :
	if not _scene_cache.has(scene_path):
		_scene_cache[scene_path] = load(scene_path)
	var scene = _scene_cache[scene_path]
	if not scene is PackedScene:
		return
	var player = _main._players[target]
	var rect: Rect2 = ZoneService.get_current_zone_rect().grow( - Utils.EDGE_MAP_DIST)
	var pos: Vector2 = player.global_position + Vector2(SEND_DISTANCE, 0).rotated(rand_range( - PI, PI))
	pos = Vector2(clamp(pos.x, rect.position.x, rect.end.x), clamp(pos.y, rect.position.y, rect.end.y))
	# As a summon: through vanilla's spawn marker. Its data marks it as sent (on_entity_spawned).
	_main._entity_spawner.queue_to_spawn_summons.push_back([EntityType.ENEMY, scene, pos, _sent_marker])
	add_score(SENT, sender, 1)
	add_score(RECEIVED, target, 1)
	send_message_to(target, [MSG_SENT, sender])


func on_entity_spawned(entity: Node, data) -> void :
	if data == _sent_marker and entity is Enemy and entity.max_stats.health > 0:
		entity.max_stats.health = int(entity.max_stats.health * SENT_HEALTH_FACTOR)
		entity.current_stats.health = entity.max_stats.health


func on_message(_from_index: int, payload: Array) -> void :
	if payload.size() == 2 and payload[0] == MSG_SENT and typeof(payload[1]) == TYPE_INT and is_instance_valid(_main):
		var scoreboard = _main.get_node_or_null("UI/HUD/" + SCOREBOARD_NAME)
		if scoreboard != null:
			scoreboard.show_toast(tr("LAN_SENT_BY").replace("{0}", get_player_name(payload[1])))


func get_score_columns() -> Array:
	return [[KILLS, "LAN_SCORE_KILLS"], [SENT, "LAN_SCORE_SENT"], [RECEIVED, "LAN_SCORE_RECEIVED"]]
