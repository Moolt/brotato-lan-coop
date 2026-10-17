extends Node

# /root/LanNet: owns the ENet peer, the handshake, the lobby state and the session flags.
# Every RPC goes through this node, which has the same path on all peers.
# The host is always peer 1 and player_index 0. Remote functions check the sender id themselves.

signal session_started(as_host)
signal session_ended(reason)
signal joined_lobby()
signal lobby_changed()
signal player_disconnected(player_index)

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const NetConfig = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_config.gd")
const NetDiscovery = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_discovery.gd")

const HOST_PEER_ID: = 1

var config = NetConfig.new()
var discovery: Node = null

var active: = false
var is_host: = false
var is_client: = false
var joined: = false
var run_in_progress: = false
var local_player_index: = - 1

# One entry per player (see NetProtocol.new_player_entry), sorted by player_index.
var players: = []
var lobby_settings: = {}

# Reason of the last session end (translation key, "" if the player left on purpose).
# The title screen reads and clears it to show a popup.
var last_end_reason: = ""

var _peer: NetworkedMultiplayerENet = null
var _pending_hello: = {}
var _own_unlocks: = {}


func _ready() -> void :
	pause_mode = PAUSE_MODE_PROCESS
	config.load_config()
	discovery = NetDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)

	var tree: = get_tree()
	var _e = tree.connect("network_peer_connected", self, "_on_network_peer_connected")
	_e = tree.connect("network_peer_disconnected", self, "_on_network_peer_disconnected")
	_e = tree.connect("connected_to_server", self, "_on_connected_to_server")
	_e = tree.connect("connection_failed", self, "_on_connection_failed")
	_e = tree.connect("server_disconnected", self, "_on_server_disconnected")
	set_process(false)


func _process(_delta: float) -> void :
	if not is_host:
		set_process(false)
		return

	var now: = OS.get_ticks_msec()
	for peer_id in _pending_hello.keys():
		if now - _pending_hello[peer_id] > NetProtocol.HELLO_TIMEOUT * 1000:
			_pending_hello.erase(peer_id)
			_kick_peer(peer_id)



# Public API

func host(port: int = - 1) -> int:
	if active:
		leave()
	if port <= 0:
		port = config.port

	var peer: = NetworkedMultiplayerENet.new()
	peer.compression_mode = NetworkedMultiplayerENet.COMPRESS_RANGE_CODER
	peer.server_relay = false
	var err: = peer.create_server(port, NetProtocol.MAX_CLIENTS)
	if err != OK:
		last_end_reason = NetProtocol.MSG_SERVER_FAILED
		ModLoaderLog.warning("Could not host on port %d (error %d)" % [port, err], NetProtocol.MOD_ID)
		return err

	_peer = peer
	get_tree().network_peer = peer
	active = true
	is_host = true
	joined = true
	local_player_index = 0
	players = [NetProtocol.new_player_entry(HOST_PEER_ID, 0, config.player_name)]
	lobby_settings = NetProtocol.default_lobby_settings()
	last_end_reason = ""
	_set_saves_blocked(true)
	set_process(true)

	config.port = port
	config.save_config()
	ModLoaderLog.info("Hosting on port %d" % port, NetProtocol.MOD_ID)
	emit_signal("session_started", true)
	emit_signal("lobby_changed")
	return OK


func join(ip: String, port: int = - 1) -> int:
	if active:
		leave()
	if port <= 0:
		port = config.port

	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		last_end_reason = NetProtocol.MSG_INVALID_IP
		return ERR_INVALID_PARAMETER

	var peer: = NetworkedMultiplayerENet.new()
	peer.compression_mode = NetworkedMultiplayerENet.COMPRESS_RANGE_CODER
	var err: = peer.create_client(ip, port)
	if err != OK:
		last_end_reason = NetProtocol.MSG_CONNECTION_FAILED
		ModLoaderLog.warning("Could not connect to %s:%d (error %d)" % [ip, port, err], NetProtocol.MOD_ID)
		return err

	_peer = peer
	get_tree().network_peer = peer
	active = true
	is_client = true
	joined = false
	last_end_reason = ""
	_set_saves_blocked(true)

	config.last_ip = ip
	config.port = port
	config.save_config()
	ModLoaderLog.info("Connecting to %s:%d" % [ip, port], NetProtocol.MOD_ID)
	emit_signal("session_started", false)
	return OK


func leave() -> void :
	_end_session("")


func set_player_name(new_name: String) -> void :
	config.player_name = NetProtocol.sanitize_name(new_name)
	config.save_config()


# Changes the local player's lobby entry. Keys: NetProtocol.PLAYER_EDITABLE_KEYS.
func set_local_player_info(changes: Dictionary) -> void :
	if not active or not joined:
		return
	if is_host:
		var entry = get_player(local_player_index)
		if entry != null and _apply_player_changes(entry, changes):
			_broadcast_lobby_state()
	else:
		rpc_id(HOST_PEER_ID, "_rpc_update_player", changes)


# Host only: zone, difficulty.
func set_lobby_settings(changes: Dictionary) -> void :
	if not is_host:
		return
	for key in changes:
		if lobby_settings.has(key):
			lobby_settings[key] = changes[key]
	_broadcast_lobby_state()


# Host only: while true, new joins are rejected and dropped players keep their slot.
func set_run_in_progress(value: bool) -> void :
	if not is_host:
		return
	run_in_progress = value


func get_player(player_index: int):
	for entry in players:
		if entry.player_index == player_index:
			return entry
	return null


func get_local_player():
	return get_player(local_player_index)


func get_player_count() -> int:
	return players.size()


func are_all_ready() -> bool:
	if players.empty():
		return false
	for entry in players:
		if not entry.connected or entry.character_id.empty() or not entry.ready:
			return false
	return true



# Network callbacks

func _on_network_peer_connected(peer_id: int) -> void :
	if is_host:
		_pending_hello[peer_id] = OS.get_ticks_msec()


func _on_network_peer_disconnected(peer_id: int) -> void :
	if not is_host:
		return
	_pending_hello.erase(peer_id)

	var entry = _get_player_by_peer(peer_id)
	if entry == null:
		return

	ModLoaderLog.info("%s left" % entry.name, NetProtocol.MOD_ID)
	if run_in_progress:
		entry.connected = false
		entry.ready = false
		emit_signal("player_disconnected", entry.player_index)
	else:
		players.erase(entry)
		_compact_player_indices()
	_broadcast_lobby_state()


func _on_connected_to_server() -> void :
	rpc_id(HOST_PEER_ID, "_rpc_hello", NetProtocol.build_hello(config.player_name))


# ENet closes the peer itself right after emitting these, so clean up deferred.
func _on_connection_failed() -> void :
	call_deferred("_end_session", NetProtocol.MSG_CONNECTION_FAILED)


func _on_server_disconnected() -> void :
	call_deferred("_end_session", NetProtocol.MSG_HOST_LEFT)



# RPCs: client -> host

remote func _rpc_hello(hello) -> void :
	if not is_host:
		return
	var sender: = get_tree().get_rpc_sender_id()
	if not _pending_hello.has(sender):
		return
	_pending_hello.erase(sender)

	var reason: = NetProtocol.validate_hello(hello)
	if reason.empty() and run_in_progress:
		reason = NetProtocol.REJECT_IN_PROGRESS
	if reason.empty() and players.size() >= NetProtocol.MAX_PLAYERS:
		reason = NetProtocol.REJECT_FULL

	if not reason.empty():
		ModLoaderLog.info("Rejected peer %d: %s" % [sender, reason], NetProtocol.MOD_ID)
		rpc_id(sender, "_rpc_rejected", reason)
		_kick_peer_later(sender)
		return

	var entry: = NetProtocol.new_player_entry(sender, players.size(), NetProtocol.sanitize_name(hello.name))
	players.append(entry)
	ModLoaderLog.info("%s joined as player %d" % [entry.name, entry.player_index], NetProtocol.MOD_ID)
	rpc_id(sender, "_rpc_welcome", entry.player_index, NetProtocol.get_unlocks_snapshot())
	_broadcast_lobby_state()


remote func _rpc_update_player(changes) -> void :
	if not is_host or typeof(changes) != TYPE_DICTIONARY:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry != null and _apply_player_changes(entry, changes):
		_broadcast_lobby_state()



# RPCs: host -> client

remote func _rpc_welcome(player_index, unlocks) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	joined = true
	local_player_index = int(player_index)
	_apply_host_unlocks(unlocks)
	ModLoaderLog.info("Joined lobby as player %d" % local_player_index, NetProtocol.MOD_ID)
	emit_signal("joined_lobby")


remote func _rpc_rejected(reason) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	call_deferred("_end_session", str(reason))


remote func _rpc_lobby_state(new_players, new_settings) -> void :
	if not is_client or not joined or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	if typeof(new_players) != TYPE_ARRAY or typeof(new_settings) != TYPE_DICTIONARY:
		return
	players = new_players
	lobby_settings = new_settings
	var me = _get_player_by_peer(get_tree().get_network_unique_id())
	if me != null:
		local_player_index = me.player_index
	emit_signal("lobby_changed")



# Internals

func _broadcast_lobby_state() -> void :
	if not is_host:
		return
	for entry in players:
		if entry.peer_id != HOST_PEER_ID and entry.connected:
			rpc_id(entry.peer_id, "_rpc_lobby_state", players, lobby_settings)
	emit_signal("lobby_changed")


# Returns true if anything changed.
func _apply_player_changes(entry: Dictionary, changes: Dictionary) -> bool:
	var changed: = false
	for key in NetProtocol.PLAYER_EDITABLE_KEYS:
		if not changes.has(key):
			continue
		var value = changes[key]
		if key == "ready":
			if typeof(value) != TYPE_BOOL:
				continue
			if value and entry.character_id.empty():
				value = false
		elif typeof(value) != TYPE_STRING:
			continue

		if entry[key] == value:
			continue
		if key == "character_id":
			entry.ready = false
			entry.weapon_id = ""
		entry[key] = value
		changed = true
	return changed


func _compact_player_indices() -> void :
	for i in players.size():
		players[i].player_index = i
		if players[i].peer_id == HOST_PEER_ID:
			local_player_index = i


func _get_player_by_peer(peer_id: int):
	for entry in players:
		if entry.peer_id == peer_id:
			return entry
	return null


func _kick_peer_later(peer_id: int) -> void :
	var _e = get_tree().create_timer(NetProtocol.KICK_DELAY).connect("timeout", self, "_kick_peer", [peer_id])


func _kick_peer(peer_id: int) -> void :
	if not is_host or _peer == null:
		return
	if get_tree().get_network_connected_peers().has(peer_id):
		_peer.disconnect_peer(peer_id)


func _apply_host_unlocks(unlocks) -> void :
	if typeof(unlocks) != TYPE_DICTIONARY:
		return
	if _own_unlocks.empty():
		_own_unlocks = NetProtocol.get_unlocks_snapshot()
	for key in NetProtocol.UNLOCK_KEYS:
		if unlocks.has(key) and typeof(unlocks[key]) == TYPE_ARRAY:
			ProgressData.set(key, unlocks[key].duplicate())


func _restore_own_unlocks() -> void :
	for key in _own_unlocks:
		ProgressData.set(key, _own_unlocks[key])
	_own_unlocks = {}


func _set_saves_blocked(value: bool) -> void :
	ProgressData.set("lan_coop_saves_blocked", value)


func _end_session(reason: String) -> void :
	if not active:
		return
	var was_in_game: = run_in_progress or (is_client and joined)

	if _peer != null and _peer.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer.close_connection()
	get_tree().network_peer = null
	_peer = null

	_restore_own_unlocks()
	_set_saves_blocked(false)

	active = false
	is_host = false
	is_client = false
	joined = false
	run_in_progress = false
	local_player_index = - 1
	players = []
	lobby_settings = {}
	_pending_hello = {}
	set_process(false)
	last_end_reason = reason

	ModLoaderLog.info("Session ended (%s)" % (reason if not reason.empty() else "left"), NetProtocol.MOD_ID)
	emit_signal("session_ended", reason)

	var current_scene: = get_tree().current_scene
	if was_in_game and not reason.empty() and current_scene != null and current_scene.filename != MenuData.title_screen_scene:
		var _e = get_tree().change_scene(MenuData.title_screen_scene)
