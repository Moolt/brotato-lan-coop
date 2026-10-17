extends Node

# /root/LanNet/Discovery: finds games on the local network without typing an IP.
# Host: while a lobby is open (hosting, no run in progress), broadcasts a small UDP beacon
# every second to DISCOVERY_PORT. Client: while the join page is open, listens on that port
# and keeps a list of the games heard from in the last GAME_TIMEOUT seconds.

signal games_changed()

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const BEACON_INTERVAL: = 1.0
const GAME_TIMEOUT: = 3.5

# "ip:port" -> {ip, port, name, players, max_players, compatible, last_seen}
var games: = {}
var listen_failed: = false

var _beacon_peer: PacketPeerUDP = null
var _beacon_addresses: = []
var _beacon_timer: = 0.0
var _listen_peer: PacketPeerUDP = null


func _process(delta: float) -> void :
	_process_beacon(delta)
	_process_listener()


func start_listening() -> void :
	if _listen_peer != null:
		return
	games = {}
	listen_failed = false
	var peer: = PacketPeerUDP.new()
	var err: = peer.listen(NetProtocol.DISCOVERY_PORT)
	if err != OK:
		# Usually a second client on the same PC. Joining by address still works.
		listen_failed = true
		ModLoaderLog.warning("Could not listen for LAN games on port %d (error %d)" % [NetProtocol.DISCOVERY_PORT, err], NetProtocol.MOD_ID)
	else:
		_listen_peer = peer
	emit_signal("games_changed")


func stop_listening() -> void :
	if _listen_peer != null:
		_listen_peer.close()
		_listen_peer = null
	games = {}


# Sorted by name, for display.
func get_games() -> Array:
	var result: = games.values()
	result.sort_custom(self, "_sort_by_name")
	return result


func _sort_by_name(a: Dictionary, b: Dictionary) -> bool:
	return a.name.to_lower() < b.name.to_lower()



# Host

func _process_beacon(delta: float) -> void :
	var net = get_parent()
	if not net.is_host or net.run_in_progress:
		if _beacon_peer != null:
			_beacon_peer.close()
			_beacon_peer = null
		return

	if _beacon_peer == null:
		_beacon_peer = PacketPeerUDP.new()
		_beacon_peer.set_broadcast_enabled(true)
		_beacon_addresses = NetProtocol.get_broadcast_addresses()
		_beacon_timer = 0.0

	_beacon_timer -= delta
	if _beacon_timer > 0.0:
		return
	_beacon_timer = BEACON_INTERVAL

	var host_entry = net.get_player(0)
	var host_name: String = host_entry.name if host_entry != null else net.config.player_name
	var beacon: = NetProtocol.build_beacon(host_name, net.config.port, net.get_player_count())
	for address in _beacon_addresses:
		if _beacon_peer.set_dest_address(address, NetProtocol.DISCOVERY_PORT) == OK:
			var _err = _beacon_peer.put_packet(beacon)



# Client

func _process_listener() -> void :
	if _listen_peer == null:
		return

	var changed: = false
	var now: = OS.get_ticks_msec()
	while _listen_peer.get_available_packet_count() > 0:
		var bytes: = _listen_peer.get_packet()
		var ip: = _listen_peer.get_packet_ip()
		var beacon = NetProtocol.parse_beacon(bytes)
		if beacon == null or ip.empty():
			continue
		beacon.ip = ip
		var key: String = ip + ":" + str(beacon.port)
		var old = games.get(key)
		beacon.last_seen = now
		if old == null or old.name != beacon.name or old.players != beacon.players or old.compatible != beacon.compatible:
			changed = true
		games[key] = beacon

	for key in games.keys():
		if now - games[key].last_seen > GAME_TIMEOUT * 1000:
			games.erase(key)
			changed = true

	if changed:
		emit_signal("games_changed")
