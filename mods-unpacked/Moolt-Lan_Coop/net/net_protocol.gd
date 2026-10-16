extends Reference

# Shared constants and helpers for the LAN coop protocol.
# Bump PROTOCOL_VERSION whenever an RPC signature or message layout changes.

const MOD_ID: = "Moolt-Lan_Coop"
const PROTOCOL_VERSION: = 1

const DEFAULT_PORT: = 24567
const MAX_PLAYERS: = 12
const MAX_CLIENTS: = MAX_PLAYERS - 1
const MAX_NAME_LENGTH: = 16
const HELLO_TIMEOUT: = 5.0
const KICK_DELAY: = 0.5

# Reject / disconnect reasons. They double as translation keys (see net_translations.gd).
const REJECT_VERSION: = "LAN_REJECT_VERSION"
const REJECT_GAME_VERSION: = "LAN_REJECT_GAME_VERSION"
const REJECT_DLC: = "LAN_REJECT_DLC"
const REJECT_FULL: = "LAN_REJECT_FULL"
const REJECT_IN_PROGRESS: = "LAN_REJECT_IN_PROGRESS"
const REJECT_BAD_HELLO: = "LAN_REJECT_BAD_HELLO"
const MSG_HOST_LEFT: = "LAN_MSG_HOST_LEFT"
const MSG_CONNECTION_FAILED: = "LAN_MSG_CONNECTION_FAILED"
const MSG_SERVER_FAILED: = "LAN_MSG_SERVER_FAILED"
const MSG_INVALID_IP: = "LAN_MSG_INVALID_IP"

# Keys a client may change on its own lobby entry.
const PLAYER_EDITABLE_KEYS: = ["character_id", "weapon_id", "ready"]

# ProgressData arrays replaced by the host's lists while a session is active.
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


static func build_hello(player_name: String) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION, 
		"mod_version": get_mod_version(), 
		"game_version": ProgressData.VERSION, 
		"dlcs": get_sorted_dlc_ids(), 
		"name": player_name, 
	}


# Returns "" if the hello is acceptable, otherwise a reject reason.
static func validate_hello(hello) -> String:
	if typeof(hello) != TYPE_DICTIONARY:
		return REJECT_BAD_HELLO
	for key in ["protocol_version", "mod_version", "game_version", "dlcs", "name"]:
		if not hello.has(key):
			return REJECT_BAD_HELLO
	if typeof(hello.dlcs) != TYPE_ARRAY or typeof(hello.name) != TYPE_STRING:
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
	}


static func get_unlocks_snapshot() -> Dictionary:
	var unlocks: = {}
	for key in UNLOCK_KEYS:
		unlocks[key] = ProgressData.get(key).duplicate()
	return unlocks
