extends Reference

# Every game mode the lobby offers (lobby_settings.mode is the id). A mode is a script in its own
# folder under modes/ that extends modes/lan_mode.gd (or another mode); its texts are in its
# STRINGS constant ({locale: {key: text}}), registered at startup with register_translations.

const DEFAULT: = "coop"
# Modes with teams: team 0 and 1 (lobby entry "team"), their colours and names.
const TEAM_COLORS: = [Color(1.0, 0.4, 0.35), Color(0.4, 0.6, 1.0)]
const TEAM_NAMES: = ["LAN_TEAM_A", "LAN_TEAM_B"]

# id, script, name and description keys; teams: players pick one of two teams in the lobby.
const MODES: = [
	{"id": "coop", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/lan_mode.gd", "name": "LAN_MODE_COOP", "description": "LAN_MODE_COOP_DESC", "teams": false},
	{"id": "last_potato", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/last_potato/last_potato_mode.gd", "name": "LAN_MODE_LAST_POTATO", "description": "LAN_MODE_LAST_POTATO_DESC", "teams": false},
	{"id": "send_back", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/send_back/send_back_mode.gd", "name": "LAN_MODE_SEND_BACK", "description": "LAN_MODE_SEND_BACK_DESC", "teams": false},
	{"id": "draft", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/draft/draft_mode.gd", "name": "LAN_MODE_DRAFT", "description": "LAN_MODE_DRAFT_DESC", "teams": false},
	{"id": "hill", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/king_of_the_hill/hill_mode.gd", "name": "LAN_MODE_HILL", "description": "LAN_MODE_HILL_DESC", "teams": false},
	{"id": "boss", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/boss/boss_mode.gd", "name": "LAN_MODE_BOSS", "description": "LAN_MODE_BOSS_DESC", "teams": false},
	{"id": "gold_rush", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/gold_rush/gold_rush_mode.gd", "name": "LAN_MODE_GOLD_RUSH", "description": "LAN_MODE_GOLD_RUSH_DESC", "teams": false},
	{"id": "team_race", "script": "res://mods-unpacked/Moolt-Lan_Coop/modes/team_race/team_race_mode.gd", "name": "LAN_MODE_TEAM_RACE", "description": "LAN_MODE_TEAM_RACE_DESC", "teams": true},
]

# Texts shared by all modes (scoreboard, results, lobby).
const STRINGS: = {
	"en": {
		"LAN_SETTING_MODE": "Mode",
		"LAN_MODE_COOP": "Co-op",
		"LAN_MODE_COOP_DESC": "Everyone against the waves, as in vanilla co-op.",
		"LAN_SCORE_KILLS": "Kills",
		"LAN_RESULT_WINNER": "Winner: {0}",
		"LAN_RESULT_DRAW": "Nobody wins",
		"LAN_END_YOU_WIN": "You win!",
		"LAN_END_YOU_LOSE": "{0} wins",
		"LAN_TEAM": "Team",
		"LAN_TEAM_A": "Team Red",
		"LAN_TEAM_B": "Team Blue",
		"LAN_SWITCH_TEAM": "Switch team",
		"LAN_NOTE_OUT": "out",
		"LAN_NOTE_OUT_WAVE": "out in wave {0}",
		"LAN_ELIM_LEFT": "{0} potatoes left",
		"LAN_ELIM_YOU_ARE_OUT": "You are out. Watching the others...",
	},
	"de": {
		"LAN_SETTING_MODE": "Modus",
		"LAN_MODE_COOP": "Koop",
		"LAN_MODE_COOP_DESC": "Alle gegen die Wellen, wie im normalen Koop.",
		"LAN_SCORE_KILLS": "Kills",
		"LAN_RESULT_WINNER": "Sieger: {0}",
		"LAN_RESULT_DRAW": "Niemand gewinnt",
		"LAN_END_YOU_WIN": "Du gewinnst!",
		"LAN_END_YOU_LOSE": "{0} gewinnt",
		"LAN_TEAM": "Team",
		"LAN_TEAM_A": "Team Rot",
		"LAN_TEAM_B": "Team Blau",
		"LAN_SWITCH_TEAM": "Team wechseln",
		"LAN_NOTE_OUT": "raus",
		"LAN_NOTE_OUT_WAVE": "raus in Welle {0}",
		"LAN_ELIM_LEFT": "Noch {0} Kartoffeln übrig",
		"LAN_ELIM_YOU_ARE_OUT": "Du bist raus. Du schaust den anderen zu...",
	},
}


static func is_valid(mode_id) -> bool:
	return typeof(mode_id) == TYPE_STRING and get_info(mode_id) != null


static func get_info(mode_id: String):
	for info in MODES:
		if info.id == mode_id:
			return info
	return null


static func uses_teams(mode_id: String) -> bool:
	var info = get_info(mode_id)
	return info != null and info.teams


static func get_name_key(mode_id: String) -> String:
	var info = get_info(mode_id)
	return info.name if info != null else "?"


static func get_description_key(mode_id: String) -> String:
	var info = get_info(mode_id)
	return info.description if info != null else ""


# A new instance of the mode (the co-op base for an unknown id).
static func create(mode_id: String, net: Node) -> Reference:
	var info = get_info(mode_id)
	if info == null:
		info = get_info(DEFAULT)
	var mode: Reference = load(info.script).new()
	mode.setup(net, info.id)
	return mode


static func register_translations() -> void :
	var tables: = [STRINGS]
	for info in MODES:
		var constants: Dictionary = load(info.script).get_script_constant_map()
		var own = constants.get("STRINGS")
		# Subclasses see their parent's constants: register each table once.
		if typeof(own) == TYPE_DICTIONARY and not tables.has(own):
			tables.append(own)
	for table in tables:
		for locale in table:
			var translation: = Translation.new()
			translation.locale = locale
			for key in table[locale]:
				translation.add_message(key, table[locale][key])
			TranslationServer.add_translation(translation)
