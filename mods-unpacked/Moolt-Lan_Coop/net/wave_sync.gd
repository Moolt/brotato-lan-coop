extends Node

# In-wave sync, a child of main during a LAN session (added by the main.gd extension).
# Each machine moves its own player; the host decides everything else (see the plan, Step 6).
# RPCs go through LanNet, which has the same path on every peer and forwards them here.
#
# Host:
#   - Remote players are driven by their clients: every physics frame a client sends
#     {pos, move, aim, manual_aim}. The host places the player there (players are kinematic
#     bodies) and feeds move to its animation and moving/not-moving item effects.
#   - Every SNAPSHOT_INTERVAL physics frames (20 Hz) it sends a snapshot to all clients:
#     wave time left and, per player, position, movement, speed, HP and death.
# Client:
#   - No enemies yet (6b): the wave manager and the entity spawner don't run.
#   - The own player moves locally at the speed the host reports, takes no damage and doesn't
#     regenerate; HP and death come from the host.
#   - Other players are puppets: physics off, position interpolated between snapshots
#     INTERP_DELAY_MS in the past.
#   - The wave timer follows the host's. The wave ends when the host says so.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const SNAPSHOT_INTERVAL: = 3
const INTERP_DELAY_MS: = 100
const MAX_BUFFERED_SNAPSHOTS: = 20
const TIMER_RESYNC_THRESHOLD: = 0.5
const MOVE_SCALE: = 127.0
const FLAG_DEAD: = 1

var _net: Node = null
var _main: Node = null
var _is_host: = false
var _local_index: = - 1
var _frame: = 0

# Host: latest state per remote player_index: {pos, move, aim, manual_aim}.
var _remote_states: = {}
var _snapshot_seq: = 0

# Client: received snapshots, oldest first: {time (host msec), players: [{pos, move}]}.
var _snapshots: = []
var _last_seq: = - 1
# Local msec minus host msec, tracked from below (the smallest delay seen, slowly forgotten).
var _clock_offset = null


func _init() -> void :
	name = "LanWaveSync"
	pause_mode = PAUSE_MODE_PROCESS


func _ready() -> void :
	_net = LanGame.get_lan_net()
	_main = get_parent()
	_is_host = _net.is_host
	_local_index = _net.local_player_index
	_net.wave_sync = self

	if _is_host:
		for player in _main._players:
			if player.player_index != _local_index:
				player.lan_net_driven = true
	else:
		_main._wave_manager.set_physics_process(false)
		_main._entity_spawner.set_physics_process(false)
		# Bullet hell events shoot from here; enemy projectiles come from the host later (6c).
		for child in _main._enemy_projectiles.get_children():
			child.queue_free()
		for player in _main._players:
			player.disable_hurtbox()
			player._item_pickup_area.set_deferred("monitoring", false)
			player._item_attract_area.set_deferred("monitoring", false)
			player.lan_no_regen = true
			if player.player_index != _local_index:
				player.set_physics_process(false)


func _exit_tree() -> void :
	if _net != null and _net.wave_sync == self:
		_net.wave_sync = null


func _physics_process(_delta: float) -> void :
	_frame += 1
	if _is_host:
		_apply_remote_states()
		if _frame % SNAPSHOT_INTERVAL == 0:
			_net.send_snapshot(_build_snapshot())
	else:
		_send_own_state()
		_update_puppets()



# Host

func on_player_state(player_index: int, pos: Vector2, move: Vector2, aim: Vector2, manual_aim: bool) -> void :
	if player_index == _local_index or player_index < 0 or player_index >= _main._players.size():
		return
	_remote_states[player_index] = {"pos": pos, "move": move.clamped(1.0), "aim": aim, "manual_aim": manual_aim}


# Manual aim of a remote player as its client reported it, null for others.
func get_remote_manual_aim(player_index: int):
	if not _is_host or not _remote_states.has(player_index):
		return null
	return _remote_states[player_index].manual_aim


func _apply_remote_states() -> void :
	var zone_rect: Rect2 = ZoneService.get_current_zone_rect()
	for player_index in _remote_states:
		var player = _main._players[player_index]
		if not is_instance_valid(player) or player.dead:
			continue
		var state: Dictionary = _remote_states[player_index]
		player.global_position = Vector2(
			clamp(state.pos.x, zone_rect.position.x, zone_rect.end.x),
			clamp(state.pos.y, zone_rect.position.y, zone_rect.end.y)
		)
		player.lan_move = state.move
		if state.aim != Vector2.ZERO:
			player.gamepad_attack_vector = state.aim.normalized()


func _build_snapshot() -> PoolByteArray:
	_snapshot_seq += 1
	var buffer: = StreamPeerBuffer.new()
	buffer.put_u32(_snapshot_seq)
	buffer.put_u32(OS.get_ticks_msec())
	buffer.put_float(_main._wave_timer.time_left)
	buffer.put_u8(_main._players.size())
	for player in _main._players:
		buffer.put_float(player.global_position.x)
		buffer.put_float(player.global_position.y)
		var move: Vector2 = player._current_movement.clamped(1.0)
		buffer.put_8(int(round(move.x * MOVE_SCALE)))
		buffer.put_8(int(round(move.y * MOVE_SCALE)))
		buffer.put_float(player.get_move_speed())
		buffer.put_32(player.current_stats.health)
		buffer.put_32(player.max_stats.health)
		buffer.put_u8(FLAG_DEAD if player.dead else 0)
	return buffer.data_array



# Client

func on_snapshot(data: PoolByteArray) -> void :
	var buffer: = StreamPeerBuffer.new()
	buffer.data_array = data
	var seq: = buffer.get_u32()
	if seq <= _last_seq:
		return
	_last_seq = seq
	var host_time: = buffer.get_u32()
	var time_left: = buffer.get_float()
	var count: = buffer.get_u8()
	if count != _main._players.size() or data.size() != 13 + count * 23:
		return

	var offset: = OS.get_ticks_msec() - host_time
	if _clock_offset == null or offset < _clock_offset:
		_clock_offset = offset
	else:
		_clock_offset += 1

	var positions: = []
	for player_index in count:
		var pos: = Vector2(buffer.get_float(), buffer.get_float())
		var move: = Vector2(buffer.get_8(), buffer.get_8()) / MOVE_SCALE
		var speed: = buffer.get_float()
		var health: = buffer.get_32()
		var max_health: = buffer.get_32()
		var flags: = buffer.get_u8()
		positions.append({"pos": pos, "move": move})
		_apply_player_state(_main._players[player_index], speed, health, max_health, (flags & FLAG_DEAD) != 0)

	_snapshots.append({"time": host_time, "players": positions})
	if _snapshots.size() > MAX_BUFFERED_SNAPSHOTS:
		_snapshots.pop_front()

	if not _main._cleaning_up and abs(_main._wave_timer.time_left - time_left) > TIMER_RESYNC_THRESHOLD and time_left > 0.0:
		_main._wave_timer.start(time_left)


func _apply_player_state(player, speed: float, health: int, max_health: int, dead: bool) -> void :
	if not is_instance_valid(player) or player.dead:
		return
	player.lan_move_speed = speed
	if player.current_stats.health != health or player.max_stats.health != max_health:
		player.max_stats.health = max_health
		player.current_stats.health = health
		player.emit_signal("health_updated", player, health, max_health)
	if dead:
		player.die()


func _send_own_state() -> void :
	if _local_index < 0 or _local_index >= _main._players.size():
		return
	var player = _main._players[_local_index]
	if not is_instance_valid(player) or player.dead:
		return
	# is_manual_aim returns null rather than false when manual aim is off.
	_net.send_player_state(player.global_position, player._current_movement, player.gamepad_attack_vector, Utils.is_manual_aim(_local_index) == true)


# Puppets show where the host had them INTERP_DELAY_MS ago, between the two snapshots around
# that time (or the newest one if none is newer).
func _update_puppets() -> void :
	if _snapshots.empty() or _clock_offset == null:
		return
	var render_time: float = OS.get_ticks_msec() - _clock_offset - INTERP_DELAY_MS
	while _snapshots.size() > 2 and _snapshots[1].time <= render_time:
		_snapshots.pop_front()
	var from: Dictionary = _snapshots[0]
	var to: Dictionary = _snapshots[1] if _snapshots.size() > 1 else from
	var weight: = 1.0
	if to.time > from.time:
		weight = clamp((render_time - from.time) / float(to.time - from.time), 0.0, 1.0)

	for player_index in _main._players.size():
		var player = _main._players[player_index]
		if player_index == _local_index or not is_instance_valid(player) or player.dead:
			continue
		var a: Dictionary = from.players[player_index]
		var b: Dictionary = to.players[player_index]
		player.global_position = a.pos.linear_interpolate(b.pos, weight)
		player.update_animation(b.move)


# Host event: the wave ends (time out or everyone dead).
func on_wave_cleanup() -> void :
	_main.lan_clean_up_from_host()
