extends Reference

# Shared constants and helpers for the LAN coop protocol.
# Bump PROTOCOL_VERSION whenever an RPC signature or message layout changes.

const MOD_ID: = "Moolt-Lan_Coop"
const PROTOCOL_VERSION: = 20

const DEFAULT_PORT: = 24567
const DISCOVERY_PORT: = DEFAULT_PORT + 1
const BEACON_MAGIC: = "BROTATO_LAN_COOP"
const MAX_BEACON_SIZE: = 1024
const MAX_PLAYERS: = 12
const MAX_CLIENTS: = MAX_PLAYERS - 1
const MAX_NAME_LENGTH: = 16
const HELLO_TIMEOUT: = 5.0
const KICK_DELAY: = 0.5
# A client that lost the connection during a run tries to rejoin its old slot every
# RECONNECT_INTERVAL seconds (after each failed attempt) for RECONNECT_TIME seconds.
const RECONNECT_TIME: = 60.0
const RECONNECT_INTERVAL: = 2.0

# Reject / disconnect reasons. They double as translation keys (see net_translations.gd).
const REJECT_VERSION: = "LAN_REJECT_VERSION"
const REJECT_GAME_VERSION: = "LAN_REJECT_GAME_VERSION"
const REJECT_DLC: = "LAN_REJECT_DLC"
const REJECT_FULL: = "LAN_REJECT_FULL"
const REJECT_IN_PROGRESS: = "LAN_REJECT_IN_PROGRESS"
const REJECT_BAD_HELLO: = "LAN_REJECT_BAD_HELLO"
const MSG_HOST_LEFT: = "LAN_MSG_HOST_LEFT"
const MSG_CONNECTION_FAILED: = "LAN_MSG_CONNECTION_FAILED"
const MSG_RECONNECTING: = "LAN_MSG_RECONNECTING"
const MSG_RECONNECT_FAILED: = "LAN_MSG_RECONNECT_FAILED"
const MSG_SERVER_FAILED: = "LAN_MSG_SERVER_FAILED"
const MSG_INVALID_IP: = "LAN_MSG_INVALID_IP"
const MSG_INVALID_PORT: = "LAN_MSG_INVALID_PORT"

# Arena and enemy scaling knobs. The host reads them from its config (net_config.gd) and sends
# them in lobby_settings.scaling, so every peer builds the same arena. Values are per extra
# player; see LanGame for the formulas. Vanilla coop: enemies 0.3, HP 0.3, damage 0.08,
# cap 0.125, no arena growth.
const DEFAULT_SCALING: = {
	"arena_area_per_player": 0.25, 
	"enemy_count_per_player": 0.3, 
	"enemy_health_per_player": 0.3, 
	"enemy_health_per_player_beyond_4": 0.2, 
	"enemy_damage_per_player": 0.08, 
	"enemy_cap_per_player": 0.25, 
}
const MAX_SCALING_VALUE: = 2.0
# Enemy scaling presets on the lobby's settings page (lobby_settings.scaling_preset is the
# index): factors on the config's per-player enemy knobs (SCALED_BY_PRESET); the arena and the
# enemy cap stay. Normal is the config as it is.
const SCALING_PRESET_RELAXED: = 0
const SCALING_PRESET_NORMAL: = 1
const SCALING_PRESET_TOUGH: = 2
const SCALING_PRESET_FACTORS: = [0.6, 1.0, 1.5]
const SCALING_PRESET_KEYS: = ["LAN_SCALING_RELAXED", "LAN_SCALING_NORMAL", "LAN_SCALING_TOUGH"]
const SCALED_BY_PRESET: = [
	"enemy_count_per_player", 
	"enemy_health_per_player", 
	"enemy_health_per_player_beyond_4", 
	"enemy_damage_per_player", 
]

# Seconds every player has between waves for level-ups, crates and the shop
# (lobby_settings.choice_time, 0 = no limit); then the game picks and presses Go itself. The host
# waits CHOICE_GRACE more seconds for late results and goes on without them.
const DEFAULT_CHOICE_TIME: = 90
# The choices the host has in the lobby's settings page.
const CHOICE_TIMES: = [0, 45, 60, 90, 120]
const CHOICE_GRACE: = 10.0

# Keys a client may change on its own lobby entry.
const PLAYER_EDITABLE_KEYS: = ["character_id", "weapon_id", "ready"]

# ProgressData arrays replaced by get_multiplayer_unlocks() while a session is active.
const UNLOCK_KEYS: = [
	"zones_unlocked", 
	"characters_unlocked", 
	"upgrades_unlocked", 
	"consumables_unlocked", 
	"weapons_unlocked", 
	"items_unlocked", 
]


static func get_mod_version() -> String:
	if ModLoaderStore.mod_data.has(MOD_ID):
		return ModLoaderStore.mod_data[MOD_ID].manifest.version_number
	return "0.0.0"


static func get_sorted_dlc_ids() -> Array:
	var ids: Array = ProgressData.get_active_dlc_ids().duplicate()
	ids.sort()
	return ids


# rejoin_token: what the host gave this machine at its last welcome (0 = none). During a run the
# host gives the player with that token its old slot back.
static func build_hello(player_name: String, rejoin_token: int) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION, 
		"mod_version": get_mod_version(), 
		"game_version": ProgressData.VERSION, 
		"dlcs": get_sorted_dlc_ids(), 
		"name": player_name, 
		"rejoin_token": rejoin_token, 
	}


# Returns "" if the hello is acceptable, otherwise a reject reason.
static func validate_hello(hello) -> String:
	if typeof(hello) != TYPE_DICTIONARY:
		return REJECT_BAD_HELLO
	for key in ["protocol_version", "mod_version", "game_version", "dlcs", "name", "rejoin_token"]:
		if not hello.has(key):
			return REJECT_BAD_HELLO
	if typeof(hello.dlcs) != TYPE_ARRAY or typeof(hello.name) != TYPE_STRING or typeof(hello.rejoin_token) != TYPE_INT:
		return REJECT_BAD_HELLO
	if hello.protocol_version != PROTOCOL_VERSION or hello.mod_version != get_mod_version():
		return REJECT_VERSION
	if hello.game_version != ProgressData.VERSION:
		return REJECT_GAME_VERSION
	var their_dlcs: Array = hello.dlcs.duplicate()
	their_dlcs.sort()
	if their_dlcs != get_sorted_dlc_ids():
		return REJECT_DLC
	return ""


static func sanitize_name(raw_name) -> String:
	if typeof(raw_name) != TYPE_STRING:
		return "Player"
	var clean: String = raw_name.strip_edges().strip_escapes()
	if clean.length() > MAX_NAME_LENGTH:
		clean = clean.left(MAX_NAME_LENGTH)
	if clean.empty():
		return "Player"
	return clean


# The name, or with " 2", " 3", ... appended if a name in taken_names has it already (any case).
static func make_unique_name(player_name: String, taken_names: Array) -> String:
	var taken: = []
	for taken_name in taken_names:
		taken.append(str(taken_name).to_lower())
	var result: = player_name
	var number: = 2
	while taken.has(result.to_lower()):
		var suffix: = " " + str(number)
		result = player_name.left(MAX_NAME_LENGTH - suffix.length()).strip_edges() + suffix
		number += 1
	return result


static func new_player_entry(peer_id: int, player_index: int, player_name: String) -> Dictionary:
	return {
		"peer_id": peer_id, 
		"player_index": player_index, 
		"name": player_name, 
		"character_id": "", 
		"weapon_id": "", 
		"ready": false, 
		"connected": true, 
	}


static func default_lobby_settings() -> Dictionary:
	return {
		"zone": 0, 
		"difficulty": 0, 
		"run_id": 0, 
		"in_wave": false, 
		"run_over": false, 
		"scaling": DEFAULT_SCALING.duplicate(), 
		"choice_time": DEFAULT_CHOICE_TIME, 
		"scaling_preset": SCALING_PRESET_NORMAL, 
	}


static func get_unlocks_snapshot() -> Dictionary:
	var unlocks: = {}
	for key in UNLOCK_KEYS:
		unlocks[key] = ProgressData.get(key).duplicate()
	return unlocks


# Everything unlocked, so multiplayer doesn't depend on anyone's save progress. Built from the
# loaded game data (same on every peer: the handshake checks game version and DLCs), with the
# same hashes as ProgressData.add_unlocked_by_default. Consumables follow vanilla's unlock-all
# save, which only enables the default ones.
static func get_multiplayer_unlocks() -> Dictionary:
	var unlocks: = {}
	for key in UNLOCK_KEYS:
		unlocks[key] = []
	for zone in ZoneService.zones:
		unlocks.zones_unlocked.append(zone.my_id)
	for character in ItemService.characters:
		unlocks.characters_unlocked.append(character.my_id_hash)
	for upgrade in ItemService.upgrades:
		if not unlocks.upgrades_unlocked.has(upgrade.upgrade_id_hash):
			unlocks.upgrades_unlocked.append(upgrade.upgrade_id_hash)
	for consumable in ItemService.consumables:
		if consumable.unlocked_by_default:
			unlocks.consumables_unlocked.append(consumable.my_id_hash)
	for weapon in ItemService.weapons:
		if not unlocks.weapons_unlocked.has(weapon.weapon_id_hash):
			unlocks.weapons_unlocked.append(weapon.weapon_id_hash)
	for item in ItemService.items:
		unlocks.items_unlocked.append(item.my_id_hash)
	return unlocks


# LAN discovery beacon, sent by the host as UTF-8 JSON (see net_discovery.gd).
static func build_beacon(host_name: String, port: int, player_count: int) -> PoolByteArray:
	return to_json({
		"magic": BEACON_MAGIC, 
		"protocol_version": PROTOCOL_VERSION, 
		"mod_version": get_mod_version(), 
		"game_version": ProgressData.VERSION, 
		"name": host_name, 
		"port": port, 
		"players": player_count, 
		"max_players": MAX_PLAYERS, 
	}).to_utf8()


# Returns the beacon as a Dictionary (with "compatible" added), or null if it is not one.
static func parse_beacon(bytes: PoolByteArray):
	if bytes.size() > MAX_BEACON_SIZE:
		return null
	var parsed: = JSON.parse(bytes.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return null
	var beacon: Dictionary = parsed.result
	# Check types before comparing: comparing a String to a number is a script error.
	for key in ["protocol_version", "port", "players", "max_players"]:
		if typeof(beacon.get(key)) != TYPE_REAL:
			return null
	for key in ["magic", "mod_version", "game_version", "name"]:
		if typeof(beacon.get(key)) != TYPE_STRING:
			return null
	if beacon.magic != BEACON_MAGIC:
		return null

	var port: = int(beacon.port)
	if port <= 0 or port > 65535:
		return null
	return {
		"name": sanitize_name(beacon.name), 
		"port": port, 
		"players": int(beacon.players), 
		"max_players": int(beacon.max_players), 
		"compatible": int(beacon.protocol_version) == PROTOCOL_VERSION and beacon.mod_version == get_mod_version() and beacon.game_version == ProgressData.VERSION, 
	}


# Parses "ip" or "ip:port". Returns {ip, port} or {error} (a translation key).
static func parse_address(text: String, default_port: int) -> Dictionary:
	var parts: = text.strip_edges().split(":")
	if parts.size() > 2:
		return {"error": MSG_INVALID_IP}
	var ip: String = parts[0].strip_edges()
	if not ip.is_valid_ip_address():
		return {"error": MSG_INVALID_IP}
	var port: = default_port
	if parts.size() == 2:
		var port_text: String = parts[1].strip_edges()
		if not port_text.is_valid_integer() or int(port_text) <= 0 or int(port_text) > 65535:
			return {"error": MSG_INVALID_PORT}
		port = int(port_text)
	return {"ip": ip, "port": port}


# IPv4 addresses other machines can use to reach this one
# (no loopback, no link-local, no container/VM bridges).
static func get_lan_addresses() -> Array:
	var result: = []
	for candidate in _get_address_candidates():
		if not result.has(candidate.address):
			result.append(candidate.address)
	result.sort()
	return result


# The single address shown to other players: private LAN addresses first, wired before
# wireless, then anything else (e.g. a VPN). "" if there is none.
static func get_primary_lan_address() -> String:
	var best: = ""
	var best_score: = - 1
	for candidate in _get_address_candidates():
		var score: = 0
		if _is_private_address(candidate.address):
			score += 4
		var interface_name: String = candidate.interface
		if interface_name.begins_with("en") or interface_name.begins_with("eth") or "ethernet" in interface_name:
			score += 2
		elif interface_name.begins_with("wl") or "wi-fi" in interface_name or "wireless" in interface_name:
			score += 1
		if score > best_score:
			best_score = score
			best = candidate.address
	return best


# [{address, interface}] for every usable IPv4 address. interface is the lowercased
# name (Linux) or friendly name (Windows).
static func _get_address_candidates() -> Array:
	var result: = []
	for interface in IP.get_local_interfaces():
		var interface_name: = str(interface.get("friendly", "")).to_lower()
		if interface_name.empty():
			interface_name = str(interface.get("name", "")).to_lower()
		if _is_virtual_interface(interface_name) or _is_virtual_interface(str(interface.get("name", "")).to_lower()):
			continue
		for address in interface.addresses:
			if not address.is_valid_ip_address() or ":" in address:
				continue
			if address.begins_with("127.") or address.begins_with("169.254."):
				continue
			result.append({"address": address, "interface": interface_name})
	return result


# Where the host sends beacons: the limited broadcast (Linux only uses the default interface for it)
# plus the /24 broadcast of every private LAN address. Interface netmasks aren't exposed in Godot 3.
static func get_broadcast_addresses() -> Array:
	var result: = ["255.255.255.255"]
	for address in get_lan_addresses():
		if not _is_private_address(address):
			continue
		var octets: PoolStringArray = address.split(".")
		var broadcast: String = "%s.%s.%s.255" % [octets[0], octets[1], octets[2]]
		if not result.has(broadcast):
			result.append(broadcast)
	return result


static func _is_private_address(address: String) -> bool:
	if address.begins_with("10.") or address.begins_with("192.168."):
		return true
	if address.begins_with("172."):
		var second: = int(address.split(".")[1])
		return second >= 16 and second <= 31
	return false


static func _is_virtual_interface(interface_name: String) -> bool:
	for prefix in ["lo", "docker", "br-", "veth", "virbr", "vmnet", "vboxnet", "podman", "cni", "flannel"]:
		if interface_name.begins_with(prefix):
			return true
	# Windows friendly names (Hyper-V/WSL switch, VirtualBox, VMware)
	for part in ["vethernet", "virtualbox", "vmware", "loopback"]:
		if part in interface_name:
			return true
	return false
