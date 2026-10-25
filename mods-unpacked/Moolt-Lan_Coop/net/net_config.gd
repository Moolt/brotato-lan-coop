extends Reference

# Persistent per-machine settings in user://lan_coop.cfg (last name, last IP, port,
# the zone, difficulty, choice time, scaling preset and game mode last picked as host) and, in its own section, the arena and enemy
# scaling knobs used when hosting (NetProtocol.DEFAULT_SCALING). rejoin_token is what the last
# host gave this machine (NetProtocol.build_hello); saved, so a restarted game can rejoin a run.

const CONFIG_PATH: = "user://lan_coop.cfg"
const SECTION: = "lan_coop"
const SCALING_SECTION: = "scaling"
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

# Picked at random until the player sets a name (at most 14 characters, so the host's " 2"
# suffix for a taken name fits NetProtocol.MAX_NAME_LENGTH).
const DEFAULT_NAMES: = [
	"Spud Lightyear", "Tater Tot", "Mashed Menace", "Couch Potato", "Hash Brown", "Sir Fries",
	"Baked Brawler", "Spudnik", "Jacket Potato", "Captain Mash", "Wedge Wizard", "Chip Shot",
	"Alien Snack", "Peel Deal", "Gravy Train", "Spud Bud",
]

var player_name: = ""
var last_ip: = "127.0.0.1"
var port: = NetProtocol.DEFAULT_PORT
var last_zone: = 0
var last_difficulty: = 0
var last_choice_time: = NetProtocol.DEFAULT_CHOICE_TIME
var last_scaling_preset: = NetProtocol.SCALING_PRESET_NORMAL
var last_mode: = NetProtocol.DEFAULT_MODE
var last_share_materials: = true
var last_share_crates: = true
# The in-wave scoreboard of modes with scores (toggled with Tab or the gamepad's Back button).
var show_scoreboard: = true
var scaling: = NetProtocol.DEFAULT_SCALING.duplicate()
var rejoin_token: = 0


func load_config() -> void :
	var file: = ConfigFile.new()
	if file.load(CONFIG_PATH) == OK:
		player_name = str(file.get_value(SECTION, "player_name", ""))
		last_ip = str(file.get_value(SECTION, "last_ip", last_ip))
		port = int(file.get_value(SECTION, "port", port))
		last_zone = int(file.get_value(SECTION, "last_zone", last_zone))
		last_difficulty = int(file.get_value(SECTION, "last_difficulty", last_difficulty))
		last_choice_time = int(file.get_value(SECTION, "last_choice_time", last_choice_time))
		last_scaling_preset = int(file.get_value(SECTION, "last_scaling_preset", last_scaling_preset))
		last_mode = str(file.get_value(SECTION, "last_mode", last_mode))
		last_share_materials = bool(file.get_value(SECTION, "last_share_materials", last_share_materials))
		last_share_crates = bool(file.get_value(SECTION, "last_share_crates", last_share_crates))
		show_scoreboard = bool(file.get_value(SECTION, "show_scoreboard", show_scoreboard))
		rejoin_token = int(file.get_value(SECTION, "rejoin_token", rejoin_token))
		for key in scaling:
			scaling[key] = clamp(float(file.get_value(SCALING_SECTION, key, scaling[key])), 0.0, NetProtocol.MAX_SCALING_VALUE)

	# Earlier versions picked "Player" and three digits.
	if player_name.empty() or _is_old_default_name(player_name):
		var rng: = RandomNumberGenerator.new()
		rng.randomize()
		player_name = DEFAULT_NAMES[rng.randi_range(0, DEFAULT_NAMES.size() - 1)]
		save_config()

	if port <= 0 or port > 65535:
		port = NetProtocol.DEFAULT_PORT


func save_config() -> void :
	var file: = ConfigFile.new()
	file.set_value(SECTION, "player_name", player_name)
	file.set_value(SECTION, "last_ip", last_ip)
	file.set_value(SECTION, "port", port)
	file.set_value(SECTION, "last_zone", last_zone)
	file.set_value(SECTION, "last_difficulty", last_difficulty)
	file.set_value(SECTION, "last_choice_time", last_choice_time)
	file.set_value(SECTION, "last_scaling_preset", last_scaling_preset)
	file.set_value(SECTION, "last_mode", last_mode)
	file.set_value(SECTION, "last_share_materials", last_share_materials)
	file.set_value(SECTION, "last_share_crates", last_share_crates)
	file.set_value(SECTION, "show_scoreboard", show_scoreboard)
	file.set_value(SECTION, "rejoin_token", rejoin_token)
	for key in scaling:
		file.set_value(SCALING_SECTION, key, scaling[key])
	var _err = file.save(CONFIG_PATH)


static func _is_old_default_name(name: String) -> bool:
	return name.length() == 9 and name.begins_with("Player") and name.right(6).is_valid_integer()
