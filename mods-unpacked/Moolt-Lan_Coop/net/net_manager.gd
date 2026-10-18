extends Node

# /root/LanNet: owns the ENet peer, the handshake, the lobby state and the session flags.
# Every RPC goes through this node, which has the same path on all peers.
# The host is always peer 1 and player_index 0. Remote functions check the sender id themselves.

signal session_started(as_host)
signal session_ended(reason)
signal joined_lobby()
signal lobby_changed()
signal player_disconnected(player_index)
signal run_sync_changed()
# wave_end_state was set (host: sent, client: applied).
signal wave_end_ready()

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const NetConfig = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_config.gd")
const NetDiscovery = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_discovery.gd")
const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
const RunBuilder = preload("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const SoloView = preload("res://mods-unpacked/Moolt-Lan_Coop/game/solo_view.gd")

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

# Run sync (Start). The host builds the run, sends it with its digest, and clients ack whether
# their copy matches. lobby_settings.run_id names the current run (0 = none); any lobby change
# resets it, so a stale run is never started. run_state (JSON text, see RunBuilder) is kept
# for loading the wave later.
var run_state: = ""
var _run_id_counter: = 0
var _received_run_id: = 0
var _received_run_ok: = false
var _run_acks: = {}
# True between Start and the wave scene: the wave loads once every client has acked the run.
var _start_requested: = false
# True once a built or received run replaced RunData (reset when the session ends).
var _run_data_replaced: = false

# Wave end (Step 7). The host sends the run as it stands after the wave (a client's RunData
# diverged during it) with each player's pending level-ups and crates (RunBuilder.pack_pending).
# A client applies it once its own wave is over (its end-wave timer ran, or it left the wave
# scene) and acks whether its digest matches. wave_end_state is the applied one:
# {wave, pending, ok}, empty before the first wave end.
var wave_end_state: = {}
# Client: received, waiting for the own wave to be over.
var _incoming_wave_end: = {}
# Host: peer_id -> ok for wave_end_state.
var _wave_end_acks: = {}
# Between waves RunData holds only the local player (game/solo_view.gd).
var solo_view = SoloView.new()

# The wave's LanWaveSync (net/wave_sync.gd) while main.tscn is loaded in a session, else null.
# In-wave RPCs are forwarded to it.
var wave_sync: Node = null
# True while this machine's in-wave pause menu is open (the game keeps running in a session).
var pause_menu_open: = false


func _ready() -> void :
	pause_mode = PAUSE_MODE_PROCESS
	LanGame.grow_autoload_arrays()
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
	set_process_input(false)


func _process(_delta: float) -> void :
	if is_client:
		_apply_wave_end_if_ready()
		if _incoming_wave_end.empty():
			set_process(false)
		return
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
	lobby_settings.scaling = config.scaling.duplicate()
	_apply_lobby_settings({"zone": config.last_zone, "difficulty": config.last_difficulty})
	_apply_multiplayer_unlocks()
	last_end_reason = ""
	_set_saves_blocked(true)
	_set_solo_mouse(true)
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
	_set_solo_mouse(true)

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


# Host only: zone, difficulty. Invalid values are ignored; valid ones are remembered.
func set_lobby_settings(changes: Dictionary) -> void :
	if not is_host:
		return
	if _apply_lobby_settings(changes):
		config.last_zone = lobby_settings.zone
		config.last_difficulty = lobby_settings.difficulty
		config.save_config()
		_broadcast_lobby_state()


# Host only: while true, new joins are rejected and dropped players keep their slot.
# lobby_settings.in_wave tells the clients' lobbies. Ending it drops the players who left
# meanwhile and makes the run stale (it was played), so Start builds a fresh one.
func set_run_in_progress(value: bool) -> void :
	if not is_host or run_in_progress == value:
		return
	run_in_progress = value
	lobby_settings.in_wave = value
	if not value:
		for entry in players.duplicate():
			if not entry.connected:
				players.erase(entry)
		_compact_player_indices()
	_broadcast_lobby_state(value)


# Host: builds the run from the lobby and sends it to every client.
func start_run() -> int:
	if not is_host or not are_all_ready():
		return ERR_UNAVAILABLE

	_run_data_replaced = true
	RunBuilder.build_run(players, lobby_settings)
	run_state = RunBuilder.serialize_run()
	var _applied = RunBuilder.apply_run(run_state)
	var digest: = RunBuilder.digest()
	_run_id_counter += 1
	lobby_settings.run_id = _run_id_counter
	_run_acks = {}
	_start_requested = true
	ModLoaderLog.info("Run %d built: %s" % [_run_id_counter, to_json(RunBuilder.summarize())], NetProtocol.MOD_ID)

	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_run_state", _run_id_counter, run_state, digest)
	_broadcast_lobby_state(true)
	emit_signal("run_sync_changed")
	_enter_wave_if_synced()
	return OK


# Host, at the end of a wave that wasn't failed (after RunData.on_wave_end): sends the run and
# the pending level-ups and crates to every client. Like start_run, the host applies its own
# run from the same JSON, so every peer holds the same deserialized copy.
func send_wave_end_state(upgrades_to_process: Array, consumables_to_process: Array) -> void :
	if not is_host:
		return
	var pending: = RunBuilder.pack_pending(upgrades_to_process, consumables_to_process)
	run_state = RunBuilder.serialize_run()
	var _applied = RunBuilder.apply_run(run_state)
	var digest: = RunBuilder.digest()
	wave_end_state = {"wave": RunData.current_wave, "pending": pending, "ok": true}
	_wave_end_acks = {}
	ModLoaderLog.info("Wave %d over, sending the run: %s, pending %s" % [RunData.current_wave, to_json(RunBuilder.summarize()), to_json(pending)], NetProtocol.MOD_ID)
	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_wave_end_state", lobby_settings.get("run_id", 0), RunData.current_wave, run_state, digest, pending)
	emit_signal("wave_end_ready")


# {state: "none" | "pending" | "synced" | "failed", names: [...]} for the lobby's status line.
# Host: names are the clients still pending or with a different run. Client: no names.
func get_run_sync_status() -> Dictionary:
	var run_id: int = lobby_settings.get("run_id", 0)
	if run_id == 0:
		return {"state": "none", "names": []}
	if is_client:
		if _received_run_id != run_id:
			return {"state": "pending", "names": []}
		return {"state": "synced" if _received_run_ok else "failed", "names": []}

	var pending: = []
	var failed: = []
	for entry in _get_connected_clients():
		if not _run_acks.has(entry.peer_id):
			pending.append(entry.name)
		elif not _run_acks[entry.peer_id]:
			failed.append(entry.name)
	if not failed.empty():
		return {"state": "failed", "names": failed}
	if not pending.empty():
		return {"state": "pending", "names": pending}
	return {"state": "synced", "names": []}


func get_player(player_index: int):
	for entry in players:
		if entry.player_index == player_index:
			return entry
	return null


func get_local_player():
	return get_player(local_player_index)


# The local player's index in RunData right now: 0 in the solo view, else local_player_index.
func get_local_run_index() -> int:
	return 0 if solo_view.active else local_player_index


# Between waves: RunData becomes the local player's solo run (game/solo_view.gd) and back.
func enter_solo_view() -> bool:
	if not active or not solo_view.enter(local_player_index, _get_local_coop_player()):
		return false
	ModLoaderLog.info("Solo view entered (player %d)" % local_player_index, NetProtocol.MOD_ID)
	return true


func leave_solo_view() -> void :
	if not solo_view.active:
		return
	solo_view.leave()
	ModLoaderLog.info("Solo view left: %s" % to_json(RunBuilder.summarize()), NetProtocol.MOD_ID)


func get_player_count() -> int:
	return players.size()


func are_all_ready() -> bool:
	if players.empty():
		return false
	for entry in players:
		if not entry.connected or not entry.ready or not LobbyRules.is_entry_complete(entry):
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
	rpc_id(sender, "_rpc_welcome", entry.player_index)
	_broadcast_lobby_state()


remote func _rpc_update_player(changes) -> void :
	if not is_host or typeof(changes) != TYPE_DICTIONARY:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry != null and _apply_player_changes(entry, changes):
		_broadcast_lobby_state()



# RPCs: host -> client

remote func _rpc_welcome(player_index) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	joined = true
	local_player_index = int(player_index)
	_apply_multiplayer_unlocks()
	ModLoaderLog.info("Joined lobby as player %d" % local_player_index, NetProtocol.MOD_ID)
	emit_signal("joined_lobby")


remote func _rpc_rejected(reason) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	call_deferred("_end_session", str(reason))


remote func _rpc_run_state(run_id, state, digest) -> void :
	if not is_client or not joined or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	if typeof(run_id) != TYPE_INT or typeof(state) != TYPE_STRING or typeof(digest) != TYPE_STRING:
		return
	run_state = state
	_received_run_id = run_id
	_run_data_replaced = true
	_received_run_ok = RunBuilder.apply_run(state) and RunBuilder.digest() == digest
	if _received_run_ok:
		ModLoaderLog.info("Run %d received and verified" % run_id, NetProtocol.MOD_ID)
	else:
		ModLoaderLog.warning("Run %d differs from the host's: %s" % [run_id, to_json(RunBuilder.summarize())], NetProtocol.MOD_ID)
	rpc_id(HOST_PEER_ID, "_rpc_run_state_ack", run_id, _received_run_ok)
	emit_signal("run_sync_changed")



# Host -> client: the run after the wave (see send_wave_end_state).
remote func _rpc_wave_end_state(run_id, wave, state, digest, pending) -> void :
	if not is_client or not joined or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	if typeof(run_id) != TYPE_INT or typeof(wave) != TYPE_INT or typeof(state) != TYPE_STRING or typeof(digest) != TYPE_STRING or typeof(pending) != TYPE_ARRAY:
		return
	if run_id != _received_run_id:
		return
	_incoming_wave_end = {"wave": wave, "state": state, "digest": digest, "pending": pending}
	set_process(true)


# RPCs: client -> host (run sync)

remote func _rpc_run_state_ack(run_id, ok) -> void :
	if not is_host or typeof(run_id) != TYPE_INT or typeof(ok) != TYPE_BOOL:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry == null or run_id != lobby_settings.get("run_id", 0):
		return
	_run_acks[entry.peer_id] = ok
	if not ok:
		ModLoaderLog.warning("%s has a different run" % entry.name, NetProtocol.MOD_ID)
	emit_signal("run_sync_changed")
	_enter_wave_if_synced()


remote func _rpc_wave_end_ack(wave, ok) -> void :
	if not is_host or typeof(wave) != TYPE_INT or typeof(ok) != TYPE_BOOL:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry == null or wave != wave_end_state.get("wave", - 1):
		return
	_wave_end_acks[entry.peer_id] = ok
	if ok:
		ModLoaderLog.info("%s holds the run after wave %d" % [entry.name, wave], NetProtocol.MOD_ID)
	else:
		ModLoaderLog.warning("%s has a different run after wave %d" % [entry.name, wave], NetProtocol.MOD_ID)


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
	# The host is back in the lobby (wave over, or it quit): follow it. Temporary until 7e:
	# a client still picking its upgrades (solo view) goes there itself when done.
	if not lobby_settings.get("in_wave", false) and _is_in_wave_scene() and not solo_view.active:
		var _e = get_tree().change_scene(MenuData.title_screen_scene)


# Host -> client: the run every client acked is starting.
remote func _rpc_enter_wave(run_id) -> void :
	if not is_client or not joined or get_tree().get_rpc_sender_id() != HOST_PEER_ID:
		return
	if typeof(run_id) != TYPE_INT or run_id != _received_run_id or not _received_run_ok or _is_in_wave_scene():
		return
	_fill_coop_players()
	ModLoaderLog.info("Run %d: loading the wave" % run_id, NetProtocol.MOD_ID)
	var _e = get_tree().change_scene(MenuData.game_scene)


remote func _rpc_snapshot(data) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID or typeof(data) != TYPE_RAW_ARRAY:
		return
	if wave_sync != null:
		wave_sync.on_snapshot(data)


remote func _rpc_events(events) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID or typeof(events) != TYPE_ARRAY:
		return
	if wave_sync != null:
		wave_sync.on_events(events)


remote func _rpc_wave_cleanup(run_states) -> void :
	if not is_client or get_tree().get_rpc_sender_id() != HOST_PEER_ID or typeof(run_states) != TYPE_ARRAY:
		return
	if wave_sync != null:
		wave_sync.on_wave_cleanup(run_states)



# RPCs: client -> host (in-wave)

remote func _rpc_player_state(pos, move, aim, manual_aim) -> void :
	if not is_host or wave_sync == null:
		return
	if typeof(pos) != TYPE_VECTOR2 or typeof(move) != TYPE_VECTOR2 or typeof(aim) != TYPE_VECTOR2 or typeof(manual_aim) != TYPE_BOOL:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry != null:
		wave_sync.on_player_state(entry.player_index, pos, move, aim, manual_aim)


# The client's wave scene is up (the host holds the wave timer until every client sent this).
remote func _rpc_wave_loaded() -> void :
	if not is_host or wave_sync == null:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry != null:
		wave_sync.on_client_loaded(entry.peer_id)


# The client quit the wave from its pause menu.
remote func _rpc_left_wave() -> void :
	if not is_host or wave_sync == null:
		return
	var entry = _get_player_by_peer(get_tree().get_rpc_sender_id())
	if entry != null:
		wave_sync.on_player_left(entry.player_index, entry.peer_id)



# In-wave sending (called by LanWaveSync)

func send_snapshot(data: PoolByteArray) -> void :
	for entry in _get_connected_clients():
		rpc_unreliable_id(entry.peer_id, "_rpc_snapshot", data)


func send_events(events: Array) -> void :
	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_events", events)


func send_wave_cleanup(run_states: Array) -> void :
	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_wave_cleanup", run_states)


func send_wave_loaded() -> void :
	if is_client and joined:
		rpc_id(HOST_PEER_ID, "_rpc_wave_loaded")


func send_left_wave() -> void :
	if is_client and joined:
		rpc_id(HOST_PEER_ID, "_rpc_left_wave")


# Host: lobby entries of the clients that are connected right now (the wave waits for them).
func get_connected_client_peers() -> Array:
	var peers: = []
	for entry in _get_connected_clients():
		peers.append(entry.peer_id)
	return peers


func send_player_state(pos: Vector2, move: Vector2, aim: Vector2, manual_aim: bool) -> void :
	if is_client and joined:
		rpc_unreliable_id(HOST_PEER_ID, "_rpc_player_state", pos, move, aim, manual_aim)



# Internals

# Every lobby change makes a built run stale, unless keep_run (start_run itself).
func _broadcast_lobby_state(keep_run: bool = false) -> void :
	if not is_host:
		return
	if not keep_run and lobby_settings.get("run_id", 0) != 0:
		lobby_settings.run_id = 0
		run_state = ""
		_run_acks = {}
		_start_requested = false
		emit_signal("run_sync_changed")
	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_lobby_state", players, lobby_settings)
	emit_signal("lobby_changed")


# Lobby entries of clients whose peer is connected right now.
func _get_connected_clients() -> Array:
	var result: = []
	var connected_peers: = get_tree().get_network_connected_peers()
	for entry in players:
		if entry.peer_id != HOST_PEER_ID and entry.connected and connected_peers.has(entry.peer_id):
			result.append(entry)
	return result


# Applies the editable keys in order (character, weapon, ready), dropping invalid values.
# Changing character or weapon un-readies the player. Returns true if anything changed.
func _apply_player_changes(entry: Dictionary, changes: Dictionary) -> bool:
	var changed: = false
	for key in NetProtocol.PLAYER_EDITABLE_KEYS:
		if not changes.has(key):
			continue
		var value = changes[key]
		# (No match block here: "continue" inside match falls through to the next pattern.)
		if key == "ready":
			if typeof(value) != TYPE_BOOL:
				continue
			if value and not LobbyRules.is_entry_complete(entry):
				value = false
		elif typeof(value) != TYPE_STRING:
			continue
		elif key == "character_id" and not value.empty() and not LobbyRules.is_character_unlocked(LobbyRules.get_character(value)):
			continue
		elif key == "weapon_id" and not value.empty() and LobbyRules.get_starting_choice(LobbyRules.get_character(entry.character_id), value) == null:
			continue

		if entry[key] == value:
			continue
		if key == "character_id":
			entry.weapon_id = ""
		if key != "ready":
			entry.ready = false
		entry[key] = value
		changed = true
	return changed


# Returns true if anything changed.
func _apply_lobby_settings(changes: Dictionary) -> bool:
	var changed: = false
	if changes.has("zone") and LobbyRules.is_valid_zone(changes.zone) and lobby_settings.zone != int(changes.zone):
		lobby_settings.zone = int(changes.zone)
		changed = true
	if changes.has("difficulty") and LobbyRules.is_valid_difficulty(changes.difficulty) and lobby_settings.difficulty != int(changes.difficulty):
		lobby_settings.difficulty = int(changes.difficulty)
		changed = true
	return changed


# Host: once every client holds the run, everyone loads the wave.
func _enter_wave_if_synced() -> void :
	if not _start_requested or get_run_sync_status().state != "synced":
		return
	_start_requested = false
	set_run_in_progress(true)
	_fill_coop_players()
	for entry in _get_connected_clients():
		rpc_id(entry.peer_id, "_rpc_enter_wave", lobby_settings.run_id)
	ModLoaderLog.info("Run %d: loading the wave" % lobby_settings.run_id, NetProtocol.MOD_ID)
	var _e = get_tree().change_scene(MenuData.game_scene)


# Client: applies the received wave-end run once the own wave is over (vanilla's end-wave code
# still uses RunData until then) and acks it.
func _apply_wave_end_if_ready() -> void :
	if _incoming_wave_end.empty():
		return
	var current_scene: = get_tree().current_scene
	if current_scene == null:
		return
	if current_scene.filename == MenuData.game_scene and not current_scene.get("_end_wave_timer_timedout"):
		return
	var incoming: = _incoming_wave_end
	_incoming_wave_end = {}
	run_state = incoming.state
	var ok: bool = RunBuilder.apply_run(incoming.state) and RunBuilder.digest() == incoming.digest and RunBuilder.is_valid_pending(incoming.pending)
	wave_end_state = {"wave": incoming.wave, "pending": incoming.pending if ok else [], "ok": ok}
	if ok:
		ModLoaderLog.info("Run after wave %d received and verified, pending %s" % [incoming.wave, to_json(incoming.pending)], NetProtocol.MOD_ID)
	else:
		ModLoaderLog.warning("Run after wave %d differs from the host's: %s" % [incoming.wave, to_json(RunBuilder.summarize())], NetProtocol.MOD_ID)
	rpc_id(HOST_PEER_ID, "_rpc_wave_end_ack", incoming.wave, ok)
	emit_signal("wave_end_ready")


func _is_in_wave_scene() -> bool:
	var current_scene: = get_tree().current_scene
	return current_scene != null and current_scene.filename == MenuData.game_scene


# CoopService.connected_players: one [device, type] per player, in player_index order.
# The local player uses the keyboard (7) or the first gamepad (6). Remote players get
# device -1, which reads no input (see the main.gd and player_movement_behavior.gd extensions);
# their own machine moves them (net/wave_sync.gd).
func _fill_coop_players() -> void :
	CoopService.connected_players.clear()
	for entry in players:
		if entry.player_index != local_player_index:
			CoopService.connected_players.push_back([- 1, CoopService.PlayerType.KEYBOARD_AND_MOUSE])
		else:
			CoopService.connected_players.push_back(_get_local_coop_player())
	CoopService.emit_signal("connected_players_updated", CoopService.connected_players)


func _get_local_coop_player() -> Array:
	if InputService.using_gamepad:
		return [CoopService.GAMEPAD_REMAPPED_DEVICE_ID, CoopService.PlayerType.GAMEPAD_XBOX]
	return [CoopService.KEYBOARD_REMAPPED_DEVICE_ID, CoopService.PlayerType.KEYBOARD_AND_MOUSE]


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


# Everything is unlocked during a session. The own lists are kept aside and restored on
# leave; saves are blocked meanwhile, so singleplayer progress is never touched.
func _apply_multiplayer_unlocks() -> void :
	if _own_unlocks.empty():
		_own_unlocks = NetProtocol.get_unlocks_snapshot()
	var unlocks: = NetProtocol.get_multiplayer_unlocks()
	for key in NetProtocol.UNLOCK_KEYS:
		ProgressData.set(key, unlocks[key])


func _restore_own_unlocks() -> void :
	for key in _own_unlocks:
		ProgressData.set(key, _own_unlocks[key])
	_own_unlocks = {}


# Vanilla's InputService hides the mouse cursor on every input in a coop run with more than one
# player (couch coop shares one mouse). In a session every machine has a single player, so
# InputService's _input is off and _input below applies its solo rule instead: mouse input shows
# the cursor, keyboard and gamepad input hide it.
func _set_solo_mouse(value: bool) -> void :
	InputService.set_process_input(not value)
	set_process_input(value)


func _input(event: InputEvent) -> void :
	if BugReporter.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	var is_gamepad_input: bool = event is InputEventJoypadButton or Utils.is_valid_joypad_motion_event(event)
	var is_keyboard_input: bool = event is InputEventKey
	var is_mouse_input: bool = event is InputEventMouseMotion or event is InputEventMouseButton
	if is_gamepad_input or is_keyboard_input:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	elif is_mouse_input:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if is_gamepad_input:
		InputService.using_gamepad = true
	elif is_keyboard_input or is_mouse_input:
		InputService.using_gamepad = false


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
	_set_solo_mouse(false)
	if _run_data_replaced:
		# A synced run replaced RunData; don't leave it behind for the menus.
		RunData.reset()
		_run_data_replaced = false
	run_state = ""
	_received_run_id = 0
	_received_run_ok = false
	_run_acks = {}
	_start_requested = false
	wave_end_state = {}
	_incoming_wave_end = {}
	_wave_end_acks = {}
	solo_view.discard()
	CoopService.clear_coop_players()

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
