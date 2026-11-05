extends Node

# In-wave sync, a child of main during a LAN session (added by the main.gd extension).
# Each machine moves its own player; the host decides everything else (see the plan, Step 6).
# RPCs go through LanNet, which has the same path on every peer and forwards them here.
#
# Host:
#   - Remote players are driven by their clients: every physics frame a client sends
#     {pos, move, aim, manual_aim}. The host places the player there (players are kinematic
#     bodies) and feeds move to its animation and moving/not-moving item effects. aim is the
#     point the player aims at, relative to the player: the mouse, or far out along the gamepad
#     aim. In manual aim the host's weapons turn towards it (weapon.gd extension).
#   - Every entity the spawner creates during the wave (enemies, bosses, trees, structures,
#     pets) gets a net id. Spawns, births (the spawn markers) and deaths go out as reliable
#     events, collected per physics frame. Spawn markers have ids too: vanilla moves an enemy's
#     marker elsewhere when a player stands on it, and the host sends the new position.
#   - Weapon attacks (player, weapon index, rotation, distance, melee attack type; one that
#     arrives while the client's copy still swings waits until the swing is over) and
#     projectiles (spawn: scene, position, velocity, rotation, speed and range, wave motion and
#     bullet-hell direction; stop) are events too. Projectiles inside a GroupOfBullet aren't
#     synced (no bullet-hell pattern in use spawns groups).
#   - So are enemy and turret animations other than idle/death (attacks, charges), damage taken
#     by players and entities (for floating text, flashes, blood) and explosions.
#   - Materials and consumables get their own net ids: drop (with vanilla's push-back target),
#     attraction (whenever attracted_by changes to a player or a synced entity), size (vanilla
#     merges new materials into existing ones once 50 lie around) and pickup by a player are
#     events; so is a crate going into a player's things-to-process.
#   - The wave timer (and so the enemy spawns) waits until every client has loaded the wave, at
#     most LOAD_TIMEOUT seconds; every screen says "Waiting for players..." meanwhile.
#   - A client that disconnects or quits the wave loses its player (it dies).
#   - The end of the wave goes out with the host's verdict (wave failed, run lost, run won).
#   - Every SNAPSHOT_INTERVAL physics frames (20 Hz) it sends a snapshot to all clients:
#     wave time left, whether the wave still waits for clients; per player position, movement, speed, HP, death, gold, XP and level; per entity (trees
#     excluded, they don't move) position, HP ratio (0-255), burning, the enemy outlines
#     (boosted, cursed, charmed) and full lungs (DLC), and the enemy time factor (time shifter,
#     pocket watch).
#   - Primal Dread: an enemy's evolution (mutant, meca) goes with its spawn. Acid, petrol and fire
#     puddles (only the host spawns them, extensions/global/gpe_spawner.gd) and single holes have
#     their own events; the wave's hole layout comes from the shared wave seed.
# Client:
#   - The wave manager and the entity spawner don't run. Entities come from the host's events,
#     spawned through the normal spawner (and its pools), then made inert: no physics, kinematic,
#     no areas. They die on the host's death event and slide with its knockback.
#   - The own player moves locally at the speed the host reports, takes no damage and doesn't
#     regenerate; HP and death come from the host.
#   - Weapons show the host's attacks: melee weapons swing (the real swing, which hits nothing
#     because client entities are inert), ranged weapons recoil and play their sound.
#     Projectiles are copies with their areas off; they fly on their own and stop on the host's
#     stop event (or at their range).
#   - Attack animations play, but their shoot()/start_shoot() calls do nothing (enemy.gd and
#     turret.gd extensions). Damage events flash the unit, play its hurt sound and emit
#     took_damage, which drives vanilla's floating text, blood and screen shake.
#   - Item copies drop, fly to whoever attracts them and vanish on the host's pickup (sound,
#     effect, floating text). Gold, XP and level follow the snapshot; RunData's signals update the
#     HUD, and a level-up runs vanilla's on_levelled_up (sound, things-to-process icon).
#   - Other players and entities are puppets, interpolated between snapshots at a render
#     clock that runs a delay behind the host: INTERP_DELAY_MS, more while snapshots arrive late
#     (WiFi power saving delivers them in bursts), see _note_lateness and _update_puppets.
#   - The wave timer follows the host's. The wave ends when the host says so.
# Both: the game mode (LanNet.mode) hears of the wave's start, every physics frame and (host) every
# synced entity's death; its own traffic goes through LanNet, not the events.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const SNAPSHOT_INTERVAL: = 3
# Interpolation delay: at least INTERP_DELAY_MS; with late snapshots, the largest recent
# lateness plus LATENESS_MARGIN_MS (puppets stall whenever a snapshot is later than the delay),
# at most MAX_INTERP_DELAY_MS.
const INTERP_DELAY_MS: = 100
const MAX_INTERP_DELAY_MS: = 300
const LATENESS_MARGIN_MS: = 10.0
# Snapshots whose lateness counts (5 s), and how fast a lower delay is taken (per snapshot).
const LATENESS_WINDOW: = 100
const INTERP_DELAY_DECAY: = 0.02
# The clock offset follows the fastest snapshot and creeps up this much per snapshot (1 ms/s),
# enough for clock drift between machines.
const CLOCK_DRIFT_PER_SNAPSHOT: = 0.05
# The render clock advances by the physics step and runs at most 10 % fast or slow to reach
# its target; it jumps only when it is more than RENDER_CLOCK_SNAP_MS off.
const MAX_RENDER_CLOCK_RATE: = 0.1
const RENDER_CLOCK_SNAP_MS: = 500.0
# Host: between a client's states (bursty over WiFi with power saving) its player keeps moving
# in the reported direction for at most MAX_EXTRAPOLATION s. When the next state arrives, the
# difference to where it was shown fades out (REMOTE_CORRECTION_DECAY per tick) unless it is
# more than REMOTE_SNAP_DISTANCE.
const MAX_EXTRAPOLATION: = 0.25
# Clients send their state every physics tick (60 Hz): 1 ms/s of clock drift.
const REMOTE_CLOCK_DRIFT_PER_STATE: = 1.0 / 60.0
const REMOTE_CORRECTION_DECAY: = 0.75
const REMOTE_SNAP_DISTANCE: = 200.0
# Vanilla's margin for units' test_motion (unit.gd).
const REMOTE_MOTION_MARGIN: = 0.08
const MAX_BUFFERED_SNAPSHOTS: = 20
const TIMER_RESYNC_THRESHOLD: = 0.5
const MOVE_SCALE: = 127.0
const HP_SCALE: = 255.0
# Distance of the reported aim point along a gamepad's aim direction: far enough that every
# weapon around the player points the same way, as in vanilla.
const GAMEPAD_AIM_DISTANCE: = 10000.0
const FLAG_DEAD: = 1
# Primal Dread's puddles tint the players standing in them (Player._set_acid_color, petrol).
const FLAG_ACID: = 2
const FLAG_PETROL: = 4
# seq, host msec, wave time left, flags, enemy time factor, player count.
const SNAPSHOT_HEADER_SIZE: = 18
const SNAPSHOT_FLAG_WAITING: = 1
const LOAD_TIMEOUT: = 15.0
# Client: EntityService's slow time left while the host's snapshot says slowed (it ends on the
# host's word, not on a local countdown).
const TIME_SLOW_HOLD: = 1.0e9
const WAITING_FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const WAITING_FONT_SIZE: = 40
const SNAPSHOT_PLAYER_SIZE: = 37
const SNAPSHOT_ENTITY_SIZE: = 8
const ENTITY_FLAG_BURNING: = 1
const ENTITY_FLAG_BOOSTED: = 2
const ENTITY_FLAG_CURSED: = 4
const ENTITY_FLAG_CHARMED: = 8
# The DLC's iron and spiky lungs: a stargazer filled them (another sprite); mirrored (random per
# machine at _ready).
const ENTITY_FLAG_FULL: = 16
const ENTITY_FLAG_MIRRORED: = 32
# The DLC's stargazers: angry (lung died or full); clients play the angry sound when it turns on.
const ENTITY_FLAG_ANGRY: = 64
# Hidden on the host: Primal Dread's oviraptor and iguanodon wait unseen at the map's edge
# until their warning ends, then charge across (GoTowardsBorderOppositeMovementBehavior).
const ENTITY_FLAG_HIDDEN: = 128
const MAX_NET_ID: = 65535

const EVENT_SPAWN: = 0
const EVENT_DIE: = 1
const EVENT_BIRTH: = 2
const EVENT_WEAPON: = 3
const EVENT_PROJECTILE: = 4
const EVENT_PROJECTILE_STOP: = 5
const EVENT_ANIMATION: = 6
const EVENT_DAMAGE: = 7
const EVENT_EXPLOSION: = 8
const EVENT_ITEM_DROP: = 9
const EVENT_ITEM_ATTRACT: = 10
const EVENT_ITEM_PICKUP: = 11
const EVENT_CRATE_TO_PROCESS: = 12
const EVENT_ITEM_SCALE: = 13
const EVENT_BIRTH_MOVED: = 14
const EVENT_PIVOTS: = 15
const EVENT_ENTITY_SIZE: = 16
const EVENT_DESPAWN: = 17
const EVENT_PUDDLE: = 18
const EVENT_PUDDLE_END: = 19
const EVENT_HOLE: = 20
const EVENT_ITEM_DESPAWN: = 21
const EVENT_PROJECTILE_REDIRECT: = 22
const EVENT_BOOMERANG: = 23
const EVENT_DIG_SITE: = 24
const EVENT_POACHER_ZONE: = 25
const EVENT_POACHER_MARK: = 26
# Primal Dread's brachiosaurus: [code, net id, kind, value]; kinds below.
const EVENT_BRACHIOSAURUS: = 27
const BRACHIOSAURUS_STATE: = 0
const BRACHIOSAURUS_MOUTH: = 1
# Its foot: value = sprites shown (FOOT_*), flipped.
const BRACHIOSAURUS_FOOT: = 2
const FOOT_SHADOW: = 1
const FOOT_FOOT: = 2
const FOOT_RELEASE: = 4
const FOOT_FLIPPED: = 8
# An enemy projectile that follows its shooter or a target (enemy lasers): [code, id, shooter
# net id, target kind, target id].
const EVENT_PROJECTILE_FROM: = 28
# Primal Dread visuals (polled on the host per tick, see _check_entity_visuals):
# [code, net id, behaviour index, shown, line end]: a charge's warning line (velociraptor).
const EVENT_WARNING_LINE: = 29
# [code, net id, behaviour index, start, target, flipped]: a jump starts (dimetrodon,
# carnotaurus); clients play its shadow and landing marker.
const EVENT_JUMP: = 30
# [code, net id, [colour html, ...]]: an enemy's other outlines (percent damage taken: blood
# turret, mosquitor), when they change.
const EVENT_OUTLINES: = 31
# [code, net id, rotation, distance, attack type]: an attack of a weapon a synced entity holds
# (Primal Dread's ammosaurus).
const EVENT_ENTITY_WEAPON: = 32
# [code, player_index, weapon index, stat hash]: a carbon bow's next arrow.
const EVENT_CARBON_ARROW: = 33
# [code, id, texture path, sprite scale]: a projectile's texture set at the shot (carbon bow).
const EVENT_PROJECTILE_LOOK: = 34
# [code, net id, evolution]: an evil mob ate enough materials and evolved.
const EVENT_EVOLVE_MOB: = 35
# A warning line's end point is sent again when it turned more than this (radians).
const WARNING_LINE_RESEND_ANGLE: = 0.05
# Puddle kinds (extensions/global/gpe_spawner.gd).
const PUDDLE_ACID: = 0
const PUDDLE_PETROL: = 1
const PUDDLE_FIRE: = 2
# An enemy's evolution (Primal Dread), in its spawn event.
const EVOLUTION_NONE: = 0
const EVOLUTION_MUTANT: = 1
const EVOLUTION_MECA: = 2
# Charmed enemies' projectiles use it with the charm's hue.
const HUE_SHIFT_MATERIAL = preload("res://resources/shaders/hue_shift_shadermat.tres")
const ITEM_GOLD: = 0
const ITEM_CONSUMABLE: = 1
const NO_TARGET: = - 1
const RANGED_ATTACK: = - 1
const TARGET_ENTITY: = 0
const TARGET_PLAYER: = 1
const DAMAGE_CRIT: = 1
const DAMAGE_DODGE: = 2
const DAMAGE_PROTECTED: = 4
const DAMAGE_ARMOR: = 8
const DAMAGE_ONE_SHOT: = 16
const UNSYNCED_ANIMATIONS: = ["idle", "death", "RESET"]

var is_host: = false
# Events sent (host) or received (client) per event type, for tests and tuning.
var event_counts: = {}

var _net: Node = null
var _main: Node = null
var _local_index: = - 1
var _frame: = 0

# Net id -> entity, on both sides. Ids are u16 and wrap; a wave never gets near 65535 alive.
var _entities: = {}
# Built in _ready: Utils isn't a constant.
var _enemy_outlines: = []
# The outline colours the flags and the evolution manage (EVENT_OUTLINES sends the others).
var _managed_outline_colors: = []
# Host: net id -> the Pursuer's sprite scale last sent (it grows when boosted).
var _entity_sizes: = {}
# Client: net id -> pivot directions and angles from the host, until the copy has as many pivots
# (the DLC's eel adds its own when its phase changes).
var _pending_pivots: = {}
# Client: hue -> the projectile material, shared like the charm shares its own.
var _hue_materials: = {}
# Client: EVOLUTION_MUTANT / EVOLUTION_MECA -> the enemy effect behaviour data the zone's
# EvolutionSceneEffectBehavior adds to evolved enemies (texture, outline), taken before the scene
# effect behaviours are freed.
var _evolution_behaviors: = {}
# Dig sites and poacher zones (Primal Dread items), the scene effect behaviours' own lists (the
# same order on every machine, placed from the shared wave seed); the poacher behaviour's kill
# mark scene (client). Host: the state last sent per dig site [digging, dug_up] and per zone
# its position.
var _dig_sites: = []
var _dig_states: = {}
var _poacher_zones: = []
var _poacher_positions: = {}
var _poacher_mark: PackedScene = null
# Host: brachiosaurus feet (net id) -> the sprites last sent (FOOT_* mask).
var _foot_states: = {}
# Net id -> the entity's warning-line and jump attack behaviours (subtree order, the same on
# every machine), for entities that have any; host: also the state last sent per behaviour.
var _visual_behaviors: = {}
var _visual_states: = {}
# Client: running jumps, net id -> {behavior, time}.
var _jumps: = {}
# Net id -> the extra outline colours (html) last sent (host) or shown (client).
var _extra_outlines: = {}
# Puddle net id -> puddle, on both sides (host: until it starts to fade out).
var _puddles: = {}
var _next_puddle_id: = 0

# Host: latest state per remote player_index: {pos, time (client msec), move, aim, manual_aim,
# fresh (not applied yet), since (its age in s: estimated at arrival, then counted up),
# reported_velocity (from the last two states), offset (correction still to blend out),
# velocity (of the last tick's dead reckoning)}.
var _remote_states: = {}
# Host: per remote player_index, host msec minus the client's msec, tracked from below like
# _clock_offset (the fastest state seen, creeping up 1 ms/s).
var _remote_clock_offsets: = {}
var _motion_result: = Physics2DTestMotionResult.new()
var _snapshot_seq: = 0
var _next_net_id: = 0
var _events: = []
# Projectiles shot since the last flush; their spawn events are built at flush time, when
# position and velocity are set (enemy projectiles shoot once in _ready, before they're placed).
var _pending_projectiles: = []
var _next_projectile_id: = 0

# Projectile net id -> projectile, on both sides (host: shot and not yet returned to the pool).
var _projectiles: = {}
var _scene_cache: = {}

# Item (material, consumable) net id -> item, on both sides. Host: also the attraction target
# last sent per item ([kind, id]).
var _items: = {}
var _item_targets: = {}
var _item_scales: = {}

# Spawn marker net id -> EntityBirth, on both sides; host: also the position last sent. Markers
# are pooled, so each one keeps its current id in the "lan_birth_id" meta and older ids that
# still point at it are ignored.
var _births: = {}
# Client: weapon -> the attack event that came while it was still attacking (the latest one).
var _pending_weapon_events: = {}
var _birth_positions: = {}
var _next_birth_id: = 0
var _next_item_id: = 0

# Client: received snapshots, oldest first:
# {time (host msec), players: [{pos, move}], entities: {net id: pos}}.
var _snapshots: = []
var _last_seq: = - 1
# Local msec minus host msec, tracked from below (the smallest delay seen, slowly forgotten).
var _clock_offset = null
# Host msec the puppets show, the current interpolation delay and recent snapshot lateness (ms
# beyond the fastest snapshot).
var _render_time = null
var _interp_delay: = float(INTERP_DELAY_MS)
var _lateness: = []
var _spawn_args = null

# Host: peers whose wave isn't loaded yet; both: whether the wave waits for them.
var _waiting_peers: = []
var _waiting_time: = 0.0
var _waiting: = false
var _waiting_label: Label = null


func _init() -> void :
	name = "LanWaveSync"
	pause_mode = PAUSE_MODE_PROCESS


func _ready() -> void :
	# [flag, colour, alpha, desaturation] of the enemy outlines the snapshot carries, as vanilla's
	# boost and the DLC's curse and charm add them.
	_enemy_outlines = [
		[ENTITY_FLAG_BOOSTED, Utils.BOOST_COLOR, 1.0, 0.0], 
		[ENTITY_FLAG_CURSED, Utils.CURSE_COLOR, 1.0, 0.0], 
		[ENTITY_FLAG_CHARMED, Utils.CHARM_COLOR, 0.4, 0.75], 
	]
	_managed_outline_colors = [Utils.BOOST_COLOR, Utils.CURSE_COLOR, Utils.CHARM_COLOR, Utils.MUTANT_COLOR, Utils.MECA_COLOR]
	_net = LanGame.get_lan_net()
	_main = get_parent()
	is_host = _net.is_host
	_local_index = _net.local_player_index
	_net.wave_sync = self
	_net.on_wave_started()

	_add_waiting_label()
	for child in _main._effect_behaviors.get_children():
		if child.get("dig_sites") is Array:
			_dig_sites = child.dig_sites
		if child.get("poacher_zones") is Array:
			_poacher_zones = child.poacher_zones
			_poacher_mark = child.poacher_mark
	if is_host:
		var _c = RunData.connect("poacher_enemy_killed_in_zone", self, "_on_host_poacher_kill")
		_waiting_peers = _net.get_connected_client_peers()
		_set_waiting(not _waiting_peers.empty())
		var _e = _net.connect("player_disconnected", self, "_on_player_disconnected")
		for player in _main._players:
			if player.player_index != _local_index:
				player.lan_net_driven = true
			_e = player.connect("took_damage", self, "_on_host_took_damage", [TARGET_PLAYER, player.player_index])
		call_deferred("_kill_disconnected_players")
	else:
		_spawn_args = EntitySpawner.SpawnEntityArgs.new(Vector2.ZERO, EntityType.ENEMY)
		_main._wave_manager.set_physics_process(false)
		_main._entity_spawner.set_physics_process(false)
		_main._entity_spawner._structure_timer.stop()
		# Bullet hell events shoot from here; enemy projectiles come from the host later (6c).
		for child in _main._enemy_projectiles.get_children():
			child.queue_free()
		# Scene effect behaviours act on spawns (the DLC curses enemies as they spawn); the
		# host's do that, and the snapshot carries the outlines.
		for child in _main._effect_behaviors.get_children():
			if child.get("mutant_enemy_effect_behavior_data") != null:
				_evolution_behaviors[EVOLUTION_MUTANT] = child.mutant_enemy_effect_behavior_data
				_evolution_behaviors[EVOLUTION_MECA] = child.meca_enemy_effect_behavior_data
			child.queue_free()
		for player in _main._players:
			player.disable_hurtbox()
			player._item_pickup_area.set_deferred("monitoring", false)
			player._item_attract_area.set_deferred("monitoring", false)
			player.lan_no_regen = true
			if player.player_index != _local_index:
				player.set_physics_process(false)
		_net.send_wave_loaded()
	_net.mode.on_wave_started(_main)


func _exit_tree() -> void :
	if RunData.is_connected("poacher_enemy_killed_in_zone", self, "_on_host_poacher_kill"):
		RunData.disconnect("poacher_enemy_killed_in_zone", self, "_on_host_poacher_kill")
	if _net != null and _net.wave_sync == self:
		_net.wave_sync = null
	# Leaving before the end of the wave (pause menu Quit): the host lets the player die.
	if not is_host and _net != null and not _main._cleaning_up:
		_net.send_left_wave()


# The wave is over and RunData is about to become the solo view (game/solo_view.gd): no more
# snapshots or events either way, since they index players RunData no longer holds.
func stop() -> void :
	set_physics_process(false)
	if _net.wave_sync == self:
		_net.wave_sync = null


func _physics_process(delta: float) -> void :
	_frame += 1
	if not _main._cleaning_up:
		_net.mode.on_wave_physics(_main, delta)
	if is_host:
		if _waiting:
			_waiting_time += delta
			if _waiting_time >= LOAD_TIMEOUT:
				_set_waiting(false)
		_apply_remote_states(delta)
		_flush_pending_projectiles()
		_check_item_attraction()
		_check_puddles()
		_check_dig_sites()
		_check_poacher_zones()
		_check_brachiosaurus_feet()
		_check_entity_visuals()
		_check_births()
		if not _events.empty():
			_count_events(_events)
			_net.send_events(_events)
			_events = []
		if _frame % SNAPSHOT_INTERVAL == 0:
			_net.send_snapshot(_build_snapshot())
	else:
		_send_own_state()
		_update_puppets(delta)
		_update_jumps(delta)
		_play_pending_weapon_events()



# Host

func on_player_state(player_index: int, time: int, pos: Vector2, move: Vector2, aim: Vector2, manual_aim: bool) -> void :
	if player_index == _local_index or player_index < 0 or player_index >= _main._players.size():
		return
	var offset: = float(OS.get_ticks_msec() - time)
	var clock_offset = _remote_clock_offsets.get(player_index)
	if clock_offset == null or offset < clock_offset:
		clock_offset = offset
	else:
		clock_offset += REMOTE_CLOCK_DRIFT_PER_STATE
	_remote_clock_offsets[player_index] = clock_offset
	var age: float = min(offset - clock_offset, MAX_EXTRAPOLATION * 1000.0) / 1000.0
	var previous = _remote_states.get(player_index)
	# The player's actual velocity from the last two states (0 when blocked by a wall or a
	# player, which the pressed direction doesn't show), unknown (0) after a long gap.
	var reported_velocity: = Vector2.ZERO
	if previous != null:
		var interval: float = (time - previous.time) / 1000.0
		if interval > 0.0 and interval <= MAX_EXTRAPOLATION:
			reported_velocity = ((pos - previous.pos) / interval).clamped(_main._players[player_index].get_move_speed())
	_remote_states[player_index] = {"pos": pos, "time": time, "move": move.clamped(1.0), "aim": aim, "manual_aim": manual_aim, "fresh": true, "since": age, "reported_velocity": reported_velocity, "offset": previous.offset if previous != null else Vector2.ZERO, "velocity": previous.velocity if previous != null else Vector2.ZERO}


# Manual aim of a remote player as its client reported it, null for others.
func get_remote_manual_aim(player_index: int):
	if not is_host or not _remote_states.has(player_index):
		return null
	return _remote_states[player_index].manual_aim


# Where a remote player aims as its client reported it (global position), null for others.
func get_remote_aim_point(player_index: int):
	if not is_host or not _remote_states.has(player_index):
		return null
	return _main._players[player_index].global_position + _remote_states[player_index].aim


# Called by the entity_spawner.gd extension for every non-player entity it spawns.
func on_entity_spawned(entity: Node, scene: PackedScene, type: int, pos: Vector2, player_index: int, data: Resource, charmed_by: int) -> void :
	_next_net_id = _next_net_id % MAX_NET_ID + 1
	var net_id: = _next_net_id
	entity.set_meta("lan_net_id", net_id)
	_entities[net_id] = entity
	if not entity.is_connected("died", self, "_on_host_entity_died"):
		var _e = entity.connect("died", self, "_on_host_entity_died")
		if entity is Unit:
			_e = entity.connect("took_damage", self, "_on_host_entity_took_damage")
		# Primal Dread's hungry hungry dinosaur (a pet) plays "eat" when it eats a fruit.
		if entity is Enemy or entity is Turret or entity is HungryHungryDinosaur:
			_e = entity._animation_player.connect("animation_started", self, "_on_host_entity_animation", [entity])
		if entity is Boss:
			_e = entity.connect("state_changed", self, "_on_host_boss_state_changed")
		var mouth = _get_mouth_player(entity)
		if mouth != null:
			_e = mouth.connect("animation_started", self, "_on_host_brachiosaurus_mouth", [entity])
	# The evolution happened in the spawn (EvolutionSceneEffectBehavior on enemy_respawned).
	var evolution: = EVOLUTION_NONE
	if entity is Enemy:
		if entity._is_mutant:
			evolution = EVOLUTION_MUTANT
		elif entity._is_meca:
			evolution = EVOLUTION_MECA
	_events.append([EVENT_SPAWN, net_id, type, scene.resource_path, pos, player_index, _get_data_ref(data, player_index), charmed_by, evolution])
	if entity is Pursuer:
		_entity_sizes[net_id] = entity.sprite.scale.y
	_watch_visual_behaviors(entity, net_id)
	_send_pivots(entity)


# The second AnimationPlayer of Primal Dread's brachiosaurus and T-rex (mouth open or closed).
func _get_mouth_player(entity: Node):
	if entity is Brachiosaurus:
		return entity._brachiosaurus_animation_player
	if entity is Tyranosaurus:
		return entity._TRexAnimationPlayer
	return null


func _watch_visual_behaviors(entity: Node, net_id: int) -> void :
	var _erased = _visual_behaviors.erase(net_id)
	_erased = _visual_states.erase(net_id)
	if not entity is Enemy:
		return
	var behaviors: = _find_visual_behaviors(entity, [])
	if not behaviors.empty():
		_visual_behaviors[net_id] = behaviors


func _find_visual_behaviors(node: Node, result: Array) -> Array:
	if node is WarningChargingAttackBehavior or node is JumpAttackBehavior:
		result.append(node)
	for child in node.get_children():
		var _r = _find_visual_behaviors(child, result)
	return result


# Bullets circling a boss on pivots (vanilla's predator, the DLC's giant, jellyfish and eel) turn
# a random way on each machine: the host sends each pivot's direction and angle at the spawn and
# whenever the boss changes phase (the eel adds pivots then), after the phase's own changes.
func _on_host_boss_state_changed(boss: Node) -> void :
	call_deferred("_send_pivots", boss)


func _send_pivots(entity: Node) -> void :
	if not is_instance_valid(entity) or entity.dead or not entity.has_meta("lan_net_id"):
		return
	var pivots: = _find_pivots(entity, [])
	if pivots.empty():
		return
	var data: = []
	for pivot in pivots:
		data.append([pivot.direction, pivot.rotation])
	_events.append([EVENT_PIVOTS, entity.get_meta("lan_net_id"), data])


func _find_pivots(node: Node, result: Array) -> Array:
	if node is Pivot:
		result.append(node)
	for child in node.get_children():
		var _r = _find_pivots(child, result)
	return result


# Called by the entity_spawner.gd extension right after vanilla started a spawn marker, which is
# then the last child of the births container (taken from the pool or newly added).
func on_birth(type: int, pos: Vector2, charmed_by: int) -> void :
	var container: Node = _main._births_container
	if container.get_child_count() == 0:
		return
	_next_birth_id = _next_birth_id % MAX_NET_ID + 1
	var birth: Node = container.get_child(container.get_child_count() - 1)
	birth.set_meta("lan_birth_id", _next_birth_id)
	_births[_next_birth_id] = birth
	_birth_positions[_next_birth_id] = pos
	_events.append([EVENT_BIRTH, _next_birth_id, type, pos, charmed_by])


# Finished markers hide themselves; moved ones (a player stood on an enemy's marker) are sent.
func _check_births() -> void :
	var done: = []
	for birth_id in _births:
		var birth = _births[birth_id]
		if not is_instance_valid(birth) or not birth.visible or birth.get_meta("lan_birth_id") != birth_id:
			done.append(birth_id)
		elif birth.global_position != _birth_positions[birth_id]:
			_birth_positions[birth_id] = birth.global_position
			_events.append([EVENT_BIRTH_MOVED, birth_id, birth.global_position])
	for birth_id in done:
		var _erased = _births.erase(birth_id)
		_erased = _birth_positions.erase(birth_id)


# Called by the gpe_spawner.gd extension for every puddle the host spawns, once it is set up.
func on_puddle_spawned(puddle: Node2D, kind: int) -> void :
	if _main._cleaning_up:
		return
	_next_puddle_id = _next_puddle_id % MAX_NET_ID + 1
	puddle.set_meta("lan_puddle_id", _next_puddle_id)
	_puddles[_next_puddle_id] = puddle
	var sprite_index: int = max(0, puddle.puddle_sprites.find(puddle.sprite.texture))
	_events.append([EVENT_PUDDLE, _next_puddle_id, kind, puddle.global_position, puddle._target_scale, sprite_index, puddle.sprite.rotation])


# A dig site that starts or stops being dug, or is dug up, goes out with its progress.
func _check_dig_sites() -> void :
	if _main._cleaning_up:
		return
	for i in _dig_sites.size():
		var site = _dig_sites[i]
		if not is_instance_valid(site):
			continue
		var state: = [site.is_being_dug() and not site.dug_up, site.dug_up]
		if _dig_states.get(i, [false, false]) != state:
			_dig_states[i] = state
			_events.append([EVENT_DIG_SITE, i, state[0], site.progress, state[1]])


# A poacher zone moved after a bonus kill (PoacherZoneSceneEffectBehavior relocates it).
func _check_poacher_zones() -> void :
	if _main._cleaning_up:
		return
	for i in _poacher_zones.size():
		var zone = _poacher_zones[i]
		if not is_instance_valid(zone):
			continue
		if not _poacher_positions.has(i):
			_poacher_positions[i] = zone.global_position
		elif _poacher_positions[i] != zone.global_position:
			_poacher_positions[i] = zone.global_position
			_events.append([EVENT_POACHER_ZONE, i, zone.global_position])


# Called by the brachiosaurus.gd extension after the host's state change (every second); its
# pivots (state 1) follow.
func on_brachiosaurus_state(boss: Node, new_state: int) -> void :
	if not boss.has_meta("lan_net_id") or _main._cleaning_up:
		return
	_events.append([EVENT_BRACHIOSAURUS, boss.get_meta("lan_net_id"), BRACHIOSAURUS_STATE, new_state])
	if new_state == 1:
		call_deferred("_send_pivots", boss)


func _on_host_brachiosaurus_mouth(anim_name: String, boss: Node) -> void :
	if boss.dead or not boss.has_meta("lan_net_id") or _main._cleaning_up:
		return
	_events.append([EVENT_BRACHIOSAURUS, boss.get_meta("lan_net_id"), BRACHIOSAURUS_MOUTH, anim_name])


# The foot's sprites change in its own physics (chase, lock, stomp), which copies don't run.
func _check_brachiosaurus_feet() -> void :
	if _main._cleaning_up:
		return
	for net_id in _entities:
		var foot = _entities[net_id]
		if not is_instance_valid(foot) or not foot is BrachiosaurusFoot or foot.dead:
			continue
		var mask: = 0
		if foot.sprite.visible:
			mask |= FOOT_SHADOW
		if foot._sprite_foot.visible:
			mask |= FOOT_FOOT
		if foot._sprite_release.visible:
			mask |= FOOT_RELEASE
		if foot._sprite_foot.flip_h:
			mask |= FOOT_FLIPPED
		if _foot_states.get(net_id, - 1) != mask:
			_foot_states[net_id] = mask
			_events.append([EVENT_BRACHIOSAURUS, net_id, BRACHIOSAURUS_FOOT, mask])


# Warning lines (shown, end point) and jump starts, which the behaviours drive in the host's
# physics only.
func _check_entity_visuals() -> void :
	if _visual_behaviors.empty() or _main._cleaning_up:
		return
	for net_id in _visual_behaviors:
		var entity = _entities.get(net_id)
		if entity == null or not is_instance_valid(entity) or entity.dead:
			continue
		var behaviors: Array = _visual_behaviors[net_id]
		var states: Array = _visual_states.get(net_id, [])
		while states.size() < behaviors.size():
			states.append(null)
		for i in behaviors.size():
			var behavior = behaviors[i]
			if not is_instance_valid(behavior):
				continue
			if behavior is WarningChargingAttackBehavior:
				var line = behavior._warning_line
				if not is_instance_valid(line):
					continue
				var end: Vector2 = line.points[1] if line.visible and line.points.size() > 1 else Vector2.ZERO
				var last = states[i]
				if last == null or last[0] != line.visible or (line.visible and abs(last[1].angle_to(end)) > WARNING_LINE_RESEND_ANGLE):
					states[i] = [line.visible, end]
					_events.append([EVENT_WARNING_LINE, net_id, i, line.visible, end])
			elif behavior is JumpAttackBehavior:
				if behavior._is_jumping and states[i] != true:
					_events.append([EVENT_JUMP, net_id, i, behavior._start_position, behavior._target_position, entity.sprite.flip_h])
				states[i] = behavior._is_jumping
		_visual_states[net_id] = states


# Outlines beyond the flags' and the evolution's (percent damage taken: blood turret, mosquitor).
func _check_extra_outlines(net_id: int, entity: Node) -> void :
	var extra: = []
	for color in entity._outline_colors:
		if not color in _managed_outline_colors:
			extra.append(color.to_html())
	if extra != _extra_outlines.get(net_id, []):
		_extra_outlines[net_id] = extra
		_events.append([EVENT_OUTLINES, net_id, extra])


func _on_host_poacher_kill(player_index: int, kill_position: Vector2) -> void :
	if not _main._cleaning_up:
		_events.append([EVENT_POACHER_MARK, player_index, kill_position])


func on_hole_spawned(pos: Vector2) -> void :
	if not _main._cleaning_up:
		_events.append([EVENT_HOLE, pos])


# A puddle that started to fade out (lifetime over, evicted, its plant died) fades on the clients.
func _check_puddles() -> void :
	if _puddles.empty() or _main._cleaning_up:
		return
	var done: = []
	for puddle_id in _puddles:
		var puddle = _puddles[puddle_id]
		if not is_instance_valid(puddle) or not puddle.is_active() or puddle.get_meta("lan_puddle_id", 0) != puddle_id:
			done.append(puddle_id)
	for puddle_id in done:
		var _erased = _puddles.erase(puddle_id)
		_events.append([EVENT_PUDDLE_END, puddle_id])


func on_client_loaded(peer_id: int) -> void :
	_waiting_peers.erase(peer_id)
	if _waiting and _waiting_peers.empty():
		_set_waiting(false)


func on_player_left(player_index: int, peer_id: int) -> void :
	on_client_loaded(peer_id)
	var _erased = _remote_states.erase(player_index)
	if player_index < 0 or player_index >= _main._players.size() or _main._cleaning_up:
		return
	var player = _main._players[player_index]
	if is_instance_valid(player) and not player.dead:
		player.die(_player_die_args())


# Death args for a player killed by the session (left, or dead on the host), as vanilla's
# Player.take_damage sets them but without a killer. Not Utils.default_die_args: vanilla leaves
# the last killer in its `from`, which may be freed by now, and main._on_player_died reads it.
func _player_die_args() -> Entity.DieArgs:
	var args: = Entity.DieArgs.new()
	args.enemy_killed_by_player = false
	return args


# Host, at the start of a later wave: players who disconnected in an earlier one stay dead.
func _kill_disconnected_players() -> void :
	for entry in _net.players:
		if not entry.connected:
			on_player_left(entry.player_index, entry.peer_id)


func _on_player_disconnected(player_index: int) -> void :
	var entry = _net.get_player(player_index)
	on_player_left(player_index, entry.peer_id if entry != null else 0)


func on_weapon_shot(weapon: Node, distance: float) -> void :
	var player = weapon._parent
	if not is_instance_valid(player):
		return
	if not player is Player:
		# A weapon a synced entity holds (Primal Dread's ammosaurus).
		if player.has_meta("lan_net_id") and _entities.get(player.get_meta("lan_net_id")) == player and player.get("_weapon") == weapon:
			var entity_attack_type: int = weapon.next_attack_type if weapon is MeleeWeapon else RANGED_ATTACK
			_events.append([EVENT_ENTITY_WEAPON, player.get_meta("lan_net_id"), weapon.rotation, distance, entity_attack_type])
		return
	var weapon_index: int = player.current_weapons.find(weapon)
	if weapon_index < 0:
		return
	var attack_type: int = weapon.next_attack_type if weapon is MeleeWeapon else RANGED_ATTACK
	_events.append([EVENT_WEAPON, player.player_index, weapon_index, weapon.rotation, distance, attack_type])


# Called by the projectile.gd extension. Only projectiles that sit directly in main's
# projectile containers are synced (bullets inside a GroupOfBullet move with their group).
func on_projectile_shot(projectile: Node) -> void :
	if projectile.lan_net_id != 0 or projectile is GroupOfBullet:
		return
	var parent: = projectile.get_parent()
	if parent != _main._player_projectiles and parent != _main._enemy_projectiles:
		return
	_next_projectile_id = _next_projectile_id % MAX_NET_ID + 1
	projectile.lan_net_id = _next_projectile_id
	_projectiles[_next_projectile_id] = projectile
	_pending_projectiles.append(projectile)


# net_id and pos as before the stop: a projectile without a stop delay is already back in the
# pool (on_projectile_returned) and has no net id any more.
func on_projectile_stopped(projectile: Node, net_id: int, pos: Vector2) -> void :
	if not is_host:
		return
	if _pending_projectiles.has(projectile):
		# Never sent: forget it.
		_pending_projectiles.erase(projectile)
		var _erased = _projectiles.erase(net_id)
		projectile.lan_net_id = 0
		return
	_events.append([EVENT_PROJECTILE_STOP, net_id, pos])


func on_projectile_returned(projectile: Node) -> void :
	var net_id: int = projectile.lan_net_id
	if _projectiles.get(net_id) != projectile:
		return
	var _erased = _projectiles.erase(net_id)
	if not is_host:
		return
	if _pending_projectiles.has(projectile):
		_pending_projectiles.erase(projectile)
	elif projectile._hitbox.active:
		# Pooled without stop() (stop() clears active): tell the clients.
		_events.append([EVENT_PROJECTILE_STOP, net_id, projectile.global_position])


# A synced projectile changed course on the host (deflected). One not sent yet goes out with its
# new course anyway.
func on_projectile_redirected(projectile: Node) -> void :
	if _pending_projectiles.has(projectile) or _projectiles.get(projectile.lan_net_id) != projectile:
		return
	_events.append([EVENT_PROJECTILE_REDIRECT, projectile.lan_net_id, projectile.global_position, projectile.velocity, projectile.rotation])


# A boomerang flies by position from start_flight (its weapon calls it right after the shot, with
# its velocity at zero): the copy gets the same flight, back to the same carrier.
func _send_boomerang(projectile: Node) -> void :
	if projectile._phase == BoomerangProjectile.Phase.NONE:
		return
	var carrier: = _get_target_ref(projectile._carrier)
	_events.append([EVENT_BOOMERANG, projectile.lan_net_id, carrier[0], carrier[1], projectile._start, projectile._forward.angle(), (projectile._end - projectile._start).length()])


# Enemy lasers stay with their shooter (EnemyLaser) or turn towards its target (EnemyLaserFollow).
func _send_projectile_from(projectile: Node) -> void :
	var from = projectile._hitbox.from
	if from == null or not is_instance_valid(from) or not from.has_meta("lan_net_id") or _entities.get(from.get_meta("lan_net_id")) != from:
		return
	var target: = _get_target_ref(projectile.get("target"))
	_events.append([EVENT_PROJECTILE_FROM, projectile.lan_net_id, from.get_meta("lan_net_id"), target[0], target[1]])


func _flush_pending_projectiles() -> void :
	for projectile in _pending_projectiles:
		if not is_instance_valid(projectile) or projectile.lan_net_id == 0:
			continue
		var speed: float = projectile.velocity.length()
		var max_range: = 0
		if projectile is PlayerProjectile and projectile._weapon_stats != null:
			speed = projectile._weapon_stats.projectile_speed
			max_range = projectile._max_range
		var is_enemy: bool = projectile.get_parent() == _main._enemy_projectiles
		var direction: = Vector2.ZERO
		if projectile is BulletHellProjectile and typeof(projectile.direction) == TYPE_VECTOR2:
			direction = projectile.direction
		# Charmed enemies shoot in the charm's hue (set_sprite_material); -1: no hue shift.
		var hue: = - 1.0
		var material = projectile._sprite.material
		if material is ShaderMaterial and material.shader == HUE_SHIFT_MATERIAL.shader:
			hue = material.get_shader_param("hue")
		_events.append([EVENT_PROJECTILE, projectile.lan_net_id, projectile.filename, projectile.global_position, projectile.velocity, projectile.rotation, speed, max_range, is_enemy, projectile.sinusoidal_motion, projectile.sinusoidal_motion_speed, direction, hue])
		if projectile is BoomerangProjectile:
			_send_boomerang(projectile)
		if projectile is EnemyLaser or projectile is EnemyLaserFollow:
			_send_projectile_from(projectile)
		if projectile.has_meta(CarbonBowWeapon.PROJECTILE_STAT_META) and projectile._sprite.texture != null:
			_events.append([EVENT_PROJECTILE_LOOK, projectile.lan_net_id, projectile._sprite.texture.resource_path, projectile._sprite.scale.x])
	_pending_projectiles.clear()


func _on_host_entity_animation(anim_name: String, entity: Node) -> void :
	if UNSYNCED_ANIMATIONS.has(anim_name) or entity.dead or not entity.has_meta("lan_net_id"):
		return
	var net_id: int = entity.get_meta("lan_net_id")
	if _entities.get(net_id) == entity:
		_events.append([EVENT_ANIMATION, net_id, anim_name, entity._animation_player.playback_speed])


func _on_host_entity_took_damage(unit: Node, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool) -> void :
	if not unit.has_meta("lan_net_id") or _entities.get(unit.get_meta("lan_net_id")) != unit:
		return
	_on_host_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot, TARGET_ENTITY, unit.get_meta("lan_net_id"))


func _on_host_took_damage(_unit: Node, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool, target_kind: int, target_id: int) -> void :
	var flags: = 0
	if is_crit:
		flags |= DAMAGE_CRIT
	if is_dodge:
		flags |= DAMAGE_DODGE
	if is_protected:
		flags |= DAMAGE_PROTECTED
	if armor_did_something:
		flags |= DAMAGE_ARMOR
	if is_one_shot:
		flags |= DAMAGE_ONE_SHOT
	var effect_scale: = 1.0
	if args != null:
		effect_scale = args.get_effect_scale()
	_events.append([EVENT_DAMAGE, target_kind, target_id, value, knockback_direction, flags, hit_type, effect_scale])


# Called by the weapon_service.gd extension after vanilla set the explosion up.
func on_explosion(instance: Node, effect: Resource) -> void :
	var path: String = effect.explosion_scene.resource_path
	_events.append([EVENT_EXPLOSION, path, instance.global_position, instance.scale.x, instance._explosion_smoke.amount, instance.sound_db_mod])


# Called by the item.gd extension after vanilla dropped a material or consumable.
func on_item_dropped(item: Node) -> void :
	if _main._cleaning_up:
		return
	_next_item_id = _next_item_id % MAX_NET_ID + 1
	item.lan_net_id = _next_item_id
	_items[_next_item_id] = item
	_item_targets[_next_item_id] = [NO_TARGET, 0]
	_item_scales[_next_item_id] = item.scale.x
	var kind: = ITEM_GOLD if item is Gold else ITEM_CONSUMABLE
	var texture_path: = ""
	var consumable_id: = ""
	var boosted: = 1
	if item is Gold:
		boosted = item.boosted
		if item.sprite.texture != null:
			texture_path = item.sprite.texture.resource_path
	elif item.consumable_data != null:
		consumable_id = item.consumable_data.my_id
	_events.append([EVENT_ITEM_DROP, item.lan_net_id, kind, texture_path, consumable_id, item.global_position, item.rotation, item.push_back_destination, item.scale.x, boosted])


# Called by the item.gd extension before vanilla handles a pickup, on both sides.
func on_item_picked_up(item: Node, player_index: int) -> void :
	var net_id: int = item.lan_net_id
	if _items.get(net_id) != item:
		return
	var _erased = _items.erase(net_id)
	_erased = _item_targets.erase(net_id)
	_erased = _item_scales.erase(net_id)
	# The gold bag (player -1) collects everything at the end of the wave, on every machine. Mid-
	# wave, player -1 is an entity that ate the item (the evil mob eats materials).
	if is_host and (player_index >= 0 or not _main._cleaning_up):
		_events.append([EVENT_ITEM_PICKUP, net_id, player_index])


# Called by the main.gd extension before vanilla's despawn_consumable (a fruit eaten by a pet).
func on_item_despawned(item: Node) -> void :
	var net_id: int = item.lan_net_id
	if _items.get(net_id) != item or _main._cleaning_up:
		return
	var _erased = _items.erase(net_id)
	_erased = _item_targets.erase(net_id)
	_erased = _item_scales.erase(net_id)
	item.lan_net_id = 0
	_events.append([EVENT_ITEM_DESPAWN, net_id])


# Called by the carbon_bow.gd extension: the host picked the bow's next arrow.
func on_carbon_bow_arrow(weapon: Node) -> void :
	var player = weapon._parent
	if not is_instance_valid(player) or not player is Player or _main._cleaning_up:
		return
	var weapon_index: int = player.current_weapons.find(weapon)
	if weapon_index >= 0:
		_events.append([EVENT_CARBON_ARROW, player.player_index, weapon_index, weapon._next_stat_hash])


func on_evil_mob_evolved(mob: Node, evolution: int) -> void :
	if mob.has_meta("lan_net_id") and _entities.get(mob.get_meta("lan_net_id")) == mob and not _main._cleaning_up:
		_events.append([EVENT_EVOLVE_MOB, mob.get_meta("lan_net_id"), evolution])


func on_crate_to_process(player_index: int, consumable_data: Resource) -> void :
	_events.append([EVENT_CRATE_TO_PROCESS, player_index, consumable_data.my_id])


func _check_item_attraction() -> void :
	for net_id in _items:
		var item = _items[net_id]
		if not is_instance_valid(item):
			continue
		var target: = _get_target_ref(item.attracted_by)
		if target != _item_targets[net_id]:
			_item_targets[net_id] = target
			_events.append([EVENT_ITEM_ATTRACT, net_id, target[0], target[1]])
		if item.scale.x != _item_scales[net_id]:
			_item_scales[net_id] = item.scale.x
			_events.append([EVENT_ITEM_SCALE, net_id, item.scale.x])


# [TARGET_PLAYER, player_index], [TARGET_ENTITY, net id] or [NO_TARGET, 0]. The gold bag
# (end of the wave) counts as none: every machine sends its own items there.
func _get_target_ref(node) -> Array:
	if node == null or not is_instance_valid(node):
		return [NO_TARGET, 0]
	if node is Player:
		return [TARGET_PLAYER, node.player_index]
	if node.has_meta("lan_net_id") and _entities.get(node.get_meta("lan_net_id")) == node:
		return [TARGET_ENTITY, node.get_meta("lan_net_id")]
	return [NO_TARGET, 0]


func _on_host_entity_died(entity: Node, args: Entity.DieArgs) -> void :
	var net_id = entity.get_meta("lan_net_id") if entity.has_meta("lan_net_id") else null
	if net_id == null or _entities.get(net_id) != entity:
		return
	var _erased = _entities.erase(net_id)
	_erased = _entity_sizes.erase(net_id)
	_erased = _foot_states.erase(net_id)
	_erased = _visual_behaviors.erase(net_id)
	_erased = _visual_states.erase(net_id)
	_erased = _extra_outlines.erase(net_id)
	# The clients' own clean_up_room kills everything at the end of the wave. Entity.despawn()
	# (an enemy leaving the map, a puddle evicted) also says cleaning_up, mid-wave.
	if not args.cleaning_up:
		_events.append([EVENT_DIE, net_id, args.knockback_vector])
		_net.mode.on_entity_died(_main, entity, args)
	elif not _main._cleaning_up:
		_events.append([EVENT_DESPAWN, net_id])


# Structures and pets get their data (StructureEffect, PetEffect) from the player's effects,
# which every peer holds in the same order. Other data is sent as a resource path.
func _get_data_ref(data: Resource, player_index: int):
	if data == null:
		return null
	if player_index >= 0 and player_index < RunData.get_player_count():
		var effects: Dictionary = RunData.get_player_effects(player_index)
		for key in [Keys.structures_hash, Keys.stat_pets_hash]:
			if effects.has(key) and typeof(effects[key]) == TYPE_ARRAY:
				var index: int = effects[key].find(data)
				if index >= 0:
					return [key, index]
	if not data.resource_path.empty() and data.resource_path.find("::") < 0:
		return data.resource_path
	return null


# Remote players are where their client reported them, moved on at their velocity between the
# last two states for the state's age (dead reckoning, at most MAX_EXTRAPOLATION). Not the
# pressed direction: a player blocked by another player would be moved into it and push it.
# A new state's difference to the shown position is blended out over a few ticks.
func _apply_remote_states(delta: float) -> void :
	var zone_rect: Rect2 = ZoneService.get_current_zone_rect()
	for player_index in _remote_states:
		var player = _main._players[player_index]
		if not is_instance_valid(player) or player.dead:
			continue
		var state: Dictionary = _remote_states[player_index]
		var fresh: bool = state.fresh
		if fresh:
			state.fresh = false
		else:
			state.since += delta
		var velocity: Vector2 = state.reported_velocity
		var predicted: Vector2 = state.pos + velocity * min(state.since, MAX_EXTRAPOLATION)
		if fresh:
			# The new state: fade out its difference to where the old one would show the player
			# this tick (last tick's position moved on at last tick's velocity).
			state.offset = player.global_position + state.velocity * delta - predicted
			if state.offset.length() > REMOTE_SNAP_DISTANCE:
				state.offset = Vector2.ZERO
		state.offset *= REMOTE_CORRECTION_DECAY
		state.velocity = velocity if state.since < MAX_EXTRAPOLATION else Vector2.ZERO
		var shown: Vector2 = predicted + state.offset
		_move_remote_player(player, Vector2(
			clamp(shown.x, zone_rect.position.x, zone_rect.end.x),
			clamp(shown.y, zone_rect.position.y, zone_rect.end.y)
		))
		player.lan_move = state.move
		if state.aim != Vector2.ZERO:
			player.gamepad_attack_vector = state.aim.normalized()


# Moves a remote player towards target the way vanilla moves units (test_motion, then slide),
# so it stops at the host's player (and walls) instead of being placed inside it: the host's
# kinematic player would push itself out. Far targets (a correction) are jumped to.
func _move_remote_player(player: Node, target: Vector2) -> void :
	var motion: Vector2 = target - player.global_position
	if motion.length() > REMOTE_SNAP_DISTANCE:
		player.global_position = target
		return
	if motion == Vector2.ZERO:
		return
	var start: Vector2 = player.global_position
	if not player.test_motion(motion, true, REMOTE_MOTION_MARGIN, _motion_result):
		player.global_position = target
	else:
		player.global_position += _motion_result.motion
		var slide: Vector2 = _motion_result.motion_remainder.slide(_motion_result.collision_normal)
		if not player.test_motion(slide, true, REMOTE_MOTION_MARGIN, _motion_result):
			player.global_position += slide
		else:
			player.global_position += _motion_result.motion
	# As Unit._physics_process after its own move: effect behaviours count the distance (the DLC's
	# steps: the hiker's gold and max HP, lifetime steps). A jump (snap) isn't walking.
	player._on_moved(player.global_position - start)


func _build_snapshot() -> PoolByteArray:
	_snapshot_seq += 1
	var buffer: = StreamPeerBuffer.new()
	buffer.put_u32(_snapshot_seq)
	buffer.put_u32(OS.get_ticks_msec())
	buffer.put_float(_main._wave_timer.time_left)
	buffer.put_u8(SNAPSHOT_FLAG_WAITING if _waiting else 0)
	buffer.put_float(EntityService.enemy_time_factor)
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
		var player_flags: = 0
		if player.dead:
			player_flags |= FLAG_DEAD
		if player._acid_color_applied:
			player_flags |= FLAG_ACID
		if player.petrol_puddle_count > 0:
			player_flags |= FLAG_PETROL
		buffer.put_u8(player_flags)
		var player_data = RunData.players_data[player.player_index]
		buffer.put_32(player_data.gold)
		# A double: XP gain bonuses make it fractional, and a float32 would differ from the host's.
		buffer.put_double(player_data.current_xp)
		buffer.put_u16(player_data.current_level)

	var moving: = []
	for net_id in _entities:
		var entity = _entities[net_id]
		if is_instance_valid(entity) and not entity.dead and not entity is Neutral:
			moving.append(net_id)
	buffer.put_u16(moving.size())
	for net_id in moving:
		var entity = _entities[net_id]
		buffer.put_u16(net_id)
		buffer.put_16(int(clamp(entity.global_position.x, - 32768, 32767)))
		buffer.put_16(int(clamp(entity.global_position.y, - 32768, 32767)))
		var hp_ratio: = 1.0
		if entity is Unit and entity.max_stats.health > 0:
			hp_ratio = clamp(float(entity.current_stats.health) / entity.max_stats.health, 0.0, 1.0)
		buffer.put_u8(int(round(hp_ratio * HP_SCALE)))
		var flags: = 0
		if entity is Unit and entity._is_burning:
			flags |= ENTITY_FLAG_BURNING
		if entity is Enemy:
			for outline in _enemy_outlines:
				if entity.has_outline(outline[1]):
					flags |= outline[0]
			if entity.get("is_full") == true:
				flags |= ENTITY_FLAG_FULL
			if (entity.get("sprite_full") != null or entity is Brachiosaurus or entity is Tyranosaurus) and entity.sprite.scale.x < 0:
				flags |= ENTITY_FLAG_MIRRORED
			if not entity._outline_colors.empty() or _extra_outlines.has(net_id):
				_check_extra_outlines(net_id, entity)
			if entity.get("angry_sound") != null and entity._current_movement_behavior == entity._on_triggered_movement_behavior:
				flags |= ENTITY_FLAG_ANGRY
		if not entity.visible:
			flags |= ENTITY_FLAG_HIDDEN
		buffer.put_u8(flags)
		if entity is Pursuer and _entity_sizes.get(net_id) != entity.sprite.scale.y:
			_entity_sizes[net_id] = entity.sprite.scale.y
			_events.append([EVENT_ENTITY_SIZE, net_id, entity.sprite.scale.y])
	return buffer.data_array



# Client

func on_snapshot(data: PoolByteArray) -> void :
	if data.size() < SNAPSHOT_HEADER_SIZE:
		return
	var buffer: = StreamPeerBuffer.new()
	buffer.data_array = data
	var seq: = buffer.get_u32()
	if seq <= _last_seq:
		return
	var host_time: = buffer.get_u32()
	var time_left: = buffer.get_float()
	var snapshot_flags: = buffer.get_u8()
	var time_factor: = buffer.get_float()
	var count: = buffer.get_u8()
	var entities_offset: = SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_PLAYER_SIZE
	if count != _main._players.size() or data.size() < entities_offset + 2:
		return
	buffer.seek(entities_offset)
	var entity_count: = buffer.get_u16()
	if data.size() != entities_offset + 2 + entity_count * SNAPSHOT_ENTITY_SIZE:
		return
	buffer.seek(SNAPSHOT_HEADER_SIZE)
	_last_seq = seq

	var offset: = float(OS.get_ticks_msec() - host_time)
	if _clock_offset == null or offset < _clock_offset:
		_clock_offset = offset
	else:
		_clock_offset += CLOCK_DRIFT_PER_SNAPSHOT
	_note_lateness(offset - _clock_offset)

	var positions: = []
	for player_index in count:
		var pos: = Vector2(buffer.get_float(), buffer.get_float())
		var move: = Vector2(buffer.get_8(), buffer.get_8()) / MOVE_SCALE
		var speed: = buffer.get_float()
		var health: = buffer.get_32()
		var max_health: = buffer.get_32()
		var flags: = buffer.get_u8()
		var gold: = buffer.get_32()
		var xp: = buffer.get_double()
		var level: = buffer.get_u16()
		positions.append({"pos": pos, "move": move})
		_apply_player_state(_main._players[player_index], speed, health, max_health, (flags & FLAG_DEAD) != 0)
		_apply_player_tint(_main._players[player_index], flags)
		_apply_player_progress(player_index, gold, xp, level)

	var entity_positions: = {}
	var _count = buffer.get_u16()
	for _i in entity_count:
		var net_id: = buffer.get_u16()
		entity_positions[net_id] = Vector2(buffer.get_16(), buffer.get_16())
		var entity = _entities.get(net_id)
		_apply_entity_health(entity, buffer.get_u8())
		_apply_entity_flags(entity, buffer.get_u8())
		if _pending_pivots.has(net_id):
			_apply_pivots(net_id)

	_snapshots.append({"time": host_time, "players": positions, "entities": entity_positions})
	if _snapshots.size() > MAX_BUFFERED_SNAPSHOTS:
		_snapshots.pop_front()

	var waiting: = (snapshot_flags & SNAPSHOT_FLAG_WAITING) != 0
	if waiting != _waiting and not _main._cleaning_up:
		_set_waiting(waiting)
	if not _main._cleaning_up:
		_apply_enemy_time_factor(time_factor)
	if not _main._cleaning_up and abs(_main._wave_timer.time_left - time_left) > TIMER_RESYNC_THRESHOLD and time_left > 0.0:
		_main._wave_timer.start(time_left)
		_main._wave_timer.paused = _waiting
		_main._wave_timer.half_wave_timer.paused = _waiting


# The host's enemy time slow (time shifter, pocket watch): enemy projectiles fly and enemy
# animations play slower (Projectile._get_time_factor, Enemy._apply_time_factor_to_animation in
# _update_puppets), and ShiftTimeVisualEffect follows enemy_time_slow_changed. It lasts until the
# host's factor is back at 1.
func _apply_enemy_time_factor(time_factor: float) -> void :
	if time_factor >= 1.0:
		if EntityService._enemy_time_slow_remaining > 0.0:
			EntityService.stop_enemy_time_slow()
		return
	var was_slowed: bool = EntityService._enemy_time_slow_remaining > 0.0
	EntityService.enemy_time_factor = max(EntityService.MIN_ENEMY_TIME_FACTOR, time_factor)
	EntityService._enemy_time_slow_remaining = TIME_SLOW_HOLD
	if not was_slowed:
		EntityService.emit_signal("enemy_time_slow_changed", true)


func _apply_player_state(player, speed: float, health: int, max_health: int, dead: bool) -> void :
	if not is_instance_valid(player) or player.dead:
		return
	player.lan_move_speed = speed
	if player.current_stats.health != health or player.max_stats.health != max_health:
		player.max_stats.health = max_health
		player.current_stats.health = health
		player.emit_signal("health_updated", player, health, max_health)
	if dead:
		player.die(_player_die_args())


# The acid and petrol tints of players in the host's puddles (clients' puddle copies have no areas).
func _apply_player_tint(player, flags: int) -> void :
	if not is_instance_valid(player) or player.dead:
		return
	player._set_acid_color((flags & FLAG_ACID) != 0)
	var petrol: = (flags & FLAG_PETROL) != 0
	if petrol and player.petrol_puddle_count <= 0:
		player._set_color_modulation(player.color_petrol)
		player.petrol_puddle_count = 1
	elif not petrol and player.petrol_puddle_count > 0:
		player.remove_color_modulation(player.color_petrol)
		player.petrol_puddle_count = 0


# RunData's signals drive the HUD (gold, XP bar) and, for a level-up, vanilla's on_levelled_up.
func _apply_player_progress(player_index: int, gold: int, xp: float, level: int) -> void :
	var player_data = RunData.players_data[player_index]
	if player_data.gold != gold:
		player_data.gold = gold
		RunData.emit_signal("gold_changed", gold, player_index)
	var xp_changed: bool = player_data.current_xp != xp or player_data.current_level != level
	while player_data.current_level < level:
		player_data.current_level += 1
		RunData.emit_signal("levelled_up", player_index)
	player_data.current_level = level
	if xp_changed:
		player_data.current_xp = xp
		RunData.emit_signal("xp_added", xp, RunData.get_next_level_xp_needed(player_index), player_index)


# Boss and other over-head life bars follow health_updated. The client's max HP can differ from
# the host's (elite stats, buffs), so the client copy uses the 0-255 ratio as its HP.
func _apply_entity_health(entity, health: int) -> void :
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity is Unit:
		return
	if health != entity.current_stats.health or entity.max_stats.health != HP_SCALE:
		entity.max_stats.health = int(HP_SCALE)
		entity.current_stats.health = health
		entity.emit_signal("health_updated", entity, health, entity.max_stats.health)


func _apply_entity_flags(entity, flags: int) -> void :
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity is Unit:
		return
	var hidden: = (flags & ENTITY_FLAG_HIDDEN) != 0
	if entity.visible == hidden:
		entity.visible = not hidden
		if not hidden and _is_border_charger(entity):
			# GoTowardsBorderOppositeMovementBehavior._on_warning_finished: the charge starts.
			var behavior: Node = entity._current_movement_behavior
			if entity.enemy_id == "iguanodon":
				SoundManager.playSingle(behavior.iguanodon_charge_sound, 0, 0, false, 0.5)
			elif entity.enemy_id == "oviraptor":
				SoundManager.playSingle(behavior.oviraptor_charge_sound, 0, 0, false, 0.5)
	var burning: = (flags & ENTITY_FLAG_BURNING) != 0
	if burning != entity._burning_particles.emitting:
		if burning:
			entity._burning_particles.start_emitting()
		else:
			entity._burning_particles.stop_emitting()
	if entity is Enemy:
		for outline in _enemy_outlines:
			var shown: bool = (flags & outline[0]) != 0
			if shown and not entity.has_outline(outline[1]):
				entity.add_outline(outline[1], outline[2], outline[3])
			elif not shown and entity.has_outline(outline[1]):
				entity.remove_outline(outline[1])
		if entity.get("sprite_full") != null:
			var full: = (flags & ENTITY_FLAG_FULL) != 0
			if entity.is_full != full:
				entity.is_full = full
				entity.sprite.texture = entity.sprite_full if full else entity._original_texture
			var mirrored: = (flags & ENTITY_FLAG_MIRRORED) != 0
			if (entity.sprite.scale.x < 0) != mirrored:
				entity.sprite.scale.x = - entity.sprite.scale.x
		# The brachiosaurus faces into the map from the edge it came from.
		# The brachiosaurus faces into the map, the T-rex towards its target.
		if (entity is Brachiosaurus or entity is Tyranosaurus) and (entity.sprite.scale.x < 0) != ((flags & ENTITY_FLAG_MIRRORED) != 0):
			entity.sprite.scale.x = - entity.sprite.scale.x
		if entity.get("angry_sound") != null:
			var angry: = (flags & ENTITY_FLAG_ANGRY) != 0
			if angry and entity._current_movement_behavior != entity._on_triggered_movement_behavior:
				# As Stargazer.get_angry; the movement itself comes from the host.
				entity._current_movement_behavior = entity._on_triggered_movement_behavior
				SoundManager2D.play(entity.angry_sound, entity.global_position, 5, 0.1, true)


func _count_events(events: Array) -> void :
	for event in events:
		if typeof(event) == TYPE_ARRAY and not event.empty():
			event_counts[event[0]] = event_counts.get(event[0], 0) + 1


func on_events(events: Array) -> void :
	_count_events(events)
	for event in events:
		if typeof(event) != TYPE_ARRAY or event.empty() or typeof(event[0]) != TYPE_INT:
			continue
		if event[0] == EVENT_SPAWN and event.size() == 9:
			_client_spawn(event)
		elif event[0] == EVENT_PUDDLE and event.size() == 7:
			_client_puddle(event)
		elif event[0] == EVENT_PUDDLE_END and event.size() == 2:
			_client_puddle_end(event)
		elif event[0] == EVENT_HOLE and event.size() == 2:
			_client_hole(event)
		elif event[0] == EVENT_PROJECTILE_REDIRECT and event.size() == 5:
			_client_projectile_redirect(event)
		elif event[0] == EVENT_BOOMERANG and event.size() == 7:
			_client_boomerang(event)
		elif event[0] == EVENT_DIG_SITE and event.size() == 5:
			_client_dig_site(event)
		elif event[0] == EVENT_POACHER_ZONE and event.size() == 3:
			_client_poacher_zone(event)
		elif event[0] == EVENT_POACHER_MARK and event.size() == 3:
			_client_poacher_mark(event)
		elif event[0] == EVENT_BRACHIOSAURUS and event.size() == 4:
			_client_brachiosaurus(event)
		elif event[0] == EVENT_PROJECTILE_FROM and event.size() == 5:
			_client_projectile_from(event)
		elif event[0] == EVENT_WARNING_LINE and event.size() == 5:
			_client_warning_line(event)
		elif event[0] == EVENT_JUMP and event.size() == 6:
			_client_jump(event)
		elif event[0] == EVENT_OUTLINES and event.size() == 3:
			_client_outlines(event)
		elif event[0] == EVENT_ENTITY_WEAPON and event.size() == 5:
			_client_entity_weapon(event)
		elif event[0] == EVENT_CARBON_ARROW and event.size() == 4:
			_client_carbon_arrow(event)
		elif event[0] == EVENT_PROJECTILE_LOOK and event.size() == 4:
			_client_projectile_look(event)
		elif event[0] == EVENT_EVOLVE_MOB and event.size() == 3:
			_client_evolve_mob(event)
		elif event[0] == EVENT_ITEM_DESPAWN and event.size() == 2:
			_client_item_despawn(event)
		elif event[0] == EVENT_DIE and event.size() == 3:
			_client_die(event)
		elif event[0] == EVENT_DESPAWN and event.size() == 2:
			_client_despawn(event)
		elif event[0] == EVENT_BIRTH and event.size() == 5:
			_client_birth(event)
		elif event[0] == EVENT_BIRTH_MOVED and event.size() == 3:
			_client_birth_moved(event)
		elif event[0] == EVENT_ITEM_SCALE and event.size() == 3:
			_client_item_scale(event)
		elif event[0] == EVENT_WEAPON and event.size() == 6:
			_client_weapon_shot(event)
		elif event[0] == EVENT_PROJECTILE and event.size() == 13:
			_client_projectile(event)
		elif event[0] == EVENT_PROJECTILE_STOP and event.size() == 3:
			_client_projectile_stop(event)
		elif event[0] == EVENT_ANIMATION and event.size() == 4:
			_client_animation(event)
		elif event[0] == EVENT_PIVOTS and event.size() == 3:
			_client_pivots(event)
		elif event[0] == EVENT_ENTITY_SIZE and event.size() == 3:
			_client_entity_size(event)
		elif event[0] == EVENT_DAMAGE and event.size() == 8:
			_client_damage(event)
		elif event[0] == EVENT_EXPLOSION and event.size() == 6:
			_client_explosion(event)
		elif event[0] == EVENT_ITEM_DROP and event.size() == 10:
			_client_item_drop(event)
		elif event[0] == EVENT_ITEM_ATTRACT and event.size() == 4:
			_client_item_attract(event)
		elif event[0] == EVENT_ITEM_PICKUP and event.size() == 3:
			_client_item_pickup(event)
		elif event[0] == EVENT_CRATE_TO_PROCESS and event.size() == 3:
			_client_crate_to_process(event)


func _client_spawn(event: Array) -> void :
	# [EVENT_SPAWN, net_id, type, scene path, pos, player_index, data ref, charmed_by, evolution]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_STRING:
		return
	if typeof(event[4]) != TYPE_VECTOR2 or typeof(event[5]) != TYPE_INT or typeof(event[7]) != TYPE_INT or typeof(event[8]) != TYPE_INT:
		return
	if _main._cleaning_up or not ResourceLoader.exists(event[3]):
		return
	var scene = load(event[3])
	if not scene is PackedScene:
		return
	var type: int = event[2]
	var player_index: int = event[5]
	var data = _resolve_data_ref(event[6], player_index)
	if data == null and (type == EntityType.STRUCTURE or type == EntityType.PET):
		return

	_spawn_args._init(event[4], type)
	_spawn_args.player_index = player_index
	var entity = _main._entity_spawner.spawn_entity(scene, _spawn_args, data, null, event[7])
	if entity == null:
		return
	_make_inert(entity)
	_entities[event[1]] = entity
	if event[8] != EVOLUTION_NONE and entity is Enemy:
		_client_evolve(entity, event[8])
	if _is_border_charger(entity):
		# As the behaviour's first get_movement on the host: rustling grass and shaking ferns
		# where it waits. It shows once the snapshot says it is visible.
		entity.visible = false
		SoundManager.playSingle(entity._current_movement_behavior.grass_sound, 0, 0, false, 0.5)
		_main._shake_zone_sprites(entity.global_position, 1.2)


# Primal Dread's oviraptor and iguanodon (hidden until they charge from the map's edge).
func _is_border_charger(entity: Node) -> bool:
	return entity is Enemy and entity._current_movement_behavior is GoTowardsBorderOppositeMovementBehavior


# As EvolutionSceneEffectBehavior._evolution_enemy, without the boost (the host has the stats):
# the flags, and the enemy effect behaviour that swaps the texture and adds the outline (it
# takes both off again when the enemy dies).
func _client_evolve(enemy: Node, evolution: int) -> void :
	enemy._is_mutant = evolution == EVOLUTION_MUTANT
	enemy._is_meca = evolution == EVOLUTION_MECA
	enemy.can_be_boosted = false
	var behavior_data = _evolution_behaviors.get(evolution)
	if behavior_data != null and behavior_data.get("scene") is PackedScene:
		enemy.effect_behaviors.add_child(behavior_data.scene.instance().init(enemy))


func _client_puddle(event: Array) -> void :
	# [EVENT_PUDDLE, puddle id, kind, pos, target scale, sprite index, sprite rotation]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_VECTOR2:
		return
	if typeof(event[4]) != TYPE_VECTOR2 or typeof(event[5]) != TYPE_INT or typeof(event[6]) != TYPE_REAL:
		return
	if _main._cleaning_up:
		return
	var spawner: Node = _main._gpe_spawner
	var scene: PackedScene = null
	var container: Node = _main._gpe_container
	if event[2] == PUDDLE_ACID:
		scene = spawner.acid_puddle
	elif event[2] == PUDDLE_PETROL:
		scene = spawner.petrol_puddle
	elif event[2] == PUDDLE_FIRE:
		scene = spawner.fire_puddle
		container = _main._fire_puddles_container
	if scene == null or not is_instance_valid(container):
		return
	var pool_id: int = scene.get_instance_id()
	var puddle = _main.get_node_from_pool(pool_id, container)
	if puddle == null:
		puddle = scene.instance()
		puddle.set_meta("pool_id", pool_id)
		container.add_child(puddle)
	# Only shows: no areas (the host's puddles hurt, slow and burn), no lifetime (it fades out on
	# the host's EVENT_PUDDLE_END). Init without its random sprite and rotation.
	puddle.set_deferred("monitoring", false)
	puddle.set_deferred("monitorable", false)
	puddle.global_position = event[3]
	puddle.lifetime = - 1
	if event[5] >= 0 and event[5] < puddle.puddle_sprites.size():
		puddle.sprite.texture = puddle.puddle_sprites[event[5]]
	if event[5] >= 0 and event[5] < puddle.puddle_sprites_outline.size():
		puddle.sprite_outline.texture = puddle.puddle_sprites_outline[event[5]]
	puddle.sprite.rotation = event[6]
	puddle._target_scale = event[4]
	puddle._play_spawn_tween()
	puddle.set_meta("lan_puddle_id", event[1])
	_puddles[event[1]] = puddle


func _client_puddle_end(event: Array) -> void :
	# [EVENT_PUDDLE_END, puddle id]
	if typeof(event[1]) != TYPE_INT:
		return
	var puddle = _puddles.get(event[1])
	var _erased = _puddles.erase(event[1])
	if puddle != null and is_instance_valid(puddle) and puddle.get_meta("lan_puddle_id", 0) == event[1] and puddle.is_active():
		puddle.despawn()


func _client_dig_site(event: Array) -> void :
	# [EVENT_DIG_SITE, index, digging, progress, dug_up]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_BOOL or typeof(event[3]) != TYPE_REAL or typeof(event[4]) != TYPE_BOOL:
		return
	if event[1] < 0 or event[1] >= _dig_sites.size() or not is_instance_valid(_dig_sites[event[1]]):
		return
	_dig_sites[event[1]].lan_apply_host_state(event[2], event[3], event[4])


func _client_poacher_zone(event: Array) -> void :
	# [EVENT_POACHER_ZONE, index, pos]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	if event[1] < 0 or event[1] >= _poacher_zones.size() or not is_instance_valid(_poacher_zones[event[1]]):
		return
	_poacher_zones[event[1]].relocate(event[2])


# As PoacherZoneSceneEffectBehavior._on_poacher_enemy_killed_in_zone: a mark where the enemy died,
# and that player's zones flash.
func _client_poacher_mark(event: Array) -> void :
	# [EVENT_POACHER_MARK, player_index, pos]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2 or _main._cleaning_up:
		return
	if _poacher_mark != null:
		var mark: Node2D = _poacher_mark.instance()
		mark.global_position = event[2]
		_main._gpe_container.add_child(mark)
	for zone in _poacher_zones:
		if is_instance_valid(zone) and zone.player_index == event[1]:
			zone._on_poacher_enemy_killed_in_zone(event[1], event[2])


func _client_brachiosaurus(event: Array) -> void :
	# [EVENT_BRACHIOSAURUS, net id, kind, value]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT:
		return
	var entity = _entities.get(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead:
		return
	if event[2] == BRACHIOSAURUS_STATE and typeof(event[3]) == TYPE_INT and entity is Brachiosaurus:
		entity.lan_apply_host_state(event[3])
	elif event[2] == BRACHIOSAURUS_MOUTH and typeof(event[3]) == TYPE_STRING and _get_mouth_player(entity) != null:
		var mouth: AnimationPlayer = _get_mouth_player(entity)
		if mouth.has_animation(event[3]):
			if event[3].begins_with("open_mouth") and mouth.get("_audio_shoot") != null:
				mouth._audio_shoot.pitch_scale = rand_range(0.8, 1.2)
				mouth._audio_shoot.play()
			mouth.play(event[3])
	elif event[2] == BRACHIOSAURUS_FOOT and typeof(event[3]) == TYPE_INT and entity is BrachiosaurusFoot:
		var mask: int = event[3]
		entity.sprite.visible = (mask & FOOT_SHADOW) != 0
		entity._sprite_foot.visible = (mask & FOOT_FOOT) != 0
		entity._sprite_release.visible = (mask & FOOT_RELEASE) != 0
		entity._sprite_foot.flip_h = (mask & FOOT_FLIPPED) != 0


func _client_projectile_from(event: Array) -> void :
	# [EVENT_PROJECTILE_FROM, id, shooter net id, target kind, target id]
	for i in [1, 2, 3, 4]:
		if typeof(event[i]) != TYPE_INT:
			return
	var projectile = _projectiles.get(event[1])
	var from = _entities.get(event[2])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1]:
		return
	if from == null or not is_instance_valid(from):
		return
	projectile._hitbox.from = from
	if projectile is EnemyLaser:
		projectile.offset_from_parent = projectile.global_position - from.global_position
	elif projectile is EnemyLaserFollow:
		var target = null
		if event[3] == TARGET_PLAYER and event[4] >= 0 and event[4] < _main._players.size():
			target = _main._players[event[4]]
		elif event[3] == TARGET_ENTITY:
			target = _entities.get(event[4])
		if target != null and is_instance_valid(target):
			projectile.target = target


func _client_hole(event: Array) -> void :
	# [EVENT_HOLE, pos]
	if typeof(event[1]) != TYPE_VECTOR2 or _main._cleaning_up:
		return
	var spawner: Node = _main._gpe_spawner
	spawner.lan_from_host = true
	spawner.spawn_single_hole_at_position(event[1])
	spawner.lan_from_host = false


func _resolve_data_ref(ref, player_index: int):
	if typeof(ref) == TYPE_STRING:
		return load(ref) if ResourceLoader.exists(ref) else null
	if typeof(ref) != TYPE_ARRAY or ref.size() != 2 or typeof(ref[0]) != TYPE_INT or typeof(ref[1]) != TYPE_INT:
		return null
	if player_index < 0 or player_index >= RunData.get_player_count():
		return null
	var effects: Dictionary = RunData.get_player_effects(player_index)
	if not effects.has(ref[0]) or typeof(effects[ref[0]]) != TYPE_ARRAY:
		return null
	var list: Array = effects[ref[0]]
	if ref[1] < 0 or ref[1] >= list.size() or not list[ref[1]] is Resource:
		return null
	return list[ref[1]]


# The host simulates; the client copy only shows. Kinematic, so setting the position moves it.
# Its mask keeps only the walls (a dying unit's knockback slide): copies don't push each other,
# and the physics server doesn't pair them (perf). The layer stays, so weapon ranges see them.
func _make_inert(entity: Node) -> void :
	entity.set_physics_process(false)
	entity.mode = RigidBody2D.MODE_KINEMATIC
	entity.collision_mask &= Utils.OBSTACLES_BIT
	# Pursuers grow on their own timer; the host's growth comes as EVENT_ENTITY_SIZE.
	if entity is Pursuer:
		entity._boost_timer.stop()
	for area in _find_areas(entity, []):
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)


func _find_areas(node: Node, result: Array) -> Array:
	if node is Area2D:
		result.append(node)
	for child in node.get_children():
		var _r = _find_areas(child, result)
	return result


func _client_die(event: Array) -> void :
	# [EVENT_DIE, net_id, knockback]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	var entity = _entities.get(event[1])
	var _erased = _entities.erase(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead:
		return
	var args: = Entity.DieArgs.new()
	# Not killed by a player here, so no loot, kill effects or stats on the client.
	args.enemy_killed_by_player = false
	args.knockback_vector = event[2]
	if entity is Unit:
		# Vanilla's physics slides the corpse with the knockback (enemies skip the rest when dead).
		entity.set_physics_process(true)
	entity.die(args)



func _client_despawn(event: Array) -> void :
	# [EVENT_DESPAWN, net_id]
	if typeof(event[1]) != TYPE_INT:
		return
	var entity = _entities.get(event[1])
	var _erased = _entities.erase(event[1])
	if entity != null and is_instance_valid(entity) and not entity.dead and entity.has_method("despawn"):
		entity.despawn()


func _client_birth(event: Array) -> void :
	# [EVENT_BIRTH, birth id, type, pos, charmed_by]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_VECTOR2 or typeof(event[4]) != TYPE_INT:
		return
	if _main._cleaning_up:
		return
	var request: = SpawnRequest.new(event[2], null, event[3])
	request.charmed_by = event[4]
	_main._entity_spawner.spawn_entity_birth(request)
	var container: Node = _main._births_container
	if container.get_child_count() > 0:
		var birth: Node = container.get_child(container.get_child_count() - 1)
		if birth.has_meta("lan_birth_id"):
			var _erased = _births.erase(birth.get_meta("lan_birth_id"))
		birth.set_meta("lan_birth_id", event[1])
		_births[event[1]] = birth


func _client_birth_moved(event: Array) -> void :
	# [EVENT_BIRTH_MOVED, birth id, pos]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	var birth = _births.get(event[1])
	if birth == null or not is_instance_valid(birth) or not birth.visible or birth.get_meta("lan_birth_id") != event[1]:
		var _erased = _births.erase(event[1])
		return
	# As vanilla does when it moves the marker: the countdown starts over.
	birth.global_position = event[2]
	birth._current_time_before_spawn = birth.time_before_spawn


func _client_item_scale(event: Array) -> void :
	# [EVENT_ITEM_SCALE, net id, scale]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_REAL:
		return
	var item = _items.get(event[1])
	if item != null and is_instance_valid(item):
		item.scale = Vector2(event[2], event[2])


func _client_weapon_shot(event: Array) -> void :
	# [EVENT_WEAPON, player_index, weapon_index, rotation, distance, attack type]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[5]) != TYPE_INT:
		return
	if typeof(event[3]) != TYPE_REAL or typeof(event[4]) != TYPE_REAL:
		return
	if event[1] < 0 or event[1] >= _main._players.size():
		return
	var player = _main._players[event[1]]
	if not is_instance_valid(player) or player.dead or event[2] < 0 or event[2] >= player.current_weapons.size():
		return
	_show_weapon_attack(player.current_weapons[event[2]], event[3], event[4], event[5])


# A weapon's attack from the host: melee weapons swing, ranged ones recoil. One that comes while
# the weapon still swings waits.
func _show_weapon_attack(weapon, rotation: float, distance: float, attack_type: int) -> void :
	if not is_instance_valid(weapon):
		return
	if weapon._is_shooting:
		_pending_weapon_events[weapon] = [rotation, distance, attack_type]
		return
	weapon.rotation = rotation
	if weapon is MeleeWeapon and attack_type != RANGED_ATTACK:
		weapon.next_attack_type = attack_type
		weapon._shooting_behavior.shoot(distance)
	else:
		_client_ranged_recoil(weapon)


# Attacks that came during a swing play once it is over.
func _play_pending_weapon_events() -> void :
	if _pending_weapon_events.empty():
		return
	for weapon in _pending_weapon_events.keys():
		if is_instance_valid(weapon) and weapon._is_shooting:
			continue
		var attack: Array = _pending_weapon_events[weapon]
		var _erased = _pending_weapon_events.erase(weapon)
		if is_instance_valid(weapon):
			_show_weapon_attack(weapon, attack[0], attack[1], attack[2])


func _client_entity_weapon(event: Array) -> void :
	# [EVENT_ENTITY_WEAPON, net id, rotation, distance, attack type]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_REAL or typeof(event[3]) != TYPE_REAL or typeof(event[4]) != TYPE_INT:
		return
	var entity = _entities.get(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity.get("_weapon") is Weapon:
		return
	_show_weapon_attack(entity._weapon, event[2], event[3], event[4])


func _client_carbon_arrow(event: Array) -> void :
	# [EVENT_CARBON_ARROW, player_index, weapon index, stat hash]
	for i in [1, 2, 3]:
		if typeof(event[i]) != TYPE_INT:
			return
	if event[1] < 0 or event[1] >= _main._players.size():
		return
	var player = _main._players[event[1]]
	if not is_instance_valid(player) or event[2] < 0 or event[2] >= player.current_weapons.size():
		return
	var weapon = player.current_weapons[event[2]]
	if is_instance_valid(weapon) and weapon is CarbonBowWeapon:
		weapon._next_stat_hash = event[3]
		weapon._show_next_arrow()


func _client_projectile_look(event: Array) -> void :
	# [EVENT_PROJECTILE_LOOK, id, texture path, sprite scale]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_STRING or typeof(event[3]) != TYPE_REAL:
		return
	var projectile = _projectiles.get(event[1])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1]:
		return
	if ResourceLoader.exists(event[2]):
		projectile._sprite.texture = load(event[2])
		projectile._sprite.scale = Vector2(event[3], event[3])


func _client_warning_line(event: Array) -> void :
	# [EVENT_WARNING_LINE, net id, behaviour index, shown, line end]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_BOOL or typeof(event[4]) != TYPE_VECTOR2:
		return
	var behavior = _get_visual_behavior(event[1], event[2])
	if not behavior is WarningChargingAttackBehavior or not is_instance_valid(behavior._warning_line):
		return
	var line: Line2D = behavior._warning_line
	line.visible = event[3]
	if event[3]:
		line.points = PoolVector2Array([event[4].normalized() * 50.0, event[4]])


# As JumpAttackBehavior._try_start_jump without the move (the snapshot brings the arc): the
# landing marker and the flip now, the shadow in _update_jumps.
func _client_jump(event: Array) -> void :
	# [EVENT_JUMP, net id, behaviour index, start, target, flipped]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_VECTOR2 or typeof(event[4]) != TYPE_VECTOR2 or typeof(event[5]) != TYPE_BOOL:
		return
	var behavior = _get_visual_behavior(event[1], event[2])
	if not behavior is JumpAttackBehavior:
		return
	var entity = _entities.get(event[1])
	entity.sprite.flip_h = event[5]
	if behavior._shadow != null and not _jumps.has(event[1]):
		behavior._ground_position = behavior._shadow.position
	behavior._target_position = event[4]
	if behavior._land_shadow_warning != null:
		behavior._land_shadow_warning.global_position = event[4]
		behavior._land_shadow_warning.visible = true
	_jumps[event[1]] = {"behavior": behavior, "time": 0.0}


# JumpAttackBehavior._process_jump's shadow and marker, and its landing (sound, marker off).
func _update_jumps(delta: float) -> void :
	if _jumps.empty():
		return
	for net_id in _jumps.keys():
		var jump: Dictionary = _jumps[net_id]
		var behavior = jump.behavior
		var entity = _entities.get(net_id)
		if not is_instance_valid(behavior) or entity == null or not is_instance_valid(entity) or entity.dead:
			var _erased = _jumps.erase(net_id)
			continue
		jump.time += delta
		if jump.time < behavior.jump_delay:
			continue
		var progress: float = (jump.time - behavior.jump_delay) / behavior.jump_duration
		if progress >= 1.0:
			SoundManager.playSingle(behavior.land_sound, 0, 0, true, 0.5)
			if behavior._shadow != null:
				behavior._shadow.position.y = behavior._ground_position.y
				behavior._shadow.scale = Vector2.ONE * 2.0
			if behavior._land_shadow_warning != null:
				behavior._land_shadow_warning.visible = false
			var _erased = _jumps.erase(net_id)
			continue
		var vertical_t: float = progress
		if progress >= 0.5:
			vertical_t = 0.5 + ease((progress - 0.5) * 2.0, - 3.0) * 0.5
		behavior._update_shadow(sin(vertical_t * PI) * behavior.jump_height)
		if behavior._land_shadow_warning != null:
			behavior._land_shadow_warning.global_position = behavior._target_position


func _get_visual_behavior(net_id: int, index: int):
	var entity = _entities.get(net_id)
	if entity == null or not is_instance_valid(entity) or entity.dead:
		return null
	if not _visual_behaviors.has(net_id):
		_visual_behaviors[net_id] = _find_visual_behaviors(entity, [])
	var behaviors: Array = _visual_behaviors[net_id]
	if index < 0 or index >= behaviors.size() or not is_instance_valid(behaviors[index]):
		return null
	return behaviors[index]


func _client_outlines(event: Array) -> void :
	# [EVENT_OUTLINES, net id, [colour html, ...]]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_ARRAY:
		return
	var entity = _entities.get(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity is Enemy:
		return
	for html in _extra_outlines.get(event[1], []):
		if not html in event[2]:
			entity.remove_outline(Color(html))
	var shown: = []
	for html in event[2]:
		if typeof(html) != TYPE_STRING:
			continue
		if not entity.has_outline(Color(html)):
			entity.add_outline(Color(html), 1.0, 0.0)
		shown.append(html)
	_extra_outlines[event[1]] = shown


# The visible part of RangedWeaponShootingBehavior.shoot, without the projectiles.
func _client_ranged_recoil(weapon: Node) -> void :
	var stats = weapon.current_stats
	SoundManager.play(Utils.get_rand_element(stats.shooting_sounds), stats.sound_db_mod, 0.2)
	var initial_position: Vector2 = weapon.sprite.position
	weapon.set_shooting(true)
	weapon.tween.interpolate_property(weapon.sprite, "position", initial_position, Vector2(initial_position.x - stats.recoil, initial_position.y), stats.recoil_duration, Tween.TRANS_EXPO, Tween.EASE_OUT)
	weapon.tween.start()
	yield(weapon.tween, "tween_all_completed")
	if not is_instance_valid(weapon):
		return
	weapon.tween.interpolate_property(weapon.sprite, "position", weapon.sprite.position, initial_position, stats.recoil_duration, Tween.TRANS_EXPO, Tween.EASE_OUT)
	weapon.tween.start()
	yield(weapon.tween, "tween_all_completed")
	if is_instance_valid(weapon):
		weapon.set_shooting(false)


func _client_projectile(event: Array) -> void :
	# [EVENT_PROJECTILE, net_id, scene path, pos, velocity, rotation, speed, max range, is_enemy,
	#  sinusoidal motion, sinusoidal motion speed, bullet-hell direction, hue (-1: none)]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_STRING or typeof(event[3]) != TYPE_VECTOR2 or typeof(event[4]) != TYPE_VECTOR2:
		return
	if typeof(event[9]) != TYPE_VECTOR2 or typeof(event[10]) != TYPE_VECTOR2 or typeof(event[11]) != TYPE_VECTOR2:
		return
	if typeof(event[5]) != TYPE_REAL or typeof(event[6]) != TYPE_REAL or typeof(event[7]) != TYPE_INT or typeof(event[8]) != TYPE_BOOL:
		return
	if typeof(event[12]) != TYPE_REAL:
		return
	if _main._cleaning_up:
		return
	var scene = _load_scene(event[2])
	if scene == null:
		return
	var container = _main._enemy_projectiles if event[8] else _main._player_projectiles
	if not is_instance_valid(container):
		return
	var pool_id: int = scene.get_instance_id()
	var projectile = _main.get_node_from_pool(pool_id, container)
	if not is_instance_valid(projectile):
		projectile = scene.instance()
		if not projectile is Projectile or projectile is GroupOfBullet or (not event[8] and not projectile is PlayerProjectile):
			projectile.free()
			return
		projectile.set_meta("pool_id", pool_id)
		if event[8]:
			_main.add_enemy_projectile(projectile)
		else:
			_main.add_player_projectile(projectile)

	# A pooled copy may still hold the shooter of its last flight (EVENT_PROJECTILE_FROM).
	projectile._hitbox.from = null
	projectile.global_position = event[3]
	projectile.velocity = event[4]
	projectile.rotation = event[5]
	projectile.sinusoidal_motion = event[9]
	projectile.sinusoidal_motion_speed = event[10]
	if projectile is BulletHellProjectile:
		projectile.direction = event[11]
	if projectile is PlayerProjectile:
		# PlayerProjectile.shoot reads speed and range from the weapon stats.
		var stats: = RangedWeaponStats.new()
		stats.projectile_speed = int(event[6])
		stats.max_range = event[7]
		projectile.set_weapon_stats(stats)
		projectile.spawn_position = event[3]
	if event[12] >= 0.0:
		projectile.set_sprite_material(_get_hue_material(event[12]))
	projectile.shoot()
	for area in _find_areas(projectile, []):
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	projectile.lan_net_id = event[1]
	_projectiles[event[1]] = projectile


func _get_hue_material(hue: float) -> ShaderMaterial:
	if not _hue_materials.has(hue):
		var material: ShaderMaterial = HUE_SHIFT_MATERIAL.duplicate()
		material.set_shader_param("hue", hue)
		_hue_materials[hue] = material
	return _hue_materials[hue]


func _client_projectile_redirect(event: Array) -> void :
	# [EVENT_PROJECTILE_REDIRECT, net_id, pos, velocity, rotation]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2 or typeof(event[3]) != TYPE_VECTOR2 or typeof(event[4]) != TYPE_REAL:
		return
	var projectile = _projectiles.get(event[1])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1]:
		return
	projectile.global_position = event[2]
	projectile.velocity = event[3]
	projectile.rotation = event[4]


func _client_boomerang(event: Array) -> void :
	# [EVENT_BOOMERANG, net_id, carrier kind, carrier id, start, direction, reach]
	for i in [1, 2, 3]:
		if typeof(event[i]) != TYPE_INT:
			return
	if typeof(event[4]) != TYPE_VECTOR2 or typeof(event[5]) != TYPE_REAL or typeof(event[6]) != TYPE_REAL:
		return
	var projectile = _projectiles.get(event[1])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1] or not projectile is BoomerangProjectile:
		return
	var carrier = null
	if event[2] == TARGET_PLAYER and event[3] >= 0 and event[3] < _main._players.size():
		carrier = _main._players[event[3]]
	elif event[2] == TARGET_ENTITY:
		carrier = _entities.get(event[3])
	if carrier == null or not is_instance_valid(carrier):
		return
	projectile.global_position = event[4]
	projectile.start_flight(carrier, event[5], event[6])


func _client_projectile_stop(event: Array) -> void :
	# [EVENT_PROJECTILE_STOP, net_id, pos]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_VECTOR2:
		return
	var projectile = _projectiles.get(event[1])
	if projectile == null or not is_instance_valid(projectile) or projectile.lan_net_id != event[1]:
		return
	projectile.global_position = event[2]
	projectile.stop()


func _client_animation(event: Array) -> void :
	# [EVENT_ANIMATION, net_id, animation, playback speed]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_STRING or typeof(event[3]) != TYPE_REAL:
		return
	var entity = _entities.get(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead:
		return
	var player: AnimationPlayer = entity._animation_player
	if player.has_animation(event[2]):
		player.playback_speed = event[3]
		player.play(event[2])


func _client_pivots(event: Array) -> void :
	# [EVENT_PIVOTS, net_id, [[direction, rotation], ...]]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_ARRAY:
		return
	for entry in event[2]:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 2 or typeof(entry[0]) != TYPE_REAL or typeof(entry[1]) != TYPE_REAL:
			return
	_pending_pivots[event[1]] = event[2]
	_apply_pivots(event[1])


# Applies the host's pivots once the copy has as many (else again with the next snapshot).
func _apply_pivots(net_id: int) -> void :
	var entity = _entities.get(net_id)
	if entity == null or not is_instance_valid(entity) or entity.dead:
		var _erased = _pending_pivots.erase(net_id)
		return
	var data: Array = _pending_pivots[net_id]
	var pivots: = _find_pivots(entity, [])
	if pivots.size() != data.size():
		return
	for i in pivots.size():
		pivots[i].direction = data[i][0]
		pivots[i].rotation = data[i][1]
	var _erased = _pending_pivots.erase(net_id)


# A Pursuer grown (or shrunk back, the DLC's anglerfish) on the host. set_size adds to the size.
func _client_entity_size(event: Array) -> void :
	# [EVENT_ENTITY_SIZE, net_id, sprite scale]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_REAL:
		return
	var entity = _entities.get(event[1])
	if entity == null or not is_instance_valid(entity) or entity.dead or not entity is Pursuer:
		return
	if abs(event[2] - entity.sprite.scale.y) > 0.001:
		entity.set_size(event[2] - entity.sprite.scale.y)


func _client_damage(event: Array) -> void :
	# [EVENT_DAMAGE, target kind, net id or player index, value, knockback direction, flags,
	#  hit type, effect scale]
	for i in [1, 2, 3, 5, 6]:
		if typeof(event[i]) != TYPE_INT:
			return
	if typeof(event[4]) != TYPE_VECTOR2 or typeof(event[7]) != TYPE_REAL:
		return
	var unit = null
	if event[1] == TARGET_PLAYER:
		if event[2] >= 0 and event[2] < _main._players.size():
			unit = _main._players[event[2]]
	else:
		unit = _entities.get(event[2])
	if unit == null or not is_instance_valid(unit) or unit.dead:
		return

	var value: int = event[3]
	var flags: int = event[5]
	var is_crit: = (flags & DAMAGE_CRIT) != 0
	var is_dodge: = (flags & DAMAGE_DODGE) != 0
	# Unit.take_damage: flash on damage, hurt / crit / dodge sound.
	if value > 0:
		unit.flash()
	var sounds = unit.hurt_sounds
	if is_dodge:
		sounds = unit.dodge_sounds
	elif is_crit:
		sounds = unit.crit_sounds
	if typeof(sounds) == TYPE_ARRAY and not sounds.empty():
		SoundManager2D.play(Utils.get_rand_element(sounds), unit.global_position, 0, 0.2)
	var args: = TakeDamageArgs.new(RunData.DUMMY_PLAYER_INDEX)
	args.base_effect_scale = event[7]
	unit.emit_signal("took_damage", unit, value, event[4], is_crit, is_dodge, (flags & DAMAGE_PROTECTED) != 0, (flags & DAMAGE_ARMOR) != 0, args, event[6], (flags & DAMAGE_ONE_SHOT) != 0)


func _client_explosion(event: Array) -> void :
	# [EVENT_EXPLOSION, scene path, pos, scale, smoke amount, sound db]
	if typeof(event[1]) != TYPE_STRING or typeof(event[2]) != TYPE_VECTOR2 or typeof(event[3]) != TYPE_REAL:
		return
	if typeof(event[4]) != TYPE_INT or typeof(event[5]) != TYPE_REAL:
		return
	var scene = _load_scene(event[1])
	if scene == null:
		return
	var pool_id: int = scene.get_instance_id()
	var instance = _main.get_node_from_pool(pool_id, _main._explosions)
	if instance == null:
		instance = scene.instance()
		if not instance is PlayerExplosion:
			instance.free()
			return
		_main.add_explosion(instance)
	instance.pool_id = pool_id
	instance.player_index = - 1
	instance.global_position = event[2]
	instance.sound_db_mod = event[5]
	instance.set_smoke_amount(event[4])
	instance.scale = Vector2(event[3], event[3])
	for area in _find_areas(instance, []):
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	# PlayerExplosion.start_explosion without its fire puddle (it reads the player's effects, and
	# player -1 has none): the host's puddles reach clients on their own.
	instance._hitbox.enable()
	instance._hitbox.from = instance
	instance._sprite.modulate.a = ProgressData.settings.explosion_opacity
	instance._animation_player.play("explode")


func _client_item_drop(event: Array) -> void :
	# [EVENT_ITEM_DROP, net id, kind, texture path, consumable id, pos, rotation, push-back target,
	#  scale, boosted]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_STRING or typeof(event[4]) != TYPE_STRING:
		return
	if typeof(event[5]) != TYPE_VECTOR2 or typeof(event[6]) != TYPE_REAL or typeof(event[7]) != TYPE_VECTOR2 or typeof(event[8]) != TYPE_REAL or typeof(event[9]) != TYPE_INT:
		return
	if _main._cleaning_up:
		return
	var is_gold: bool = event[2] == ITEM_GOLD
	var consumable_data = null
	var texture = null
	if is_gold:
		if not event[3].empty() and ResourceLoader.exists(event[3]):
			texture = load(event[3])
	else:
		consumable_data = LanGame.get_consumable(event[4])
		if consumable_data == null:
			return
		texture = consumable_data.icon

	var pool_id: int = _main._gold_pool_id if is_gold else _main._consumable_pool_id
	var container: Node = _main._materials_container if is_gold else _main._consumables_container
	var item = _main.get_node_from_pool(pool_id, container)
	if item == null:
		item = (_main.gold_scene if is_gold else _main.consumable_scene).instance()
		container.add_child(item)
	item.already_picked_up = false
	if is_gold:
		item.boosted = event[9]
		item.scale = Vector2(event[8], event[8])
		_main._active_golds.push_back(item)
	else:
		item.consumable_data = consumable_data
		_main._consumables.push_back(item)
	if texture != null:
		item.set_texture(texture)
	item.drop(event[5], event[6], event[7])
	item.lan_net_id = event[1]
	_items[event[1]] = item


func _client_item_attract(event: Array) -> void :
	# [EVENT_ITEM_ATTRACT, net id, target kind, target id]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT or typeof(event[3]) != TYPE_INT:
		return
	var item = _items.get(event[1])
	if item == null or not is_instance_valid(item) or _main._cleaning_up:
		return
	var target = null
	if event[2] == TARGET_PLAYER and event[3] >= 0 and event[3] < _main._players.size():
		target = _main._players[event[3]]
	elif event[2] == TARGET_ENTITY:
		target = _entities.get(event[3])
	if target != null and not is_instance_valid(target):
		target = null
	item.attracted_by = target
	if target != null:
		item.set_physics_process(true)


func _client_item_pickup(event: Array) -> void :
	# [EVENT_ITEM_PICKUP, net id, player_index]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT:
		return
	var item = _items.get(event[1])
	var _erased = _items.erase(event[1])
	if item == null or not is_instance_valid(item) or item.already_picked_up or item.lan_net_id != event[1]:
		return
	item.already_picked_up = true
	item.lan_net_id = 0
	if event[2] < 0:
		# Eaten by an entity (evil mob): it just goes, without a player's pickup effects.
		if item is Gold:
			_main._active_golds.erase(item)
			_main.add_node_to_pool(item, _main._gold_pool_id)
		else:
			_main._consumables.erase(item)
			_main.add_node_to_pool(item, _main._consumable_pool_id)
		item.reset()
		return
	# What main.on_gold_picked_up / on_consumable_picked_up and Item.pickup show.
	if item is Gold:
		_main._active_golds.erase(item)
		if ProgressData.settings.alt_gold_sounds:
			SoundManager.play(Utils.get_rand_element(_main.gold_alt_pickup_sounds), - 5, 0.2)
		else:
			SoundManager.play(Utils.get_rand_element(_main.gold_pickup_sounds), 0, 0.2)
		_main._effects_manager.on_gold_picked_up(item, event[2])
		_main._floating_text_manager.on_gold_picked_up(item, event[2])
		_main.add_node_to_pool(item, _main._gold_pool_id)
	else:
		_main._consumables.erase(item)
		if item.consumable_data != null:
			SoundManager.play(Utils.get_rand_element(item.consumable_data.pickup_sounds))
		_main.add_node_to_pool(item, _main._consumable_pool_id)
	item.reset()


func _client_evolve_mob(event: Array) -> void :
	# [EVENT_EVOLVE_MOB, net id, evolution]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_INT:
		return
	var mob = _entities.get(event[1])
	if mob == null or not is_instance_valid(mob) or mob.dead or not mob is EvilMob:
		return
	if event[2] > mob.evolution and event[2] < mob.quantity_to_evolve.size() and event[2] < mob.textures_evolution.size():
		mob.evolve(event[2])
		# Its HP is the host's ratio (_apply_entity_health); evolve multiplied the copy's.
		mob.max_stats.health = int(HP_SCALE)
		mob.current_stats.health = int(min(mob.current_stats.health, HP_SCALE))
		mob.emit_signal("health_updated", mob, mob.current_stats.health, mob.max_stats.health)


func _client_item_despawn(event: Array) -> void :
	# [EVENT_ITEM_DESPAWN, net id]
	if typeof(event[1]) != TYPE_INT:
		return
	var item = _items.get(event[1])
	var _erased = _items.erase(event[1])
	if item == null or not is_instance_valid(item) or item.lan_net_id != event[1] or not item is Consumable:
		return
	item.lan_net_id = 0
	_main.despawn_consumable(item)


func _client_crate_to_process(event: Array) -> void :
	# [EVENT_CRATE_TO_PROCESS, player_index, consumable id]
	if typeof(event[1]) != TYPE_INT or typeof(event[2]) != TYPE_STRING:
		return
	if event[1] < 0 or event[1] >= _main._players.size():
		return
	var consumable_data = LanGame.get_consumable(event[2])
	if consumable_data != null:
		_main._things_to_process_player_containers[event[1]].consumables.add_element(consumable_data)
		# Mutation fruit and meca parts: shown until the wave ends (main._clear_displayed_consumables_ui).
		if _main._lan_is_evolution_consumable(consumable_data):
			_main._displayed_consumables_picked_up[event[1]].push_back(consumable_data)


func _load_scene(path: String):
	if not _scene_cache.has(path):
		var scene = load(path) if ResourceLoader.exists(path) else null
		_scene_cache[path] = scene if scene is PackedScene else null
	return _scene_cache[path]


func _send_own_state() -> void :
	if _local_index < 0 or _local_index >= _main._players.size():
		return
	var player = _main._players[_local_index]
	if not is_instance_valid(player) or player.dead:
		return
	# is_manual_aim returns null rather than false when manual aim is off.
	var manual_aim: bool = Utils.is_manual_aim(_local_index) == true
	var aim: Vector2 = player.gamepad_attack_vector * GAMEPAD_AIM_DISTANCE
	if manual_aim and not Utils.is_player_using_gamepad(_local_index):
		aim = player.get_global_mouse_position() - player.global_position
	_net.send_player_state(player.global_position, player._current_movement, aim, manual_aim)


# Sets the interpolation delay from the recent lateness: up at once, down slowly.
func _note_lateness(late: float) -> void :
	_lateness.append(late)
	if _lateness.size() > LATENESS_WINDOW:
		_lateness.pop_front()
	var target: float = clamp(_lateness.max() + LATENESS_MARGIN_MS, INTERP_DELAY_MS, MAX_INTERP_DELAY_MS)
	if target > _interp_delay:
		_interp_delay = target
	else:
		_interp_delay += (target - _interp_delay) * INTERP_DELAY_DECAY


# Puppets show where the host had them at the render clock (the interpolation delay ago),
# between the two snapshots around that time (or the newest one if none is newer). The clock
# moves by the physics step, so puppets move the same amount every tick (not by the uneven
# moments a tick runs at, nor in steps of whole milliseconds), and offset or delay changes
# are taken gradually.
func _update_puppets(delta: float) -> void :
	if _snapshots.empty() or _clock_offset == null:
		return
	var target: float = OS.get_ticks_msec() - _clock_offset - _interp_delay
	if _render_time == null or abs(target - _render_time) > RENDER_CLOCK_SNAP_MS:
		_render_time = target
	else:
		var rate: float = clamp(1.0 + (target - _render_time) / 1000.0, 1.0 - MAX_RENDER_CLOCK_RATE, 1.0 + MAX_RENDER_CLOCK_RATE)
		_render_time += delta * 1000.0 * rate
	var render_time: float = _render_time
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

	for net_id in _entities:
		var entity = _entities[net_id]
		if not is_instance_valid(entity) or entity.dead:
			continue
		var a = from.entities.get(net_id)
		var b = to.entities.get(net_id)
		if a == null and b == null:
			continue
		if a == null:
			a = b
		elif b == null:
			b = a
		entity.global_position = a.linear_interpolate(b, weight)
		if entity is Unit:
			entity.update_animation(b - a)
		# Enemy._physics_process (off on copies) slows the animations with the enemy time factor.
		if entity is Enemy:
			entity._apply_time_factor_to_animation(entity.get_time_factor())
			# A charging oviraptor or iguanodon faces along its path, as the host's behaviour
			# turns it (upright when it runs left). Not on the step where the host moved it up or
			# down to its lane.
			var path: Vector2 = b - a
			if entity.visible and abs(path.x) > abs(path.y) and _is_border_charger(entity):
				entity.rotation = path.angle() + (PI if path.x < 0 else 0.0)


# Holds the wave timer (enemy spawns follow it) and its half-wave timer.
func _set_waiting(value: bool) -> void :
	if is_host and _waiting and not value:
		var reason: = "every client loaded" if _waiting_peers.empty() else "timed out"
		ModLoaderLog.info("Wave starts after %.1f s (%s)" % [_waiting_time, reason], NetProtocol.MOD_ID)
	_waiting = value
	_main._wave_timer.paused = value
	_main._wave_timer.half_wave_timer.paused = value
	_waiting_label.visible = value


func _add_waiting_label() -> void :
	var font: DynamicFont = WAITING_FONT.duplicate()
	font.size = WAITING_FONT_SIZE
	font.outline_size = 3
	font.outline_color = Color.black
	_waiting_label = Label.new()
	_waiting_label.name = "LanWaitingLabel"
	_waiting_label.text = "LAN_WAITING_FOR_PLAYERS"
	_waiting_label.align = Label.ALIGN_CENTER
	_waiting_label.anchor_right = 1.0
	_waiting_label.margin_top = 180
	_waiting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waiting_label.add_font_override("font", font)
	_waiting_label.visible = false
	_main.get_node("UI/HUD").add_child(_waiting_label)


# Host event: the wave ends (time out or everyone dead), with the host's
# [wave failed, run lost, run won].
func on_wave_cleanup(run_states: Array) -> void :
	if run_states.size() != 3:
		return
	for state in run_states:
		if typeof(state) != TYPE_BOOL:
			return
	_main.lan_clean_up_from_host(run_states)
