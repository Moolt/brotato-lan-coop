extends "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd"

# Gold Rush: co-op waves, but loot isn't shared. Materials (and their XP) and crates go to the
# player who picks them up. A player who dies drops DEATH_DROP_SHARE of their materials where
# they fell, for anyone to grab. Whoever collected the most materials over the run wins
# (collected counts pickups, also of dropped materials; spending doesn't lower it).

const DEATH_DROP_SHARE: = 0.5
const DEATH_DROP_SPREAD: = 100
const MATERIALS: = "materials"
const DROPPED: = "dropped"

const STRINGS: = {
	"en": {
		"LAN_MODE_GOLD_RUSH": "Gold Rush",
		"LAN_MODE_GOLD_RUSH_DESC": "Co-op waves, but every material and crate belongs to whoever picks it up. Dying drops half your materials for the others. Whoever collects the most wins.",
		"LAN_SCORE_MATERIALS": "Collected",
		"LAN_SCORE_DROPPED": "Dropped",
		"LAN_GOLD_RUSH_LEADER": "{0} leads the gold rush",
		"LAN_GOLD_RUSH_YOU_LEAD": "You lead the gold rush!",
	},
	"de": {
		"LAN_MODE_GOLD_RUSH": "Goldrausch",
		"LAN_MODE_GOLD_RUSH_DESC": "Koop-Wellen, aber jedes Material und jede Kiste gehört dem, der sie aufsammelt. Wer stirbt, verliert die Hälfte seiner Materialien an die anderen. Wer am meisten sammelt, gewinnt.",
		"LAN_SCORE_MATERIALS": "Gesammelt",
		"LAN_SCORE_DROPPED": "Verloren",
		"LAN_GOLD_RUSH_LEADER": "{0} führt im Goldrausch",
		"LAN_GOLD_RUSH_YOU_LEAD": "Du führst im Goldrausch!",
	},
}


func get_material_receivers(picker: int):
	return [picker]


func shares_crates() -> bool:
	return false


func on_materials_collected(player_index: int, value: float) -> void :
	add_score(MATERIALS, player_index, int(round(value)))


func on_player_died(main: Node, player: Node, _args) -> void :
	if not is_host() or main._cleaning_up:
		return
	var player_index: int = player.player_index
	var amount: = int(RunData.get_player_gold(player_index) * DEATH_DROP_SHARE)
	if amount <= 0:
		return
	RunData.remove_gold(amount, player_index)
	add_score(DROPPED, player_index, amount)
	main.spawn_gold(amount, player.global_position, DEATH_DROP_SPREAD)


func get_score_columns() -> Array:
	return [[MATERIALS, "LAN_SCORE_MATERIALS"], [KILLS, "LAN_SCORE_KILLS"], [DROPPED, "LAN_SCORE_DROPPED"]]


func get_rank_key(player_index: int) -> Array:
	return [get_score(MATERIALS, player_index), get_score(KILLS, player_index)]


func get_banner(_main: Node) -> String:
	var leader: = get_leader()
	if leader < 0:
		return ""
	return tr("LAN_GOLD_RUSH_YOU_LEAD") if leader == get_local_index() else tr("LAN_GOLD_RUSH_LEADER").replace("{0}", get_player_name(leader))
