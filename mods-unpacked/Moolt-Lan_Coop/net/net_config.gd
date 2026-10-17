extends Reference

# Persistent per-machine settings in user://lan_coop.cfg (last name, last IP, port,
# the zone and difficulty last picked as host).

const CONFIG_PATH: = "user://lan_coop.cfg"
const SECTION: = "lan_coop"
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

var player_name: = ""
var last_ip: = "127.0.0.1"
var port: = NetProtocol.DEFAULT_PORT
var last_zone: = 0
var last_difficulty: = 0


func load_config() -> void :
	var file: = ConfigFile.new()
	if file.load(CONFIG_PATH) == OK:
		player_name = str(file.get_value(SECTION, "player_name", ""))
		last_ip = str(file.get_value(SECTION, "last_ip", last_ip))
		port = int(file.get_value(SECTION, "port", port))
		last_zone = int(file.get_value(SECTION, "last_zone", last_zone))
		last_difficulty = int(file.get_value(SECTION, "last_difficulty", last_difficulty))

	if player_name.empty():
		var rng: = RandomNumberGenerator.new()
		rng.randomize()
		player_name = "Player" + str(rng.randi_range(100, 999))
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
	var _err = file.save(CONFIG_PATH)
