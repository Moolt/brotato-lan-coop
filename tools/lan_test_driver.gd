extends Node

# Test-only driver (not part of the mod, not in the release zip). tools/make_test_copy.sh links it
# into a throwaway game copy as the LanTestDriver autoload. Role = argument after "--":
#   host: hosts, picks and readies, adds $FAKES (default 1) fake lobby players (the first is an
#         Engineer, for turrets), starts a 20 s wave with invulnerable players and $ENEMY_MULT
#         times the enemies, moves left, spawns a boss and three trees, sets the boss to
#         5000 HP and then half, kills a tree and the fake player 2, opens its pause menu, lets
#         the wave end cleared (with KILL_ALL=1: kills everyone, run lost), logs players/HP/
#         speed/timer, entities and the run verdict, back in the lobby logs the wave-end state
#         and the clients' acks, leaves
#   join: joins the first discovered game, picks and readies, enters the wave with the host,
#         moves right, opens its pause menu and checks it stands still, then (with
#         CLIENT_QUITS=1) quits the wave, (with CLIENT_QUITS=2) closes the game, (with
#         CLIENT_QUITS=3) loses the connection unnoticed by the host and rejoins, (with
#         CLIENT_QUITS=4) loses it with the host noticing and rejoins, or stays and
#         logs the host's run verdict, follows the host back to the lobby and logs the
#         wave-end state it received
#   (host and join) WAVES=n: n waves with upgrades and shop in between, then both check the
#         next wave (digest, every player's gear) before the end steps
#   (host and join) FAIL_ACK=1: the next wave's run counts as different from the host's, once
#   (join) TIMER_LAG=s: the client's wave timer s seconds behind the host's near the wave's end
#   (host and join) AIM_TEST=1: manual aim on; the client points its mouse at the top left of
#         its window; log_sync logs every player's first weapon rotation (compare the client's
#         own with the host's copy) and the reported aim
#   (host and join) ROUNDS=n: back in the lobby, the host starts the next run in the same
#         session and both play it again, n runs in all
#   solo: builds a 1-player run without a session and plays a vanilla wave
#   lobby: hosts, picks and readies, then screenshots the lobby page while a character and a
#         weapon are hovered and with nothing hovered, opens the settings page, sets the choice
#         time to 60, closes it with ui_cancel, and quits (lobby layout)
#   (join) in the lobby: logs the settings summary and that there is no Settings button
#   title: screenshots the main menu after 2 s and logs its layout (containers, each left button),
#         then again with Continue toggled (title_no_continue), and quits
#   quit: quits once the title screen is up (cheap check for parse errors)
#   (none): idle, for manual tests
#   (host and join) END_STAY=1: stay on the end screen (no Exit, no quit), e.g. to look at it
#   (any role) PERF_LOG=1: once a second in a wave, enemies, physics bodies/pairs, physics and
#         process time, FPS; ENEMY_CAP=n: the wave's enemy cap (solo: exactly n);
#         PHYS_ITER=n: Physics2DServer collision iterations; NO_ENEMY_COLLIDE=1: enemies don't
#         collide with each other; TIMING=1: times enemy scripts and weapon target scans;
#         NO_SYNC=1 (host alone): LanWaveSync's per-tick work off
#   (host and join) PUSH_TEST=1: at t=20-26 the client walks at the host player, the host stands
#         still; both log the host's and the client's position twice a second
#   (join) CLIENT_WALK=1: in a wave the client's player keeps walking (a new direction every second)
#   (any role) JITTER_LOG=1: every 2 s in a wave, how smoothly enemies move on screen (frame
#         times, physics ticks per frame, stalls, speed changes), clock offset jumps and buffer
#         starvation (clients)
#   (any role, also none) HIT_LOG=1: logs enemy bullets and enemies entering player hurtboxes and
#         every player HP change (bullet bug)
#   (any role, also none) TEST_VOLUME=x: master volume at x (default 0.2) of the saved one
#   (host) STALE_DIE_ARGS=1: at t=16 Utils.default_die_args.from is a freed node, as vanilla
#         leaves it (with CLIENT_QUITS=2: the host kills the left client's player)
#   (host) HOST_QUITS=1: closes the game mid-wave (t=18); the client ends the session, no rejoin
#   (host) MORTAL=1: players can be hit; at t=16 an enemy is placed on the host player
#   (host) at t=16 an enemy burns with spread 2 next to two others (burn_spread_test); log_sync
#         logs the session's physics quirk fixes and enemy contacts on player hurtboxes
#   (solo) START_WAVE, ENEMY_MULT as for host; a 20 s wave
#   (host) WAVE_DURATION=s: the first wave lasts s seconds (default 20)
#   (host) CHOICE_TIME=s: the choice time between waves (lobby_settings.choice_time)
#   (host) SCALING_PRESET=n: the enemy scaling preset (0 relaxed, 1 normal, 2 tough); remembered
#         in the test config like a lobby pick
#   (host and join) IDLE_CHOICE=1: no Go in the shop (the choice time runs out; the host presses
#         Go at 13 s left, so its waiting overlay counts down); =2: no upgrade
#         picks either; =3: as 2, and the client's choice time never ends (the host goes on
#         without it). choice_watch logs and screenshots the countdown at 13, 8 and 3 s left
#   (join) JOIN_ADDR=ip:port: joins that address instead of the first discovered game (e.g. through
#         a delay/jitter proxy); PLAYER_NAME=s: the client's name; PICK=n: its nth character
#   (host) HOST_NAME=s: the host's name; FAKE_NAMES=a,b,...: the fake players' names (screenshots)
#   (host) EXPECT=n: waits (up to t=120) for n players, all ready, before Start; later steps keep
#         their timing relative to the Start
#   (host and join) WAVES=n counts from the run's first wave, so it combines with START_WAVE
#   (any role) TARGET_FPS=n: Engine.target_fps (many instances on one PC)
#   (join) CLIENT_WALK=2: stop and go (0.6 s walking, 0.6 s standing, the next direction each time)
#   (host) OVERSHOOT_LOG=1: per remote player stop, how far the host showed the player past the
#         position the client stopped at (along the last direction), logged every 5 s
#   (join) LOAD_STALL=s: the main thread blocks s seconds while the first wave loads (slow disk)
#   (host and join) RELOAD_RACE=1: when the wave-end state arrives (the solo view starts right
#         after), every player's stats and weapons are queued for a reload in main's StatsManager,
#         as a stat change in the wave's last frames leaves them
#   (host) ITEMS=id,id: at t=16 those items for players 0 and 1; 5 s into the next wave both
#         sides log pets, structures and entities without a net id (as PET_TEST)
#   (host) PET_TEST=1: at t=16 a pet item for player 0 and 1; 5 s into the next wave both sides
#         log every pet (owner, position, net id)
#   (host) HOST_DIES=1: the host also dies at t=18 (with the fake; in Team Race their team is out).
#   (host) MODE=id: the run's game mode (lobby_settings.mode, modes/mode_registry.gd), not
#         remembered; log_sync and log_wave_end log the mode's id and state on both sides
#   (host) ZONE=n: the run's zone (lobby_settings.zone, 1 = the DLC's Abyss), not remembered
#   (host and join) CHAR=id: pick that character (e.g. character_diver) instead of the nth
#   (host and join) CURSE_TEST=1 (DLC): every item in the first shop is cursed before the buy and
#         the lock; log_run_check logs each player's cursed gear and a hash of its effects
#   (host and join) CURSE_ENEMIES=1 (DLC): vanilla's debug flag that curses every spawned enemy, on
#         both sides (only the host's curse may count); log_sync logs the cursed enemies'
#         net ids, the boosted and charmed counts and the scene effect behaviours on both sides
#   (host) BOSS=path: the boss spawned at t=13 (default the rhino), e.g. a DLC elite with pivots
#         (res://entities/units/enemies/abyss/elites/giant/giant.tscn) or the eel
#         (…/abyss/bosses/eel/eel.tscn; phase 2 at half HP, t=18)
#   (host and join) FULL_SLOTS=1: at t=16 the host fills players 0 and 1's weapon slots with
#         knives; in the shop each buys a knife first (vanilla merges it into one of theirs) and
#         presses Go in the same frame (=2: a second later)
#   (any role) DLC_LOG=s: every s seconds in a wave, log_sync's dlc line (long waves)
#   (host) DLC_ITEMS=k (DLC): at t=16 the DLC's items and weapons with index % 7 == k for players 0
#         and 1 (k = 0..6 covers all); DLC_SET=id picks the DLC (default abyssal_terrors,
#         or primal_dread)
#   (host) BOSS_HP2=n: the bosses' HP at t=18 of 5000 (default 2500; the eel's phase 2 is below 2000)
#   (host) SPAWN=path: four more enemies of that scene at t=13 (e.g. the DLC's pufferfish)
#   (host) SPAWN_NEAR=1: the SPAWN enemies 250 px around the host player (they notice it)
#   (host) CHARM_BOOST=1: at t=13 players 0 and 1 get 200 max HP, so a Romantic charms on every
#         hit that leaves an enemy below 25 % HP (vanilla's own charm path, both players' hits)
#   (host) CHARM_TEST=1: at t=15 the host charms every spitter (needs a charm effect, e.g.
#         CHAR=character_romantic); log_sync's dlc line logs charmed projectiles on both sides
#   (host) GPE_TEST=1 (Primal Dread, e.g. ZONE=2 START_WAVE=4 for the holes): at t=15 an acid, a
#         petrol and a fire puddle, a single hole, a mutant and a meca spitter, and the enemy time
#         at half speed for 4 s; log_sync's gpe line (both sides): hole layout, puddles by kind and
#         how many have areas on (clients: 0), evolved enemies by net id, time factor, overlay,
#         wave seed; on clients also that a local puddle is refused
# log_sync's dlc line (both sides): every boss's pivots (direction, angle), charmed (hue-shifted)
#   enemy projectiles, enemy projectiles the machine shot itself (clients: must stay 0), Pursuer
#   sizes by net id, full lungs
# log_sync's steps line (both sides): every player's steps this wave and max HP (the DLC's hiker
#   gains gold and max HP for steps; the host must count remote players' steps)
# log_lobby logs the active DLCs and how many zones, characters, items and weapons are loaded.
# log_perf (with log_sync): FPS, frame times, physics load, the mod's per-frame cost and, on
# clients, snapshot arrivals, losses and interpolation cushion.
# The step scripts follow the latest feature under test; edit them for the next one.
# Lines start with [TEST]; screenshots go to $SHOT_DIR.
var role: = ""
var t: = 0.0
var step: = 0
var next_t: = 0.0
var start_pos = null
var started: = false
var run_states_logged: = false
# ROUNDS=n: after the run ends in the lobby, the host starts the next run in the same session.
var round_nr: = 1
# Wave perf since the last log_perf: frame times, and on clients snapshot arrivals and losses.
var perf: = {}
var perf_log_t: = 0.0
var perf_scene = null
# JITTER_LOG=1: per-frame motion smoothness of enemies, summed over 2 s windows.
var jitter: = {}
var physics_ticks: = 0
# Enemy hitboxes that entered a player's hurtbox this wave (contact hits, also when invulnerable).
var enemy_contacts: = 0
# Enemy bullets (layer 16) that entered a player's hurtbox this wave.
var enemy_bullet_hits: = 0
# HIT_LOG=1: the wave scene whose players are watched.
var hit_log_scene = null
# The run's first wave (WAVES=n counts from it, also with START_WAVE).
var first_wave: = 0
var waited_for_wave: = false


func _ready() -> void :
	pause_mode = PAUSE_MODE_PROCESS
	if OS.get_environment("LOAD_STALL") != "":
		var _e = get_tree().connect("node_added", self, "_on_node_added")
	for a in OS.get_cmdline_args():
		if a in ["host", "join", "quit", "solo", "lobby", "title"]:
			role = a
	print("[TEST] role=", role)
	# Quieter test sessions: the master bus at $TEST_VOLUME (default 0.2) of the saved volume.
	var master = AudioServer.get_bus_index("Master")
	var volume = float(OS.get_environment("TEST_VOLUME")) if OS.get_environment("TEST_VOLUME") != "" else 0.2
	AudioServer.set_bus_volume_db(master, AudioServer.get_bus_volume_db(master) + linear2db(max(volume, 0.0001)))


func shot(tag: String) -> void :
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(OS.get_environment("SHOT_DIR") + "/shot_%s_%s.png" % [role, tag])


func scene_name() -> String:
	var s = get_tree().current_scene
	return s.filename if s != null else "<none>"


func menus():
	var s = get_tree().current_scene
	if s == null or s.filename != MenuData.title_screen_scene:
		return null
	return s.find_node("Menus", true, false)


# Test-only: the connection breaks as if the cable was pulled (no goodbye). tell_host = false
# keeps the old ENet peer alive but unpolled, so the host only notices when the client rejoins
# (or at ENet's timeout); true closes it, so the host sees the disconnect first.
var dropped_peer = null


func drop_connection(tell_host: bool) -> void :
	var net = get_node("/root/LanNet")
	dropped_peer = get_tree().network_peer
	if tell_host:
		dropped_peer.close_connection()
	else:
		net._peer = null
	get_tree().network_peer = null
	print("[TEST] ", role, " dropped the connection at t=", stepify(t, 0.1), " tell_host=", tell_host, " scene=", scene_name())
	net._on_server_disconnected()


func log_lobby(tag: String) -> void :
	shot(tag)
	var net = get_node("/root/LanNet")
	var m = menus()
	if m == null:
		print("[TEST] ", tag, " scene=", scene_name(), " run_in_progress=", net.run_in_progress, " settings=", net.lobby_settings)
		return
	var lobby = m.get_node("LanLobby")
	print("[TEST] ", tag, " page=", m._current_page.name, " joined=", net.joined, " index=", net.local_player_index, " reconnecting=", net.is_reconnecting(), " run_in_progress=", net.run_in_progress, " settings=", net.lobby_settings, " players=", net.players.size(), " coop_players=", CoopService.connected_players)
	print("[TEST] ", tag, " hint='", tr(lobby._hint_label.text), "' start_disabled=", lobby._start_button.disabled)
	print("[TEST] ", tag, " dlcs=", ProgressData.available_dlc_ids, " sets=", ProgressData.active_update_data, " zones=", ZoneService.zones.size(), " characters=", ItemService.characters.size(), " items=", ItemService.items.size(), " weapons=", ItemService.weapons.size())


func log_wave(tag: String) -> void :
	shot(tag)
	var main = get_tree().current_scene
	var positions = []
	for p in main._players:
		positions.append(p.global_position)
	print("[TEST] ", tag, " scene=", scene_name(), " coop_players=", CoopService.connected_players, " players=", positions, " devices=", main._players[0]._movement_behavior.device, ",", main._players[1]._movement_behavior.device, " wave=", RunData.current_wave, " time_left=", main._wave_timer.time_left)


func first_element(grid, nth: = 0):
	for e in grid.get_children():
		if not e.is_random and not e.is_special and e.item != null:
			if nth == 0:
				return e
			nth -= 1
	return null


# Client in the lobby: the settings summary and the read-only settings page (dropdowns open,
# every choice disabled; picking one changes nothing).
func client_settings_check(lobby) -> void :
	print("[TEST] client_settings button=", lobby._settings_button.visible, " hint='", lobby._hint_label.text, "' hint_visible=", lobby._hint_label.visible, " summary='", lobby._settings_label.text, "'")
	shot("client_lobby")
	lobby._settings_button.emit_signal("pressed")
	var page = lobby._settings_page
	var zone = page._zone_option
	var items_disabled = true
	for i in zone.get_item_count():
		items_disabled = items_disabled and zone.is_item_disabled(i)
	var net = get_node("/root/LanNet")
	var before = net.lobby_settings.zone
	page._on_option_item_selected((zone.selected + 1) % zone.get_item_count(), zone, "zone")
	yield(get_tree().create_timer(0.5), "timeout")
	print("[TEST] client_settings_page visible=", page.visible, " note='", page._read_only_label.text, "' note_visible=", page._read_only_label.visible, " zone_disabled=", zone.disabled, " items_disabled=", items_disabled, " focus=", get_viewport().gui_get_focus_owner() == page._mode_option, " zone_before=", before, " zone_after=", net.lobby_settings.zone)
	shot("client_settings_page")
	page.close()


func pick_and_ready(lobby, nth: = 0) -> void :
	var net0 = get_node("/root/LanNet")
	# TRY_CHAR=id: asks the host for that character directly (an item set that is off: refused).
	# Takes a second: the host needs EXPECT=2 to wait for it.
	if OS.get_environment("TRY_CHAR") != "":
		net0.set_local_player_info({"character_id": OS.get_environment("TRY_CHAR")})
		yield(get_tree().create_timer(1.0), "timeout")
		print("[TEST] try_char ", OS.get_environment("TRY_CHAR"), " got='", net0.get_local_player().character_id, "'")
	var character = first_element(lobby._character_grid, nth)
	if OS.get_environment("CHAR") != "":
		for e in lobby._character_grid.get_children():
			if e.item != null and e.item.my_id == OS.get_environment("CHAR"):
				character = e
	lobby._on_CharacterGrid_element_pressed(character)
	# The weapon grid follows the host's lobby state, which takes a round trip (slow links).
	var net = get_node("/root/LanNet")
	for _i in 25:
		yield(get_tree().create_timer(0.2), "timeout")
		if net.get_local_player() != null and net.get_local_player().character_id == character.item.my_id:
			break
	yield(get_tree().create_timer(0.2), "timeout")
	# Characters with a fixed weapon have no weapon to pick.
	# Characters with several picks (Survivor, CHAR=character_survivor) take the first ones in a row.
	var LobbyRules = load("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
	var pick_count = LobbyRules.get_pick_count(LobbyRules.get_character(net.get_local_player().character_id))
	for pick in pick_count:
		var weapon = first_element(lobby._weapon_grid, pick)
		if weapon == null:
			break
		lobby._on_WeaponGrid_element_pressed(weapon)
		for _i in 25:
			yield(get_tree().create_timer(0.2), "timeout")
			if net.get_local_player().weapon_ids.size() > pick:
				break
	print("[TEST] picked ", net.get_local_player().character_id, " ", net.get_local_player().weapon_ids)
	# The host's item sets (a client has them from its welcome) and the characters they leave out
	# of the grid; weapons of the picked character the grid leaves out.
	var shown = []
	for e in lobby._character_grid.get_children():
		if not e.is_random and e.item != null:
			shown.append(e.item.my_id)
	var hidden = []
	for c in ItemService.characters:
		if not shown.has(c.my_id):
			hidden.append(c.my_id)
	var hidden_weapons = []
	var shown_weapons = []
	for e in lobby._weapon_grid.get_children():
		if not e.is_random and e.item != null:
			shown_weapons.append(e.item.my_id)
	for w in LobbyRules.get_all_starting_choices(LobbyRules.get_character(net.get_local_player().character_id)):
		if not shown_weapons.has(w.my_id):
			hidden_weapons.append(w.my_id)
	print("[TEST] lobby_item_sets ", ProgressData.active_update_data, " hidden_characters=", hidden, " hidden_weapons=", hidden_weapons, " weapon_label='", lobby._weapon_label.text, "'")
	lobby._on_ReadyButton_pressed()


func _process(delta: float) -> void :
	# TARGET_FPS=n: frame cap, e.g. for many instances on one PC (real players' PCs render on their
	# own). Every frame: the game applies its own FPS setting after startup.
	if OS.get_environment("TARGET_FPS") != "" and Engine.target_fps != int(OS.get_environment("TARGET_FPS")):
		Engine.target_fps = int(OS.get_environment("TARGET_FPS"))
	if OS.get_environment("CURSE_ENEMIES") == "1":
		DebugService.curse_enemy_spawn = true
	dlc_log_watch(delta)
	hit_log_watch()
	target_log(delta)
	storm_edge()
	hurt_host()
	toggle_test()
	if role == "":
		return
	if not started:
		started = menus() != null
		if started and get_node_or_null("/root/LanNet") != null:
			var _e = get_node("/root/LanNet").connect("wave_end_ready", self, "solo_view_test")
			_e = get_node("/root/LanNet").connect("wave_end_ready", self, "log_progress", [role + "_wave_end"])
			_e = get_node("/root/LanNet").connect("session_ended", self, "progress_after_session")
			_e = get_node("/root/LanNet").connect("run_sync_changed", self, "fail_ack_test")
			_e = get_node("/root/LanNet").connect("wave_end_ready", self, "reload_race")
		return
	t += delta
	# The wave's verdict, once, as soon as its cleanup starts (the scene changes soon after).
	var scene = get_tree().current_scene
	if not run_states_logged and scene != null and scene.filename == MenuData.game_scene and scene._cleaning_up:
		run_states_logged = true
		log_perf(role + "_cleanup")
		log_run_states(role + "_cleanup")
	perf_sample(delta)
	perf_curve(delta)
	jitter_sample(delta)
	client_walk()
	pet_watch()
	push_test()
	choice_watch()
	pick_upgrades(delta)
	shop_actions(delta)
	end_screen_actions(delta)
	if t < next_t:
		return
	if role == "quit" or get_node_or_null("/root/LanNet") == null:
		get_tree().quit()
		return
	if role == "title":
		_title_step()
		return
	if role == "solo":
		_solo_step()
	elif role == "lobby":
		_lobby_step()
	elif role == "host":
		_host_step()
	else:
		_client_step()
	step += 1


func perf_curve(delta: float) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main._cleaning_up:
		return
	if perf_scene != main:
		perf_scene = main
		perf_log_t = 0.0
		enemy_contacts = 0
		enemy_bullet_hits = 0
		for player in main._players:
			var _e = player._hurtbox.connect("area_entered", self, "_on_player_hurtbox_area_entered")
		if OS.get_environment("ENEMY_CAP") != "":
			main._entity_spawner._current_wave_data.max_enemies = int(OS.get_environment("ENEMY_CAP"))
		if OS.get_environment("PHYS_ITER") != "":
			Physics2DServer.set_collision_iterations(int(OS.get_environment("PHYS_ITER")))
		# Perf comparison only: the host's LanWaveSync stops its per-tick work (nothing is sent).
		if OS.get_environment("NO_SYNC") == "1" and main.get_node_or_null("LanWaveSync") != null:
			main.get_node("LanWaveSync").set_physics_process(false)
	if OS.get_environment("PERF_LOG") != "1":
		return
	perf_log_t += delta
	if perf_log_t < 1.0:
		return
	perf_log_t = 0.0
	var enemies = main._entity_spawner.enemies
	if OS.get_environment("NO_ENEMY_COLLIDE") == "1":
		for enemy in enemies:
			enemy.set_collision_mask_bit(2, false)
	var timing = ""
	if OS.get_environment("TIMING") == "1":
		# One extra call of each per-tick script, timed: enemy movement/attack scripts, then every
		# weapon's nearest-target scan.
		var start = OS.get_ticks_usec()
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.dead:
				enemy._physics_process(1.0 / 60.0)
		var enemies_us = OS.get_ticks_usec() - start
		var weapons = 0
		var in_range = 0
		start = OS.get_ticks_usec()
		for player in main._players:
			for weapon in player.current_weapons:
				weapons += 1
				in_range += weapon._targets_in_range.size()
				var _d = weapon.get_direction_and_calculate_target()
		timing = " enemy_scripts_us=%d weapons=%d targets_in_range=%d weapon_scan_us=%d" % [enemies_us, weapons, in_range, OS.get_ticks_usec() - start]
	var sync = main.get_node_or_null("LanWaveSync")
	print("[TEST] ", role, "_curve wave_t=", stepify(main._wave_timer.wait_time - main._wave_timer.time_left, 1), " enemies=", main._entity_spawner.enemies.size(), " bodies=", Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), " pairs=", Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS), " physics_ms=", stepify(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1), " process_ms=", stepify(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1), " fps=", Engine.get_frames_per_second(), " removed_for_perf=", main._entity_spawner.enemies_removed_for_perf, timing)


# HIT_LOG=1 (any role, also idle for manual tests): logs every enemy bullet or enemy entering a
# player's hurtbox and every player HP change, with the wave time.
func hit_log_watch() -> void :
	if OS.get_environment("HIT_LOG") != "1":
		return
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main == hit_log_scene:
		return
	hit_log_scene = main
	for player in main._players:
		var _e = player._hurtbox.connect("area_entered", self, "_on_hit_log_area", [player])
		_e = player.connect("health_updated", self, "_on_hit_log_health")
	print("[TEST] hit_log watching ", main._players.size(), " players, local=", main.get_node("LanWaveSync")._local_index if main.get_node_or_null("LanWaveSync") != null else 0)


func _on_hit_log_area(area: Area2D, player) -> void :
	var kind = "enemy" if area.get_parent() is Enemy else ("bullet" if area.collision_layer & Utils.ENEMY_PROJECTILES_BIT else "")
	if kind == "":
		return
	var main = get_tree().current_scene
	print("[TEST] hit_log t=", stepify(main._wave_timer.wait_time - main._wave_timer.time_left, 0.01), " ", kind, " entered hurtbox of player ", player.player_index, " from ", area.get_parent().filename.get_file(), " hurtbox_on=", not player._hurtbox.is_disabled(), " hp=", player.current_stats.health)


func _on_hit_log_health(unit, current_health, max_health) -> void :
	var main = get_tree().current_scene
	print("[TEST] hit_log t=", stepify(main._wave_timer.wait_time - main._wave_timer.time_left, 0.01), " player ", unit.player_index, " hp ", current_health, "/", max_health)


func _on_player_hurtbox_area_entered(area: Area2D) -> void :
	if area.get_parent() is Enemy:
		enemy_contacts += 1
	elif area.collision_layer & Utils.ENEMY_PROJECTILES_BIT:
		enemy_bullet_hits += 1


# The session's physics quirk fixes (extensions/overlap, burning_particles, wave_sync _make_inert).
func log_quirk_fixes(tag: String, main, wave_sync) -> void :
	var LanGame = load("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
	var hitboxes_moved = 0
	var spread_on = 0
	var burning = 0
	var masks = {}
	for enemy in main._entity_spawner.enemies:
		if enemy._hitbox.collision_layer & LanGame.ENEMY_HITBOX_BIT and not enemy._hitbox.collision_layer & Utils.ENEMIES_BIT:
			hitboxes_moved += 1
		if not enemy._burning_particles._collision.disabled:
			spread_on += 1
		if enemy._is_burning:
			burning += 1
		masks[enemy.collision_mask] = masks.get(enemy.collision_mask, 0) + 1
	var hurtbox_masks = []
	for player in main._players:
		hurtbox_masks.append(player._hurtbox.collision_mask)
	print("[TEST] ", tag, " quirks enemies=", main._entity_spawner.enemies.size(), " hitboxes_moved=", hitboxes_moved, " spread_on=", spread_on, " burning=", burning, " enemy_masks=", masks, " hurtbox_masks=", hurtbox_masks, " enemy_contacts=", enemy_contacts, " cap_factor=", LanGame.get_enemy_cap_factor(main._players.size()) if wave_sync != null else "-")


# Host: one enemy burns with spread 2 and two others stand next to it (all with 10000 HP, so they
# live); vanilla spreads the burn to both (Unit.apply_burning enables the SpreadArea).
func burn_spread_test(main) -> void :
	var enemies = []
	for enemy in main._entity_spawner.enemies:
		if is_instance_valid(enemy) and not enemy.dead and not enemy._is_burning:
			enemies.append(enemy)
	if enemies.size() < 3:
		print("[TEST] burn_spread skipped enemies=", enemies.size())
		return
	enemies = enemies.slice(0, 2)
	for i in 3:
		enemies[i].max_stats.health = 10000
		enemies[i].current_stats.health = 10000
		if i > 0:
			enemies[i].global_position = enemies[0].global_position + Vector2(40 * i, 0)
	var burning_data = BurningData.new()
	burning_data.chance = 1.0
	burning_data.damage = 1
	burning_data.duration = 5
	burning_data.spread = 2
	enemies[0].apply_burning(burning_data)
	for wait in [0.5, 1.0]:
		yield(get_tree().create_timer(wait), "timeout")
		var states = []
		for enemy in enemies:
			states.append(is_instance_valid(enemy) and enemy._is_burning)
		var particles = enemies[0]._burning_particles if is_instance_valid(enemies[0]) else null
		print("[TEST] burn_spread burning=", states, " shape_disabled=", particles._collision.disabled if particles != null else "-", " bodies=", particles.bodies.size() if particles != null else "-", " spread=", particles.burning_data.spread if particles != null and particles.burning_data != null else "-", " physics=", particles.is_physics_processing() if particles != null else "-", " dist=", [enemies[0].global_position.distance_to(enemies[1].global_position), enemies[0].global_position.distance_to(enemies[2].global_position)])


# Host with MORTAL=1: an enemy on the host player; its contact hits count in enemy_contacts.
func contact_test(main) -> void :
	if OS.get_environment("MORTAL") != "1":
		return
	for enemy in main._entity_spawner.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.global_position = main._players[0].global_position
			print("[TEST] contact_test enemy placed hp_before=", main._players[0].current_stats.health)
			return


func _physics_process(_delta: float) -> void :
	physics_ticks += 1
	jitter_tick()
	overshoot_tick()


# OVERSHOOT_LOG=1 (host): per remote player, the shown positions of the last 400 ms and the
# current stop; a stop is the first state whose input is zero after moving. Overshoot: the largest
# distance past the reported stop position along the last direction, from 400 ms before that
# state arrived until 500 ms after (or the next move).
var overshoot: = {}
var overshoot_results: = {}
var overshoot_log_msec: = 0


func overshoot_tick() -> void :
	if OS.get_environment("OVERSHOOT_LOG") != "1" or role != "host":
		return
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main._cleaning_up or main.get_node_or_null("LanWaveSync") == null:
		overshoot = {}
		return
	var sync = main.get_node("LanWaveSync")
	var now = OS.get_ticks_msec()
	for i in sync._remote_states:
		var state = sync._remote_states[i]
		var player = main._players[i]
		if not is_instance_valid(player) or player.dead:
			continue
		if not overshoot.has(i):
			overshoot[i] = {"hist": [], "dir": Vector2.ZERO, "moving": false, "stop": null}
		var o = overshoot[i]
		o.hist.append([now, player.global_position])
		while not o.hist.empty() and now - o.hist[0][0] > 400:
			o.hist.pop_front()
		if state.move != Vector2.ZERO:
			if o.stop != null:
				overshoot_results[i] = overshoot_results.get(i, []) + [o.stop.max]
				o.stop = null
			o.dir = state.move.normalized()
			o.moving = true
		elif o.moving:
			o.moving = false
			var stop = {"at": now, "pos": state.pos, "dir": o.dir, "max": - 1000.0}
			for entry in o.hist:
				stop.max = max(stop.max, (entry[1] - state.pos).dot(o.dir))
			o.stop = stop
		elif o.stop != null:
			o.stop.max = max(o.stop.max, (player.global_position - o.stop.pos).dot(o.stop.dir))
			if now - o.stop.at > 500:
				overshoot_results[i] = overshoot_results.get(i, []) + [o.stop.max]
				o.stop = null
	if now - overshoot_log_msec >= 5000:
		overshoot_log_msec = now
		for i in overshoot_results:
			var sorted = overshoot_results[i].duplicate()
			sorted.sort()
			print("[TEST] overshoot player=", i, " ", get_node("/root/LanNet").get_player(i).name, " stops=", sorted.size(), " px median=", stepify(sorted[sorted.size() / 2], 0.1), " p90=", stepify(sorted[int(sorted.size() * 0.9)], 0.1), " max=", stepify(sorted[- 1], 0.1), " over_5px=", sorted.size() - sorted.bsearch(5.0), " time_left=", stepify(main._wave_timer.time_left, 0.1))
		overshoot_results = {}


# LOAD_STALL=s (join): blocks the main thread once, when the first wave's LanWaveSync enters the
# tree (before it tells the host it loaded), as a slow load would.
var load_stalled: = false


func _on_node_added(node: Node) -> void :
	if load_stalled or role != "join" or node.name != "LanWaveSync":
		return
	load_stalled = true
	var seconds = float(OS.get_environment("LOAD_STALL"))
	print("[TEST] load stall ", seconds, " s at t=", stepify(t, 0.1))
	OS.delay_msec(int(seconds * 1000))
	print("[TEST] load stall over at t=", stepify(t, 0.1))


func reload_race() -> void :
	var main = get_tree().current_scene
	if OS.get_environment("RELOAD_RACE") != "1" or main == null or main.filename != MenuData.game_scene:
		return
	var weapons = 0
	for player in main._players:
		main._stats_manager.reload_stats(player)
		weapons += player.current_weapons.size()
	print("[TEST] ", role, " reload_race queued ", main._players.size(), " players, ", weapons, " weapons, solo_view=", get_node("/root/LanNet").solo_view.active)


# PET_TEST=1: 5 s into the second wave, every pet on this machine (owner, scene, position, net id).
var pets_logged: = false


func pet_watch() -> void :
	if (OS.get_environment("PET_TEST") != "1" and OS.get_environment("ITEMS") == "") or pets_logged or first_wave == 0:
		return
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main._cleaning_up or RunData.current_wave != first_wave + 1:
		return
	if main._wave_timer.wait_time - main._wave_timer.time_left < 5.0 or main.get_node_or_null("LanWaveSync") == null:
		return
	pets_logged = true
	var sync = main.get_node("LanWaveSync")
	var out = []
	for pet in main._entity_spawner.pets:
		if is_instance_valid(pet):
			out.append("p%d:%s:%s:id=%s" % [pet.player_index, pet.filename.get_file().get_basename(), pet.global_position.round(), pet.get_meta("lan_net_id") if pet.has_meta("lan_net_id") else "-"])
	print("[TEST] ", role, "_pets wave=", RunData.current_wave, " time_left=", stepify(main._wave_timer.time_left, 0.01), " count=", out.size(), " ", out, " net_entities=", sync._entities.size())
	var structures = []
	for structure in main._entity_spawner.structures:
		if is_instance_valid(structure):
			structures.append("p%d:%s:%s:id=%s" % [structure.player_index, structure.filename.get_file().get_basename(), structure.global_position.round(), structure.get_meta("lan_net_id") if structure.has_meta("lan_net_id") else "-"])
	# Entity nodes that aren't synced (spawned outside the entity spawner).
	var unsynced = {}
	for child in main._entities_container.get_children():
		if child is Entity and not child.dead and not child.has_meta("lan_net_id") and not child is Player:
			unsynced[child.filename.get_file()] = unsynced.get(child.filename.get_file(), 0) + 1
	print("[TEST] ", role, "_structures count=", structures.size(), " ", structures, " unsynced_entities=", unsynced)
	shot(role + "_pets")


# Per physics tick (JITTER_LOG): how far up to 20 enemies moved since the last tick. Vanilla
# moves them a steady amount per tick; a stall (0 while walking) or a jump shows as a change.
# PUSH_TEST=1: at t=20-26 the client walks straight at the host player (as it sees it); the host
# stands still and logs where it is twice a second (pushed = it moved).
var push_log_t: = 0.0


func push_test() -> void :
	if OS.get_environment("PUSH_TEST") != "1":
		return
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main._cleaning_up or main.get_node_or_null("LanWaveSync") == null:
		return
	var sync = main.get_node("LanWaveSync")
	var me = main._players[sync._local_index]
	var host = main._players[0]
	var directions = {"button_move_right_0": Vector2.RIGHT, "button_move_left_0": Vector2.LEFT, "button_move_down_0": Vector2.DOWN, "button_move_up_0": Vector2.UP}
	if role == "join":
		var to_host = host.global_position - me.global_position
		for action in directions:
			if t >= 20.0 and t < 26.0 and to_host.length() > 1.0 and directions[action].dot(to_host.normalized()) > 0.38:
				Input.action_press(action)
			elif t >= 19.9 and t < 26.5:
				Input.action_release(action)
	if t >= 19.5 and t < 27.0 and t >= push_log_t:
		push_log_t = t + 0.5
		print("[TEST] push t=", stepify(t, 0.1), " host_pos=", host.global_position.round(), " client_pos=", main._players[1].global_position.round(), " distance=", stepify(host.global_position.distance_to(main._players[1].global_position), 1))


# CLIENT_WALK=1 (join): in a wave the client's player walks, a new direction every second.
func client_walk() -> void :
	if not OS.get_environment("CLIENT_WALK") in ["1", "2"] or role != "join":
		return
	var main = get_tree().current_scene
	var directions = ["button_move_right_0", "button_move_down_0", "button_move_left_0", "button_move_up_0"]
	var in_wave = main != null and main.filename == MenuData.game_scene and not main._cleaning_up
	var current = int(OS.get_ticks_msec() / 1000) % 4 if in_wave else - 1
	if in_wave and OS.get_environment("CLIENT_WALK") == "2":
		# Stop and go: 600 ms walking, 600 ms standing.
		var period = int(OS.get_ticks_msec() / 600)
		current = int(period / 2) % 4 if period % 2 == 0 else - 1
	for i in 4:
		if i == current:
			Input.action_press(directions[i])
		else:
			Input.action_release(directions[i])


func jitter_tick() -> void :
	if jitter.empty() or not jitter.has("tick_pos"):
		return
	var main = get_tree().current_scene
	var tracked = 0
	var new_pos = {}
	for enemy in main._entity_spawner.enemies:
		if tracked >= 20:
			break
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var id = enemy.get_instance_id()
		new_pos[id] = enemy.global_position
		tracked += 1
		if not jitter.tick_pos.has(id):
			continue
		var step = enemy.global_position.distance_to(jitter.tick_pos[id])
		var last_step = jitter.last_step.get(id, - 1.0)
		if last_step > 0.5:
			jitter.moving += 1
			if step < 0.05:
				jitter.stalls += 1
			jitter.speed_changes.append(abs(step - last_step) / last_step)
		jitter.last_step[id] = step
	jitter.tick_pos = new_pos
	var sync = main.get_node_or_null("LanWaveSync")
	if sync != null and sync.is_host:
		var now = OS.get_ticks_msec()
		for index in sync._remote_states:
			var state = sync._remote_states[index]
			if not jitter.remote_last.has(index):
				jitter.remote_last[index] = [state.pos, now]
				continue
			var last = jitter.remote_last[index]
			if state.pos != last[0]:
				jitter.remote_gaps.append(now - last[1])
				jitter.remote_last[index] = [state.pos, now]
				jitter.remote_ages.append(int(state.since * 1000.0))
			elif state.move != Vector2.ZERO:
				jitter.remote_stalls += 1
			# Direction unchanged for 0.3 s: steps should be steady.
			if state.move != jitter.remote_move.get(index, Vector2.ZERO):
				jitter.remote_move[index] = state.move
				jitter.remote_move_since[index] = now
			var straight = now - jitter.remote_move_since.get(index, now) > 300
			# What the host shows: the remote player's step this tick.
			var shown = main._players[index].global_position
			if jitter.remote_shown.has(index) and state.move != Vector2.ZERO:
				var step = shown.distance_to(jitter.remote_shown[index][0])
				var last_step = jitter.remote_shown[index][1]
				if step < 0.05:
					jitter.remote_shown_stalls += 1
				if last_step > 0.5:
					jitter.remote_step_changes.append(abs(step - last_step) / last_step)
					if straight:
						jitter.remote_straight_changes.append(abs(step - last_step) / last_step)
				jitter.remote_shown[index] = [shown, step]
			else:
				jitter.remote_shown[index] = [shown, - 1.0]


# TOGGLE_TEST=1 (any role, a mode with a scoreboard): in wave 1 at 6 s Tab, at 8 s the gamepad's
# Back button; logs whether the scoreboard's table is shown before and after each.
var toggle_steps: = {}


func toggle_test() -> void :
	var main = get_tree().current_scene
	if OS.get_environment("TOGGLE_TEST") != "1" or main == null or main.filename != MenuData.game_scene or main._cleaning_up or RunData.current_wave != 1:
		return
	var board = main.get_node_or_null("UI/HUD/LanScoreboard")
	if board == null:
		return
	var elapsed = main._wave_timer.wait_time - main._wave_timer.time_left
	for at in [6, 8]:
		if elapsed >= at and not toggle_steps.has(at):
			toggle_steps[at] = true
			var before = board._panel.visible
			var event
			if at == 6:
				event = InputEventKey.new()
				event.scancode = KEY_TAB
			else:
				event = InputEventJoypadButton.new()
				event.button_index = JOY_SELECT
			event.pressed = true
			Input.parse_input_event(event)
			call_deferred("toggle_log", board, at, before)


func toggle_log(board, at: int, before: bool) -> void :
	yield(get_tree(), "idle_frame")
	print("[TEST] toggle_test t=", at, " before=", before, " after=", board._panel.visible, " saved=", get_node("/root/LanNet").config.show_scoreboard)


# HURT_HOST=n (host): in wave 1 at wave time 5 s the host player takes n damage (through armor
# and invincibility), e.g. to check HP at the next wave's start (log_run_check's hp=).
var host_hurt: = false
var host_hurt_checked: = false


func hurt_host() -> void :
	var main = get_tree().current_scene
	if OS.get_environment("HURT_HOST") == "" or role != "host" or main == null or main.filename != MenuData.game_scene or main._cleaning_up:
		return
	if host_hurt and RunData.current_wave == 2 and not host_hurt_checked and not main._players.empty():
		host_hurt_checked = true
		print("[TEST] hurt_host wave 2 hp=", main._players[0].current_stats.health, "/", main._players[0].max_stats.health)
	if host_hurt or RunData.current_wave != 1:
		return
	if main._wave_timer.wait_time - main._wave_timer.time_left < 5.0 or main._players.empty():
		return
	host_hurt = true
	var args = TakeDamageArgs.new(RunData.DUMMY_PLAYER_INDEX)
	args.dodgeable = false
	args.armor_applied = false
	args.bypass_invincibility = true
	var _taken = main._players[0].take_damage(int(OS.get_environment("HURT_HOST")), args)
	print("[TEST] hurt_host hp=", main._players[0].current_stats.health, "/", main._players[0].max_stats.health)


# STORM_EDGE=1 (host, Last Potato Standing): from wave time 24 s the host player is held 60 px
# outside the storm's circle, towards the arena's centre; screenshots at 26, 30 and 34 s
# (WAVE_DURATION=40).
var storm_edge_shots: = {}


func storm_edge() -> void :
	var main = get_tree().current_scene
	if OS.get_environment("STORM_EDGE") != "1" or role != "host" or main == null or main.filename != MenuData.game_scene or main._cleaning_up:
		return
	var mode = get_node("/root/LanNet").mode
	if not mode.has_method("get_storm"):
		return
	var elapsed = main._wave_timer.wait_time - main._wave_timer.time_left
	if elapsed < 24.0 or main._players.empty() or main._players[0].dead:
		return
	var storm = mode.get_storm(main)
	var rect = ZoneService.get_current_zone_rect()
	var direction = (rect.position + rect.size / 2.0 - storm[0]).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	main._players[0].global_position = storm[0] + direction * (storm[1] + 60.0)
	for at in [26, 30, 34]:
		if elapsed >= at and not storm_edge_shots.has(at):
			storm_edge_shots[at] = true
			shot("storm_edge_%d" % at)


# TARGET_LOG=1 (any role): once a second in a wave, what every player weapon aims at (its
# current targets: script, name, distance to the player, and whether it is an Enemy).
var target_log_wait: = 0.0


func target_log(delta: float) -> void :
	var main = get_tree().current_scene
	if OS.get_environment("TARGET_LOG") != "1" or main == null or main.filename != MenuData.game_scene or main._cleaning_up:
		return
	target_log_wait += delta
	if target_log_wait < 1.0:
		return
	target_log_wait = 0.0
	for player in main._players:
		if not is_instance_valid(player):
			continue
		var parts = []
		for weapon in player.current_weapons:
			var targets = []
			for target in weapon._current_target:
				if not is_instance_valid(target):
					targets.append("freed")
					continue
				var script = target.get_script()
				targets.append("%s:%s:%d:%s" % [script.resource_path.get_file() if script != null else target.get_class(), target.name, int(target.global_position.distance_to(player.global_position)), target is Enemy])
			var odd = []
			for body in weapon._targets_in_range:
				if is_instance_valid(body) and not body is Enemy:
					odd.append("%s:%s" % [body.get_class(), body.name])
			parts.append("%s rot=%.2f shooting=%s cd=%d %s in_range=%d odd=%s" % [weapon.name, weapon.rotation, weapon._is_shooting, int(weapon._current_cooldown), targets, weapon._targets_in_range.size(), odd])
		print("[TEST] targets t=%.1f p%d dead=%s %s" % [main._wave_timer.wait_time - main._wave_timer.time_left, player.player_index, player.dead, parts])


# JITTER_LOG: frame times, physics ticks per frame, enemy motion per tick (jitter_tick), and on
# clients the snapshots' lateness, clock offset jumps and frames where the buffer ran dry; on
# the host how regularly the clients' reported positions change.
func jitter_sample(_delta: float) -> void :
	var main = get_tree().current_scene
	if OS.get_environment("JITTER_LOG") != "1" or main == null or main.filename != MenuData.game_scene or main._cleaning_up:
		jitter = {}
		physics_ticks = 0
		return
	var sync = main.get_node_or_null("LanWaveSync")
	var now = OS.get_ticks_usec()
	if jitter.empty():
		jitter = {"start": now, "last": now, "pos": {}, "frames": 0, "ticks": {}, "dt": [], "stalls": 0, "moving": 0, "speed_changes": [], "last_speed": {}, "offset": sync._clock_offset if sync != null else null, "offset_jumps": [], "starved": 0, "tick_pos": {}, "last_step": {}, "remote_last": {}, "remote_gaps": [], "remote_stalls": 0, "remote_shown": {}, "remote_shown_stalls": 0, "remote_step_changes": [], "remote_straight_changes": [], "remote_ages": [], "remote_move": {}, "remote_move_since": {}, "late": [], "last_time": sync._snapshots[- 1].time if sync != null and not sync._snapshots.empty() else - 1}
		physics_ticks = 0
		return
	var dt = (now - jitter.last) / 1000000.0
	jitter.last = now
	jitter.frames += 1
	jitter.dt.append(dt * 1000.0)
	jitter.ticks[physics_ticks] = jitter.ticks.get(physics_ticks, 0) + 1
	physics_ticks = 0
	if sync != null and not sync.is_host:
		# Lateness of each new snapshot beyond the fastest one seen (the clock offset).
		var now_ms = OS.get_ticks_msec()
		for snapshot in sync._snapshots:
			if snapshot.time > jitter.last_time and sync._clock_offset != null:
				jitter.late.append(now_ms - snapshot.time - sync._clock_offset)
		if not sync._snapshots.empty():
			jitter.last_time = max(jitter.last_time, sync._snapshots[- 1].time)
		if jitter.offset != null and sync._clock_offset != null and sync._clock_offset < jitter.offset - 2:
			jitter.offset_jumps.append(jitter.offset - sync._clock_offset)
		jitter.offset = sync._clock_offset
		if not sync._snapshots.empty() and sync._render_time != null and sync._snapshots[- 1].time < sync._render_time:
			jitter.starved += 1
		jitter.delay = sync._interp_delay
	if now - jitter.start >= 2000000:
		var changes = jitter.speed_changes
		changes.sort()
		var dts = jitter.dt
		dts.sort()
		var median = changes[changes.size() / 2] if not changes.empty() else 0.0
		var p90 = changes[int(changes.size() * 0.9)] if not changes.empty() else 0.0
		var late = jitter.late
		late.sort()
		var late_text = "-" if late.empty() else "%d/%d/%d" % [late[late.size() / 2], late[int(late.size() * 0.9)], late[- 1]]
		var gaps = jitter.remote_gaps
		gaps.sort()
		var steps = jitter.remote_step_changes
		steps.sort()
		var straight = jitter.remote_straight_changes
		straight.sort()
		var ages = jitter.remote_ages
		ages.sort()
		var extra = "" if straight.empty() or ages.empty() else ", straight step_change p50/p90=%.2f/%.2f, state age_ms p50/p90/max=%d/%d/%d" % [straight[straight.size() / 2], straight[int(straight.size() * 0.9)], ages[ages.size() / 2], ages[int(ages.size() * 0.9)], ages[- 1]]
		var remote_text = "-" if gaps.empty() else "%d updates, gap_ms p50/p90/max=%d/%d/%d, stalled_ticks=%d, shown: stalls=%d step_change p50/p90=%.2f/%.2f" % [gaps.size(), gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.9)], gaps[- 1], jitter.remote_stalls, jitter.remote_shown_stalls, steps[steps.size() / 2] if not steps.empty() else 0.0, steps[int(steps.size() * 0.9)] if not steps.empty() else 0.0] + extra
		print("[TEST] ", role, "_jitter remote_player=", remote_text, " late_ms_p50/p90/max=", late_text, " snaps=", late.size(), " frames=", jitter.frames, " fps=", stepify(jitter.frames / 2.0, 1), " dt_ms_median=", stepify(dts[dts.size() / 2], 0.1), " dt_ms_max=", stepify(dts[- 1], 0.1), " ticks_per_frame=", jitter.ticks, " tick_samples=", jitter.moving, " tick_stall_pct=", stepify(100.0 * jitter.stalls / max(1, jitter.moving), 0.1), " speed_change_median=", stepify(median, 0.01), " p90=", stepify(p90, 0.01), " offset_jumps_ms=", jitter.offset_jumps, " starved_frames=", jitter.starved, " interp_delay_ms=", stepify(jitter.get("delay", 0.0), 1))
		jitter = {}


func perf_reset() -> void :
	perf = {"frames": 0, "time": 0.0, "max_ms": 0.0, "slow": 0, "snaps": 0, "lost": 0, "max_gap": 0, "last_seq": perf.get("last_seq", - 1), "last_at": perf.get("last_at", 0), "min_cushion": 100000.0, "starved": 0, "last_time": perf.get("last_time", - 1)}


func perf_sample(delta: float) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or main.get_node_or_null("LanWaveSync") == null:
		perf = {}
		return
	if perf.empty():
		perf_reset()
	perf.frames += 1
	perf.time += delta
	perf.max_entities = max(perf.get("max_entities", 0), main.get_node("LanWaveSync")._entities.size())
	perf.max_ms = max(perf.max_ms, delta * 1000.0)
	if delta > 1.0 / 30.0:
		perf.slow += 1
	var sync = main.get_node("LanWaveSync")
	if sync.is_host or sync._last_seq < 0:
		return
	var now = OS.get_ticks_msec()
	if sync._last_seq != perf.last_seq:
		# Received = new entries in the snapshot buffer (several can arrive in one frame);
		# lost = the seq advance not covered by them.
		var received = 0
		for snapshot in sync._snapshots:
			if snapshot.time > perf.get("last_time", - 1):
				received += 1
		if not sync._snapshots.empty():
			perf.last_time = sync._snapshots[- 1].time
		var lost = max(0, sync._last_seq - perf.last_seq - received) if perf.last_seq >= 0 else 0
		# Per snapshot size in UDP packets (ENet fragments above about 1400 bytes).
		var frags = "%dpkt" % ceil((sync.SNAPSHOT_HEADER_SIZE + sync.SNAPSHOT_PLAYER_SIZE * main._players.size() + 2 + sync.SNAPSHOT_ENTITY_SIZE * sync._entities.size()) / 1400.0)
		if not perf.has("by_size"):
			perf.by_size = {}
		if not perf.by_size.has(frags):
			perf.by_size[frags] = [0, 0]
		perf.by_size[frags][0] += received
		perf.by_size[frags][1] += lost
		perf.lost += lost
		if perf.last_seq >= 0:
			perf.max_gap = max(perf.max_gap, now - perf.last_at)
		perf.snaps += received
		perf.last_seq = sync._last_seq
		perf.last_at = now
	# How far the newest snapshot is ahead of the interpolation's render time (below 0: extrapolating).
	if not sync._snapshots.empty() and sync._render_time != null:
		var cushion = sync._snapshots[- 1].time - sync._render_time
		perf.min_cushion = min(perf.min_cushion, cushion)
		if cushion < 0:
			perf.starved += 1


func log_perf(tag: String) -> void :
	if perf.empty() or perf.frames == 0:
		return
	var main = get_tree().current_scene
	var sync = main.get_node("LanWaveSync") if main != null and main.filename == MenuData.game_scene else null
	var mod_us = - 1
	if sync != null:
		var start = OS.get_ticks_usec()
		if sync.is_host:
			var _snapshot = sync._build_snapshot()
			# Not sent: clients would see a gap.
			sync._snapshot_seq -= 1
		else:
			# Step 0: the render clock stays where it is.
			sync._update_puppets(0.0)
		mod_us = OS.get_ticks_usec() - start
	print("[TEST] ", tag, " perf_detail physics_ms=", stepify(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1), " process_ms=", stepify(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1), " active_bodies=", Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), " collision_pairs=", Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " ", "build_snapshot_us=" if sync != null and sync.is_host else "update_puppets_us=", mod_us)
	print("[TEST] ", tag, " perf frames=", perf.frames, " avg_fps=", stepify(perf.frames / max(perf.time, 0.001), 0.1), " max_frame_ms=", stepify(perf.max_ms, 0.1), " slow_frames=", perf.slow, " snaps=", perf.snaps, " snap_hz=", stepify(perf.snaps / max(perf.time, 0.001), 0.1), " lost=", perf.lost, " max_gap_ms=", perf.max_gap, " min_cushion_ms=", stepify(perf.min_cushion, 1), " starved_frames=", perf.starved, " max_entities=", perf.get("max_entities", 0), " received_lost_by_size=", perf.get("by_size", {}))
	perf_reset()


func add_fake_players(net, count: int) -> void :
	var LobbyRules = load("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
	var NetProtocol = load("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
	var characters = LobbyRules.get_available_characters()
	for i in count:
		var index = net.players.size()
		# FAKE_NAMES=a,b,...: their names (screenshots), else Fake<index>.
		var names = OS.get_environment("FAKE_NAMES").split(",", false)
		var entry = NetProtocol.new_player_entry(1000 + index, index, names[i] if i < names.size() else "Fake%d" % index)
		var character = characters[(index * 7) % characters.size()]
		if i == 0:
			# Engineer: starts with a turret, so structures get tested.
			for c in characters:
				if c.my_id == "character_engineer":
					character = c
		entry.character_id = character.my_id
		var choices = LobbyRules.get_starting_choices(character)
		for pick in LobbyRules.get_pick_count(character):
			if pick < choices.size():
				entry.weapon_ids.append(choices[pick].my_id)
		entry.ready = true
		net.players.append(entry)
	net._broadcast_lobby_state()


func log_names(tag: String) -> void :
	var main = get_tree().current_scene
	var out = []
	for i in main._players.size():
		var c = main._players_ui[i].player_life_bar_container
		var label = c.get_node_or_null("LanNameLabel")
		out.append("%d:%s bar=%s color=%s" % [i, label.text if label else "-", main._players_ui[i].player_life_bar.visible, label.get_color("font_color").to_html(false) if label else "-"])
	print("[TEST] ", tag, " names=", out)


func log_hud(tag: String) -> void :
	var main = get_tree().current_scene
	var positions = []
	var hud = []
	for i in main._players.size():
		positions.append(main._players[i].global_position.round())
		var ui = main._players_ui[i]
		hud.append("%d:%s/%s" % [i, ui.hud_container.name, "vis" if ui.hud_container.visible else "hid"])
	print("[TEST] ", tag, " players=", main._players.size(), " positions=", positions)
	print("[TEST] ", tag, " hud=", hud)
	print("[TEST] ", tag, " lifebars=", main.get_node("%PlayerLifeBarContainerP12").name, " things12=", main.get_node("%UIThingsToProcessPlayerContainer12").name, " max_players=", CoopService.get_max_players(), " color11=", CoopService.get_player_color(11))
	var gold = []
	for i in RunData.get_player_count():
		gold.append(RunData.get_player_gold(i))
	print("[TEST] ", tag, " gold=", gold, " wave=", RunData.current_wave, " time_left=", main._wave_timer.time_left)


func log_scaling(tag: String) -> void :
	var main = get_tree().current_scene
	var zone = ZoneService.current_zone
	print("[TEST] ", tag, " zone=", zone.width, "x", zone.height, " rect=", ZoneService.get_current_zone_rect(), " camera_max=", ZoneService.current_zone_max_camera_rect)
	print("[TEST] ", tag, " coop enemies=", CoopService.additional_enemies_per_coop_player, " hp=", CoopService.additional_enemy_health_per_coop_player, " dmg=", CoopService.additional_enemy_damage_per_coop_player, " hp100=", EntityService.get_final_enemy_health(100), " dmg100=", EntityService.get_final_enemy_damage(100.0), " max_enemies=", main._entity_spawner._current_wave_data.max_enemies, " materials_factor=", stepify(CoopService.get_coop_materials_factor(), 0.01), " removed_for_perf=", main._entity_spawner.enemies_removed_for_perf)


func log_camera(tag: String) -> void :
	var main = get_tree().current_scene
	var cam = main._camera
	print("[TEST] ", tag, " camera targets=", cam.targets.size(), " snapped=", cam._is_snapped, " dynamic=", cam.dynamic_camera_enabled, " zoom=", cam.zoom, " pos=", cam.global_position.round(), " p0=", main._players[0].global_position.round())


func log_enemies(tag: String) -> void :
	var main = get_tree().current_scene
	var spawner = main._entity_spawner
	print("[TEST] ", tag, " enemies=", spawner.enemies.size(), " queued=", spawner.queue_to_spawn.size(), " removed_for_perf=", spawner.enemies_removed_for_perf, " fps=", Engine.get_frames_per_second(), " time_left=", main._wave_timer.time_left)


func center_offset(i: int) -> Vector2:
	return ZoneService.get_map_center() + Vector2(450, 0).rotated(i * PI / 2)


func visible_children(node) -> int:
	var n = 0
	if is_instance_valid(node):
		for c in node.get_children():
			if c.visible and c.get("velocity") != null and c.velocity != Vector2.ZERO:
				n += 1
	return n


func log_mode(tag: String) -> void :
	var net = get_node_or_null("/root/LanNet")
	if net != null and net.mode != null:
		var state: Dictionary = net.mode.state.duplicate()
		# The draft pool is long; its size is enough.
		if state.has("pool"):
			state.pool = state.pool.size()
		print("[TEST] ", tag, " mode=", net.mode.id, " serial=", net.mode.serial, " state=", to_json(state))


# DLC_LOG=s: every s seconds in a wave, the outlines and dlc lines (long waves).
var dlc_log_t: = 0.0
func dlc_log_watch(delta: float) -> void :
	if OS.get_environment("DLC_LOG") == "":
		return
	var main = get_tree().current_scene
	var sync = main.get_node_or_null("LanWaveSync") if main != null else null
	if sync == null or main._cleaning_up:
		dlc_log_t = 0.0
		return
	dlc_log_t += delta
	if dlc_log_t >= float(OS.get_environment("DLC_LOG")):
		dlc_log_t = 0.0
		log_dlc(role + "_every", main, sync)


# The item set of DLC_SET (default abyssal_terrors), null when it isn't owned.
func dlc_item_set():
	var id: = OS.get_environment("DLC_SET") if OS.get_environment("DLC_SET") != "" else "abyssal_terrors"
	if not ProgressData.is_dlc_available(id):
		return null
	for update_data in ItemService.update_data_list:
		if update_data != null and update_data.id == id:
			return update_data.item_set
	return null


# DLC_ITEMS=k: the DLC's items and weapons whose index % 7 == k for players 0 and 1 (weapons only
# into free slots), so 7 runs cover all of them.
func dlc_items_test(k: int) -> void :
	var dlc = dlc_item_set()
	var added = []
	for i in dlc.items.size():
		if i % 7 == k:
			for player_index in 2:
				RunData.add_item(dlc.items[i], player_index)
			added.append(dlc.items[i].my_id)
	for i in dlc.weapons.size():
		if i % 7 == k:
			for player_index in 2:
				if RunData.players_data[player_index].weapons.size() < 6:
					var _w = RunData.add_weapon(dlc.weapons[i], player_index)
			added.append(dlc.weapons[i].my_id)
	print("[TEST] dlc_items k=", k, " of items=", dlc.items.size(), " weapons=", dlc.weapons.size(), ": ", added)


# Role title: the main menu's layout (the Multiplayer button must not push it off the screen).
func _title_step() -> void :
	# Step 0: wait; 1: as loaded (Continue shown with a saved run); 2: Continue hidden.
	if step == 0:
		next_t = 2.0
		step = 1
		return
	var main_menu = menus()._main_menu
	var tag = "title" if step == 1 else "title_no_continue"
	var out = []
	for path in ["LogoContainer", "EmptySpace", "MarginContainer"]:
		out.append("%s=%s" % [path, main_menu.get_node(path).get_global_rect()])
	print("[TEST] ", tag, " continue=", main_menu.continue_button.visible, " menu=", main_menu.get_global_rect(), " ", out, " right=", main_menu.right_container.get_global_rect())
	for button in main_menu.left_container.get_children():
		if button is Control and button.visible:
			print("[TEST] ", tag, "   ", button.name, " ", button.get_global_rect())
	shot(tag)
	if step == 1:
		main_menu.continue_button.visible = not main_menu.continue_button.visible
		next_t = t + 1.0
		step = 2
		return
	get_tree().quit()


# DLC enemies (see the header): pivots, charmed projectiles, local projectiles, Pursuer sizes, lungs.
func log_dlc(tag: String, main: Node, wave_sync: Node) -> void :
	var pivots = []
	for boss in main._entity_spawner.bosses:
		for pivot in find_pivots(boss, []).slice(0, 1):
			pivots.append("%s:%d/%.2f" % [boss.enemy_id, pivot.direction, fposmod(pivot.rotation, TAU)])
		pivots.append("%s:n=%d" % [boss.enemy_id, find_pivots(boss, []).size()])
	var hue = 0
	var local = 0
	var active = 0
	for projectile in main._enemy_projectiles.get_children():
		if not projectile is Projectile or not projectile._hitbox.active:
			continue
		active += 1
		var material = projectile._sprite.material
		if material is ShaderMaterial and material.shader == load("res://resources/shaders/hue_shift_shadermat.tres").shader:
			hue += 1
		if projectile.lan_net_id == 0 and projectile.get_parent() == main._enemy_projectiles:
			local += 1
	var sizes = []
	var full = 0
	var mirrored = []
	var angry = []
	var charmed = []
	var ids = wave_sync._entities.keys()
	ids.sort()
	for net_id in ids:
		var e = wave_sync._entities[net_id]
		if not is_instance_valid(e) or e.dead:
			continue
		if e is Pursuer:
			sizes.append("%d:%.2f" % [net_id, e.sprite.scale.y])
		if e.get("is_full") == true:
			full += 1
		if e is Enemy and e.has_outline(Utils.CHARM_COLOR):
			charmed.append(net_id)
		if e.get("sprite_full") != null and e.sprite.scale.x < 0:
			mirrored.append(net_id)
		if e.get("angry_sound") != null and e._current_movement_behavior == e._on_triggered_movement_behavior:
			angry.append(net_id)
	print("[TEST] ", tag, " dlc time_left=", stepify(main._wave_timer.time_left, 0.01), " pivots=", pivots, " enemy_projectiles=", active, " hue=", hue, " local=", local, " pursuer_sizes=", sizes, " full_lungs=", full, " mirrored_lungs=", mirrored, " angry=", angry, " charmed=", charmed)



# Primal Dread ground effects and evolution (GPE_TEST): the hole layout, active puddles by
# kind (and how many of them have their areas on: clients must have 0), puddles the sync tracks,
# evolved enemies by net id, the enemy time factor and its overlay.
func log_gpe(tag: String, main: Node, wave_sync: Node) -> void :
	var holes = []
	for child in main._gpe_container.get_children():
		if child.filename.find("holes_") >= 0:
			holes.append(child.filename.get_file())
		elif child is Hole:
			holes.append("single:%s" % child.global_position.round())
	var puddles = {"AcidPuddle": 0, "PetrolPuddle": 0, "FirePuddle": 0}
	var monitoring = 0
	for container in [main._gpe_container, main._fire_puddles_container]:
		for child in container.get_children():
			if child is Area2D and child.has_method("is_active") and child.is_active():
				var kind = "FirePuddle" if child is FirePuddle else "PetrolPuddle" if child is PetrolPuddle else "AcidPuddle"
				puddles[kind] += 1
				if child.monitoring:
					monitoring += 1
	var mutant = []
	var meca = []
	var ids = wave_sync._entities.keys()
	ids.sort()
	for net_id in ids:
		var e = wave_sync._entities[net_id]
		if is_instance_valid(e) and e is Enemy and not e.dead:
			if e._is_mutant and e.has_outline(Utils.MUTANT_COLOR):
				mutant.append(net_id)
			elif e._is_meca and e.has_outline(Utils.MECA_COLOR):
				meca.append(net_id)
	var overlay = main.get_node_or_null("UI/ShiftTimeVisualEffect")
	# Clients: a puddle of their own must be refused (the host's come as events).
	var local_blocked = "-"
	if not wave_sync.is_host:
		local_blocked = main._gpe_spawner.get_new_acid_puddle_at_pos(main._players[0].global_position, false, true) == null
	var consumables = []
	for consumable in main._consumables:
		if is_instance_valid(consumable) and consumable.consumable_data != null:
			consumables.append(consumable.consumable_data.my_id)
	consumables.sort()
	print("[TEST] ", tag, " gpe consumables=", consumables)
	# Oviraptors and iguanodons by net id: shown or hidden, and their facing in degrees.
	var chargers = []
	for net_id in ids:
		var e = wave_sync._entities[net_id]
		if is_instance_valid(e) and e is Enemy and not e.dead and e._current_movement_behavior is GoTowardsBorderOppositeMovementBehavior:
			chargers.append("%d:%s:%d" % [net_id, "shown" if e.visible else "hidden", int(round(rad2deg(e.rotation)))])
	print("[TEST] ", tag, " gpe chargers=", chargers)
	print("[TEST] ", tag, " gpe local_blocked=", local_blocked, " holes=", holes, " puddles=", puddles, " monitoring=", monitoring, " tracked=", wave_sync._puddles.size(), " mutant=", mutant, " meca=", meca, " time_factor=", stepify(EntityService.enemy_time_factor, 0.01), " overlay=", overlay.visible if overlay != null else "-", " wave_seed=", get_node("/root/LanNet").lobby_settings.get("wave_seed", 0))


# GPE_TEST=1 (host, t=15): an acid, a petrol and a fire puddle, a single hole and a mutant and a
# meca enemy near the host player, and the enemy time at half speed for 4 s. On clients, a local
# puddle must not appear.
func gpe_test(main: Node) -> void :
	var pos: Vector2 = main._players[0].global_position
	var gpe = main._gpe_spawner
	var acid = gpe.get_new_acid_puddle_at_pos(pos + Vector2(-200, 0), false, false)
	var petrol = gpe.get_new_petrol_puddle_at_pos(pos + Vector2(200, 0), true, false)
	var burning = BurningData.new()
	burning.chance = 1.0
	burning.damage = 5
	burning.duration = 3
	var fire = gpe.get_new_fire_puddle_at_pos(pos + Vector2(0, 200), burning, GPESpawner.FIRE_PUDDLE_SCALE * 2, 6.0, 0)
	gpe.spawn_single_hole_at_position(pos + Vector2(0, -300))
	EntityService.slow_enemy_time(0.5, 4.0)
	var spawner = main._entity_spawner
	var scene = load("res://entities/units/enemies/crash_zone/basic/spitter/spitter.tscn")
	for i in 2:
		# Far from the players, so their weapons don't kill them before the next log.
		var request = SpawnRequest.new(EntityType.ENEMY, scene, ZoneService.get_current_zone_rect().end - Vector2(300 + i * 150, 400))
		request.is_mutant = i == 0
		request.is_meca = i == 1
		spawner.queue_to_spawn.push_back(request)
	var dlc_data = ItemService.get_dlc_data_by_id("primal_dread")
	main.spawn_consumable(dlc_data.meca_fruit, pos + Vector2(-100, 100), pos)
	main.spawn_consumable(dlc_data.mutant_fruit, pos + Vector2(100, 100), pos)
	print("[TEST] gpe_test acid=", acid != null, " petrol=", petrol != null, " fire=", fire != null)


func find_pivots(node: Node, result: Array = []) -> Array:
	if node is Pivot:
		result.append(node)
	for child in node.get_children():
		var _r = find_pivots(child, result)
	return result


func log_sync(tag: String) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene:
		print("[TEST] ", tag, " not in wave, scene=", scene_name())
		return
	var out = []
	for p in main._players:
		var pd = RunData.players_data[p.player_index]
		out.append("%d:%s%s hp=%d/%d spd=%d g=%d xp=%.1f lvl=%d" % [p.player_index, p.global_position.round(), " dead" if p.dead else "", p.current_stats.health, p.max_stats.health, p.get_move_speed(), pd.gold, pd.current_xp, pd.current_level])
	var cam = main._camera
	log_mode(tag)
	print("[TEST] ", tag, " hurtbox_hits contacts=", enemy_contacts, " bullets=", enemy_bullet_hits)
	print("[TEST] ", tag, " time_left=", stepify(main._wave_timer.time_left, 0.1), " players=", out, " cam_targets=", cam.targets.size(), " sync=", main.get_node_or_null("LanWaveSync") != null)
	var spawner = main._entity_spawner
	var boss_hp = []
	for boss in spawner.bosses:
		boss_hp.append("%d/%d bar=%s" % [boss.current_stats.health, boss.max_stats.health, boss.life_bar.visible])
	print("[TEST] ", tag, " enemies=", spawner.enemies.size(), " bosses=", spawner.bosses.size(), " boss_hp=", boss_hp, " neutrals=", spawner.neutrals.size(), " structures=", spawner.structures.size(), " pets=", spawner.pets.size(), " births=", spawner.active_births, " gold=", main._active_golds.size(), " consumables=", main._consumables.size(), " p0_upgrade_icons=", main._things_to_process_player_containers[0].upgrades.get_child_count(), " p0_crate_icons=", main._things_to_process_player_containers[0].consumables.get_child_count())
	var sync = main.get_node_or_null("LanWaveSync")
	if sync != null:
		# Enemy outlines by net id (compare host and client) and the scene effect behaviours (DLC curse).
		var cursed = []
		var outlined = {"boosted": 0, "charmed": 0}
		for net_id in sync._entities:
			var e = sync._entities[net_id]
			if is_instance_valid(e) and e is Enemy and not e.dead:
				if e.has_outline(Utils.CURSE_COLOR):
					cursed.append(net_id)
				if e.has_outline(Utils.BOOST_COLOR):
					outlined.boosted += 1
				if e.has_outline(Utils.CHARM_COLOR):
					outlined.charmed += 1
		cursed.sort()
		print("[TEST] ", tag, " outlines cursed=", cursed, " boosted=", outlined.boosted, " charmed=", outlined.charmed, " scene_behaviors=", main._effect_behaviors.get_child_count())
		log_dlc(tag, main, sync)
		log_gpe(tag, main, sync)
		var steps = []
		for i in RunData.get_player_count():
			steps.append("%d:%d hp=%d" % [i, RunData.steps_taken_this_wave[i], RunData.get_player_max_health(i)])
		print("[TEST] ", tag, " steps ", steps)
	if sync != null:
		var ids = sync._entities.keys()
		ids.sort()
		var sample = []
		for net_id in ids.slice(0, min(5, ids.size()) - 1) if not ids.empty() else []:
			var e = sync._entities[net_id]
			if is_instance_valid(e):
				sample.append("%d:%s%s" % [net_id, e.global_position.round(), " dead" if e.dead else ""])
		var swings = 0
		for p in main._players:
			for w in p.current_weapons:
				if w._is_shooting:
					swings += 1
		print("[TEST] ", tag, " event_counts=", sync.event_counts)
		var birth_positions = []
		for birth_id in sync._births:
			var birth = sync._births[birth_id]
			if is_instance_valid(birth) and birth.visible:
				birth_positions.append("%d:%s" % [birth_id, birth.global_position.round()])
		var gold_scales = []
		for gold in main._active_golds:
			if gold.scale.x > 1.0:
				gold_scales.append(stepify(gold.scale.x, 0.01))
		print("[TEST] ", tag, " births=", birth_positions, " grown_golds=", gold_scales.size(), " max_gold_scale=", gold_scales.max() if not gold_scales.empty() else 1.0)
		print("[TEST] ", tag, " synced_projectiles=", sync._projectiles.size(), " flying_player_proj=", visible_children(main._player_projectiles), " flying_enemy_proj=", visible_children(main._enemy_projectiles), " weapons_attacking=", swings)
		print("[TEST] ", tag, " net_entities=", ids.size(), " fps=", Engine.get_frames_per_second(), " snapshot_bytes=", sync.SNAPSHOT_HEADER_SIZE + sync.SNAPSHOT_PLAYER_SIZE * main._players.size() + 2 + sync.SNAPSHOT_ENTITY_SIZE * ids.size(), " sample=", sample)
		log_visuals(tag, main, main.get_node("LanWaveSync"))
		log_quirk_fixes(tag, main, main.get_node("LanWaveSync"))
		log_scaling(tag)
		log_perf(tag)
	shot(tag)


# Off-screen arrows, skulls of dead players, manual aim.
func log_visuals(tag: String, main, wave_sync) -> void :
	var screen = main.get_viewport().get_visible_rect()
	var offscreen = []
	var skulls = []
	var rotations = []
	for p in main._players:
		if not screen.has_point(p.get_global_transform_with_canvas().origin):
			offscreen.append(p.player_index)
		if main._players_ui[p.player_index].player_life_bar_container.has_node("LanDeadIcon"):
			skulls.append(p.player_index)
		rotations.append("%d:%s" % [p.player_index, stepify(rad2deg(p.current_weapons[0].rotation), 1) if not p.current_weapons.empty() else "-"])
	var aims = []
	for index in wave_sync._remote_states:
		aims.append("%d:%s" % [index, wave_sync._remote_states[index].aim.round()])
	print("[TEST] ", tag, " arrows=", main.get_node_or_null("UI/LanOffscreenArrows") != null, " offscreen=", offscreen, " skulls=", skulls, " manual_aim=", Utils.is_manual_aim(wave_sync._local_index), " crosshair_cursor=", main._crosshair_cursor_active, " weapon_rot=", rotations, " remote_aims=", aims)


func aim_test_setup() -> void :
	if OS.get_environment("AIM_TEST") != "1":
		return
	ProgressData.settings.manual_aim = true
	if role == "join":
		var motion = InputEventMouseMotion.new()
		motion.position = Vector2(60, 60)
		motion.global_position = motion.position
		Input.parse_input_event(motion)


func _host_step() -> void :
	var net = get_node("/root/LanNet")
	var m = menus()
	match step:
		0:
			next_t = 3.0
		1:
			if OS.get_environment("FAKE_SAVED_RUN") == "1":
				# A stand-in for the player's own "Continue" run; in memory only (the driver quits
				# without saving).
				ProgressData.saved_run_state = {"has_run_state": true, "current_wave": 7}
			log_saved_run("host_before_session")
			# ITEM_SETS_OFF=id,...: item sets the host switches off (in memory, not saved).
			for item_set_id in OS.get_environment("ITEM_SETS_OFF").split(",", false):
				ProgressData.remove_item_set(item_set_id)
			print("[TEST] host_item_sets ", ProgressData.active_update_data)
			m._main_menu.left_container.get_node("LanMultiplayerButton").emit_signal("pressed")
			var host_name = OS.get_environment("HOST_NAME") if OS.get_environment("HOST_NAME") != "" else "HostPlayer"
			m.get_node("LanMultiplayerMenu")._name_edit.text = host_name
			m.get_node("LanMultiplayerMenu")._on_NameEdit_text_changed(host_name)
			m.get_node("LanMultiplayerMenu")._host_button.emit_signal("pressed")
			next_t = t + 0.5
		2:
			pick_and_ready(m.get_node("LanLobby"), 0)
			next_t = 9.0
		3:
			if round_nr == 1:
				add_fake_players(net, int(OS.get_environment("FAKES")) if OS.get_environment("FAKES") != "" else 1)
			else:
				# Back in the lobby everyone is un-readied.
				for entry in net.players:
					if entry.peer_id >= 1000:
						entry.ready = true
				net._broadcast_lobby_state()
			next_t = 10.0
		4:
			var expect = int(OS.get_environment("EXPECT"))
			if expect > 0 and t < 120.0:
				var ready = 0
				for entry in net.players:
					if entry.ready:
						ready += 1
				if ready < expect or net.players.size() < expect:
					if int(t) % 5 == 0 and fmod(t, 1.0) < 0.26:
						print("[TEST] host waiting for players: ", net.players.size(), " joined, ", ready, " ready of ", expect, " t=", stepify(t, 0.1))
					step -= 1
					next_t = t + 0.25
					return
			if expect > 0:
				print("[TEST] host starting with ", net.players.size(), " players at t=", stepify(t, 0.1))
				# The later steps' times are relative to the usual Start at t=10.
				t = 10.0
			log_lobby("host_before_start")
			DebugService.invulnerable = OS.get_environment("MORTAL") != "1"
			DebugService.custom_wave_duration = int(OS.get_environment("WAVE_DURATION")) if OS.get_environment("WAVE_DURATION") != "" else 20
			if OS.get_environment("START_WAVE") != "":
				DebugService.starting_wave = int(OS.get_environment("START_WAVE"))
			if OS.get_environment("ENEMY_MULT") != "":
				DebugService.nb_enemies_mult = float(OS.get_environment("ENEMY_MULT"))
			if OS.get_environment("CHOICE_TIME") != "":
				net.lobby_settings.choice_time = int(OS.get_environment("CHOICE_TIME"))
				net._broadcast_lobby_state()
			if OS.get_environment("SCALING_PRESET") != "":
				net.set_lobby_settings({"scaling_preset": int(OS.get_environment("SCALING_PRESET"))})
			if OS.get_environment("MODE") != "":
				net.lobby_settings.mode = OS.get_environment("MODE")
				net._broadcast_lobby_state()
			if OS.get_environment("ZONE") != "":
				net.lobby_settings.zone = int(OS.get_environment("ZONE"))
				net._broadcast_lobby_state()
			# SHARE_MATERIALS=0 / SHARE_CRATES=0: loot sharing off (not remembered).
			for key in ["share_materials", "share_crates"]:
				if OS.get_environment(key.to_upper()) != "":
					net.lobby_settings[key] = OS.get_environment(key.to_upper()) == "1"
					net._broadcast_lobby_state()
			m.get_node("LanLobby")._start_button.emit_signal("pressed")
			next_t = 13.0
		5:
			# 3 s into the wave (with EXPECT, slow clients can take a while to load).
			var wave = get_tree().current_scene
			if wave == null or wave.filename != MenuData.game_scene or wave._wave_timer.wait_time - wave._wave_timer.time_left < 3.0:
				if t < 200.0:
					step -= 1
					next_t = t + 0.1
					waited_for_wave = true
					return
			if waited_for_wave:
				t = 13.0
			if first_wave == 0:
				first_wave = RunData.current_wave
			aim_test_setup()
			log_sync("host_w13")
			Input.action_press("button_move_left_0")
			# A boss and three trees, which wave 1 doesn't have.
			var spawner = get_tree().current_scene._entity_spawner
			var rect = ZoneService.get_current_zone_rect()
			var boss_scene = OS.get_environment("BOSS") if OS.get_environment("BOSS") != "" else "res://entities/units/enemies/crash_zone/elites/rhino/rhino.tscn"
			spawner.queue_to_spawn_bosses.push_back(SpawnRequest.new(EntityType.BOSS, load(boss_scene), rect.end - Vector2(150, 150)))
			if OS.get_environment("SPAWN") != "":
				for i in 4:
					var spawn_pos = center_offset(i) + Vector2(0, 200)
					if OS.get_environment("SPAWN_NEAR") == "1":
						spawn_pos = get_tree().current_scene._players[0].global_position + Vector2(250, 0).rotated(i * PI / 2)
					spawner.queue_to_spawn.push_back(SpawnRequest.new(EntityType.ENEMY, load(OS.get_environment("SPAWN")), spawn_pos))
			if OS.get_environment("CHARM_BOOST") == "1":
				# Romantic's charm chance is half the max HP in percent: 100 % from here on.
				for i in 2:
					RunData.add_stat(Keys.stat_max_hp_hash, 200, i)
			for i in 3:
				spawner.queue_to_spawn_trees.push_back(SpawnRequest.new(EntityType.NEUTRAL, load("res://entities/units/neutral/tree.tscn"), Vector2(150 + i * 120, rect.end.y - 150)))
			# An enemy spawning right on the host player: vanilla moves its marker elsewhere.
			spawner.queue_to_spawn.push_back(SpawnRequest.new(EntityType.ENEMY, load("res://entities/units/enemies/crash_zone/basic/spitter/spitter.tscn"), get_tree().current_scene._players[0].global_position))
			# Spitters shoot enemy projectiles.
			for i in 4:
				spawner.queue_to_spawn.push_back(SpawnRequest.new(EntityType.ENEMY, load("res://entities/units/enemies/crash_zone/basic/spitter/spitter.tscn"), center_offset(i)))
			next_t = 14.0
		6:
			Input.action_release("button_move_left_0")
			log_sync("host_w14")
			next_t = 15.0
		7:
			if OS.get_environment("CHARM_TEST") == "1":
				var charmed = 0
				for enemy in get_tree().current_scene._entity_spawner.enemies:
					if not enemy.dead and enemy.enemy_id == "spitter":
						enemy.set_charmed(0)
						charmed += 1 if enemy.get_charmed_by_player_index() == 0 else 0
				print("[TEST] charm_test charmed=", charmed)
			if OS.get_environment("GPE_TEST") == "1":
				gpe_test(get_tree().current_scene)
			next_t = 16.0
		8:
			var main7 = get_tree().current_scene
			# A level-up for the host player and the client's, and three crates right next to the
			# host (vanilla hands each to a player with the fewest, so everyone gets one).
			RunData.add_xp(30, 0)
			RunData.add_xp(30, 1)
			# A locked shop item for player 5 (the save loader only has 4 slots for them).
			if RunData.get_player_count() > 5:
				RunData.lock_player_shop_item(ItemService.get_element_safe(ItemService.items, "item_coupon"), RunData.current_wave, 5)
			for i in 3:
				# get_node_from_pool creates the pool, which vanilla's pickup returns the crate to.
				var crate = main7.get_node_from_pool(main7._consumable_pool_id, main7._consumables_container)
				if crate == null:
					crate = main7.consumable_scene.instance()
					main7._consumables_container.add_child(crate)
					var _c = crate.connect("picked_up", main7, "on_consumable_picked_up")
				crate.already_picked_up = false
				crate.consumable_data = ItemService.get_element_safe(ItemService.consumables, "consumable_item_box")
				crate.set_texture(crate.consumable_data.icon)
				var crate_pos = main7._players[0].global_position + Vector2(5 + i * 10, 0)
				crate.drop(crate_pos, 0, crate_pos)
				main7._consumables.push_back(crate)
			# An explosion next to the host player.
			var explode_args = WeaponServiceExplodeArgs.new()
			explode_args.pos = get_tree().current_scene._players[0].global_position + Vector2(150, 0)
			explode_args.damage = 30
			explode_args.accuracy = 1.0
			explode_args.crit_damage = 1.5
			explode_args.from_player_index = 0
			var _explosion = WeaponService.explode(load("res://items/all/00_base_game/landmines/landmine_exploding_effect.tres"), explode_args)
			# The injected boss has 1 HP in wave 1.
			for boss in get_tree().current_scene._entity_spawner.bosses:
				boss.max_stats.health = 5000
				boss.current_stats.health = 5000
				boss.emit_signal("health_updated", boss, 5000, 5000)
			burn_spread_test(get_tree().current_scene)
			if OS.get_environment("STALE_DIE_ARGS") == "1":
				# As vanilla leaves it after a player was killed by something since freed.
				var gone = Node.new()
				Utils.default_die_args.from = gone
				gone.free()
			contact_test(get_tree().current_scene)
			progress_test(get_tree().current_scene)
			meca_test(get_tree().current_scene)
			if OS.get_environment("FULL_SLOTS") != "":
				# Every weapon slot of players 0 and 1 holds a knife (the shop then buys one more).
				var knife = ItemService.get_element_safe(ItemService.weapons, "weapon_knife_1")
				for player_index in 2:
					while RunData.players_data[player_index].weapons.size() < RunData.get_player_effect(Keys.weapon_slot_hash, player_index):
						var _w = RunData.add_weapon(knife, player_index)
				print("[TEST] full_slots weapons=", RunData.players_data[0].weapons.size(), ",", RunData.players_data[1].weapons.size())
			if OS.get_environment("DLC_ITEMS") != "" and dlc_item_set() != null:
				dlc_items_test(int(OS.get_environment("DLC_ITEMS")))
			if OS.get_environment("ITEMS") != "":
				for item_id in OS.get_environment("ITEMS").split(","):
					var item = ItemService.get_element_safe(ItemService.items, item_id)
					for player_index in 2:
						RunData.add_item(item, player_index)
				print("[TEST] items added for players 0 and 1: ", OS.get_environment("ITEMS"))
			if OS.get_environment("PET_TEST") == "1":
				RunData.add_item(ItemService.get_element_safe(ItemService.items, "item_blazemander"), 0)
				RunData.add_item(ItemService.get_element_safe(ItemService.items, "item_bonk_dog"), 1)
				print("[TEST] pet_test items added: player 0 blazemander, player 1 bonk_dog")
			log_sync("host_w16")
			next_t = 18.0
		9:
			if OS.get_environment("HOST_QUITS") == "1":
				# The game is closed mid-run: the client must see the host's goodbye, not reconnect.
				print("[TEST] host closing the game at t=", stepify(t, 0.1))
				get_tree().quit()
				return
			var main = get_tree().current_scene
			# Fresh args: vanilla's Utils.default_die_args may hold a freed killer.
			main._players[2].die(Entity.DieArgs.new())
			if OS.get_environment("HOST_DIES") == "1":
				# With the fake: Team Race's first team is out, the run ends with this wave.
				main._players[0].die(Entity.DieArgs.new())
			var spawner = main._entity_spawner
			if not spawner.neutrals.empty():
				spawner.neutrals[0].die()
			for boss in spawner.bosses:
				boss.current_stats.health = int(OS.get_environment("BOSS_HP2")) if OS.get_environment("BOSS_HP2") != "" else 2500
				boss.emit_signal("health_updated", boss, boss.current_stats.health, boss.max_stats.health)
			next_t = 20.0
		10:
			log_sync("host_w20")
			# Pause menu on the host: the wave keeps running everywhere.
			get_tree().current_scene._pause_menu.pause(0)
			print("[TEST] host_pause open=", get_tree().current_scene._pause_menu.visible, " tree_paused=", get_tree().paused)
			next_t = 23.0
		11:
			log_sync("host_w23")
			var main = get_tree().current_scene
			if main.filename != MenuData.game_scene:
				# The run is already lost (MORTAL=1).
				next_t = 24.0
				return
			main._pause_menu.unpause()
			if OS.get_environment("KILL_ALL") == "1":
				# Everyone dies: the run is lost.
				for p in main._players:
					if not p.dead:
						p.die(Entity.DieArgs.new())
			next_t = 24.0
		12:
			if waves_target() > 1 or OS.get_environment("IDLE_CHOICE") != "":
				if wait_for_wave(waves_target() + 1):
					log_run_check("host_next_wave")
				elif end_step == 3:
					# The run ended first (won at wave 20, or lost) and the end screen is done.
					print("[TEST] host run over before wave ", waves_target() + max(first_wave, 1), ", back in the lobby")
				else:
					step -= 1
					return
			else:
				next_t = 55.0 if OS.get_environment("KILL_ALL") != "1" else 40.0
		13:
			log_lobby("host_after_wave_end")
			log_wave_end("host_wave_end")
			next_t = t + 2.0
		14:
			if next_round():
				# Pick and ready again (step 2), then Start (step 4).
				step = 1
				t = 8.5
				next_t = 9.0
				return
			if scene_name() == MenuData.game_scene:
				# Still in a wave (WAVES=n ends in wave n+1): leave() would reset RunData under the
				# running wave; quit as closing the game would.
				print("[TEST] host quitting in the wave")
				get_tree().quit()
				return
			net.leave()
			log_saved_run("host_after_session")
			get_tree().quit()


# Right after the wave-end state (the host's scene changes next): enter and leave the solo view,
# check the solo invariants in between and that the run is unchanged afterwards.
# What the session counts for (game/session_progress.gd), at t=16 in the first wave: the host
# completes a challenge with an item reward it doesn't have yet (forwarded to the clients); the
# client tries one on its own (ignored in a wave). Both add a jellyshield to their player and log
# its angle against the wave time 2 s later.
var progress_reward_chal = null
var progress_client_chal = null


# MECA_TEST=1 (host and join, Primal Dread on): at t=16 the host drops meca parts at its player
# (evolution > 0) and a mutation fruit at the client's (evolution < 0); both log each player's
# things-to-process consumables 1.5 s later. Player 0 must show meca parts, player 1 the fruit, on
# both sides; the host logs the meca parts count.
func meca_test(main) -> void :
	if OS.get_environment("MECA_TEST") != "1" or main == null or main.filename != MenuData.game_scene:
		return
	if role == "host":
		var dlc_data = ItemService.get_dlc_data_by_id("primal_dread")
		if dlc_data != null and main._players.size() > 1:
			RunData.get_player_effects(0)[Keys.stat_evolution_hash] = 1
			RunData.get_player_effects(1)[Keys.stat_evolution_hash] = -1
			main.spawn_consumable(dlc_data.meca_parts_consumable.duplicate(), main._players[0].global_position, main._players[0].global_position)
			main.spawn_consumable(dlc_data.mutation_fruit.duplicate(), main._players[1].global_position, main._players[1].global_position)
	yield(get_tree().create_timer(1.5), "timeout")
	if not is_instance_valid(main) or main != get_tree().current_scene:
		return
	var shown = []
	for i in RunData.get_player_count():
		var ids = []
		for data in main._things_to_process_player_containers[i].consumables._elements:
			ids.append(data.my_id)
		shown.append(ids)
	var meca_parts = []
	for player_data in RunData.players_data:
		meca_parts.append(player_data.meca_parts)
	print("[TEST] meca_test ", role, " things=", shown, " displayed=", main._displayed_consumables_picked_up.slice(0, 1), " meca_parts=", meca_parts)


func progress_test(main) -> void :
	var net = get_node("/root/LanNet")
	if main == null or main.filename != MenuData.game_scene or progress_reward_chal != null:
		return
	log_progress(role + "_wave_start")
	var own_items: Array = net._own_unlocks.get("items_unlocked", [])
	for chal in ChallengeService.challenges:
		if ChallengeService.is_challenge_completed(chal.my_id_hash) or not chal.reward is ItemData:
			continue
		if own_items.has(Keys.generate_hash(chal.reward.my_id)):
			continue
		if progress_reward_chal == null:
			progress_reward_chal = chal
		elif progress_client_chal == null:
			progress_client_chal = chal
			break
	if role == "host" and progress_reward_chal != null:
		ChallengeService.complete_challenge(progress_reward_chal.my_id_hash)
		print("[TEST] host_progress completed=", progress_reward_chal.my_id, " reward=", progress_reward_chal.reward.my_id, " done_here=", ChallengeService.is_challenge_completed(progress_reward_chal.my_id_hash))
	elif role != "host" and progress_client_chal != null:
		# The host's pick is the client's first one as well (same fresh profile); its own try
		# uses the second.
		ChallengeService.complete_challenge(progress_client_chal.my_id_hash)
		print("[TEST] client_progress own_try=", progress_client_chal.my_id, " done_here=", ChallengeService.is_challenge_completed(progress_client_chal.my_id_hash), " (expected false)")
	var player = main._players[net.local_player_index]
	var args = EntitySpawner.SpawnEntityArgs.new(player.global_position, - 1)
	var jellyshield = main._entity_spawner.spawn_entity(player.jellyshield_scene, args)
	jellyshield.init_trajectory(0, 1, player)
	yield(get_tree().create_timer(2.0), "timeout")
	if is_instance_valid(jellyshield) and is_instance_valid(main):
		var timer = main._wave_timer
		var expected = (timer.wait_time - timer.time_left) * jellyshield.rotation_speed
		print("[TEST] ", role, "_jellyshield angle=", stepify(jellyshield._angle, 0.01), " from_wave_time=", stepify(expected, 0.01), " time_left=", stepify(timer.time_left, 0.01))


func log_progress(tag: String) -> void :
	var killed: = 0
	for key in ProgressData.killed_enemies:
		killed += ProgressData.killed_enemies[key]
	var characters = []
	for entry in get_node("/root/LanNet").players:
		var character = ItemService.get_element_safe(ItemService.characters, entry.character_id)
		if character != null:
			var chal_hash = Keys.generate_hash("chal_" + character.name.to_lower().replace("character_", ""))
			characters.append("%s:%s" % [entry.character_id, ChallengeService.is_challenge_completed(chal_hash)])
	var new_challenges = []
	for chal_id in ProgressData.challenges_completed:
		if not get_node("/root/LanNet").progress._start_challenges.has(chal_id):
			var chal = ChallengeService.get_chal(chal_id)
			new_challenges.append(chal.my_id if chal != null else chal_id)
	print("[TEST] ", tag, " character_challenges=", characters, " new_in_session=", new_challenges)
	print("[TEST] ", tag, " counters enemies_killed=", ProgressData.data.get("enemies_killed"), " materials=", ProgressData.data.get("materials_collected"), " trees=", ProgressData.data.get("trees_killed"), " steps=", ProgressData.data.get("steps_taken"), " encyclopedia_kills=", killed, " challenges=", ProgressData.challenges_completed.size())


# After the session: every challenge completed in it, and whether its reward is in the own
# unlock lists (restored by then).
func progress_after_session(_reason) -> void :
	var net = get_node("/root/LanNet")
	var NetProtocol = load("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
	var rewards = []
	for chal_id in ProgressData.challenges_completed:
		if net.progress._start_challenges.has(chal_id):
			continue
		var chal = ChallengeService.get_chal(chal_id)
		if chal == null or chal.reward == null:
			continue
		var reward_id = chal.reward.get("my_id")
		var unlocked = false
		for key in NetProtocol.UNLOCK_KEYS:
			if ProgressData.get(key).has(Keys.generate_hash(str(reward_id))):
				unlocked = true
		rewards.append("%s->%s:%s" % [chal.my_id, reward_id, unlocked])
	print("[TEST] ", role, "_progress_after_session rewards=", rewards, " saves_blocked=", ProgressData.lan_coop_saves_blocked)
	log_progress(role + "_after_session")


func solo_view_test() -> void :
	var net = get_node("/root/LanNet")
	var RB = load("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
	var tag = role + "_solo_view"
	if net.solo_view.active:
		print("[TEST] ", tag, " skipped, main is in the solo view")
		return
	var index: int = net.local_player_index
	var before_json = RB.serialize_run()
	var before_digest = RB.digest()
	var own_data = RunData.players_data[index]
	var own_max_hp = RunData.get_player_max_health(index)
	var own_tracked = RunData.tracked_item_effects[index]
	var coop_count = RunData.get_player_count()
	var entered = net.enter_solo_view()
	print("[TEST] ", tag, " entered=", entered, " index=", index, " coop_players=", coop_count, " count=", RunData.get_player_count(), " coop=", RunData.is_coop_run, " connected=", CoopService.connected_players, " run_index=", net.get_local_run_index())
	print("[TEST] ", tag, " own_data_at_0=", RunData.players_data[0] == own_data, " max_hp=", RunData.get_player_max_health(0), "/", own_max_hp, " tracked_at_0=", RunData.tracked_item_effects[0] == own_tracked, " slots=", RunData.locked_shop_items.size(), " gold=", RunData.get_player_gold(0))
	net.leave_solo_view()
	var after_json = RB.serialize_run()
	print("[TEST] ", tag, " left active=", net.solo_view.active, " count=", RunData.get_player_count(), " coop=", RunData.is_coop_run, " connected=", CoopService.connected_players, " same_json=", after_json == before_json, " same_digest=", RB.digest() == before_digest, " max_hp=", RunData.get_player_max_health(index), "/", own_max_hp)


var pick_wait: = 0.0
var choice_seconds: = - 1


# Between waves: logs (and screenshots) what the choice countdown shows at 13, 8 and 3 s left.
# IDLE_CHOICE=3 (join): the client's choice time never runs out.
func choice_watch() -> void :
	var net = get_node_or_null("/root/LanNet")
	if net == null or not net.between_waves:
		choice_seconds = - 1
		return
	if role == "join" and OS.get_environment("IDLE_CHOICE") == "3" and net.choice_deadline_msec != 0:
		net.choice_deadline_msec = OS.get_ticks_msec() + 3600000
	var time_left: float = net.get_choice_time_left()
	var seconds: = int(ceil(time_left)) if time_left >= 0.0 else - 1
	if seconds == choice_seconds:
		return
	choice_seconds = seconds
	if seconds % 5 != 3:
		return
	var scene = get_tree().current_scene
	var tag = role + "_choice_" + str(seconds)
	if scene is BaseShop:
		var go = scene._get_go_button(0)
		var overlay = scene.get_node("LanShopWaitingOverlay")
		if role == "host" and seconds == 13 and OS.get_environment("IDLE_CHOICE") == "1":
			# The waiting overlay's countdown in the next screenshots.
			scene._on_GoButton_pressed(0)
		print("[TEST] ", tag, " shop go='", go.text, "' go_color=", go.get("custom_colors/font_color"), " overlay=", overlay.visible, " back='", overlay._back_button.text, "' back_disabled=", overlay._back_button.disabled)
	elif scene != null and scene.filename == MenuData.game_scene:
		var label = scene._wave_timer_label
		print("[TEST] ", tag, " upgrades label='", label.text, "' visible=", label.is_visible_in_tree(), " modulate=", label.modulate, " upgrades_ui=", scene._upgrades_ui.visible)
	else:
		print("[TEST] ", tag, " scene=", scene_name())
	shot(tag)


# Between waves: in the solo upgrades UI, picks the first upgrade or takes the crate's item.
func pick_upgrades(delta: float) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or not main._upgrades_ui.visible:
		return
	if int(OS.get_environment("IDLE_CHOICE")) >= 2:
		return
	pick_wait += delta
	if pick_wait < 1.0:
		return
	pick_wait = 0.0
	var container = main._upgrades_ui._player_container1
	var own = RunData.players_data[0]
	var wave_timer = main._wave_timer
	print("[TEST] ", role, "_upgrades wave_timer time_left=", stepify(wave_timer.time_left, 0.01), " paused=", wave_timer.paused, " ticking=", not wave_timer.tick_timer.is_stopped())
	var before = "count=%d coop=%s gold=%d max_hp=%d items=%d" % [RunData.get_player_count(), RunData.is_coop_run, own.gold, RunData.get_player_max_health(0), own.items.size()]
	if container._upgrades_container.visible and not container._old_upgrades.empty():
		var upgrade = container._old_upgrades[0]
		# The upgrade's stat for every player: from the coop run stashed by the solo view before,
		# and after the pick (the coop run again once the last pick left the solo view).
		var net = get_node("/root/LanNet")
		var key_hash = Keys.generate_hash(upgrade.effects[0].key)
		var stat_before = []
		for player_data in net.solo_view._players_data:
			stat_before.append(player_data.effects.get(key_hash))
		container._on_choose_button_pressed(upgrade)
		var stat_after = []
		if net.solo_view.active:
			stat_after = ["own", RunData.players_data[0].effects.get(key_hash)]
		else:
			for player_data in RunData.players_data:
				stat_after.append(player_data.effects.get(key_hash))
		print("[TEST] ", role, "_pick upgrade=", upgrade.my_id, " ", upgrade.effects[0].key, "+", upgrade.effects[0].value, " before ", before, " stat coop_before=", stat_before, " after=", stat_after, " icons=", main._things_to_process_player_containers[net.local_player_index].upgrades._elements)
	elif container._items_container.visible:
		# The host takes the item, the client recycles it (gold shows in its own HUD).
		var item = container._item_data
		var local_index = get_node("/root/LanNet").local_player_index
		if role == "host":
			container._on_TakeButton_pressed()
		else:
			container._on_DiscardButton_pressed()
		print("[TEST] ", role, "_pick item=", item.my_id if item != null else "-", " ", "taken" if role == "host" else "recycled", " before ", before, " after items=", own.items.size(), " gold=", own.gold, " hud_gold=", main._players_ui[local_index].gold.gold_label.text, " crate_icons=", main._things_to_process_player_containers[local_index].consumables._elements.size())
	shot(role + "_upgrades")


var end_step: = 0
var end_wait: = 0.0


# On the end screen: logs what it shows, switches to the other player and back (LAN player
# dropdown), then presses Exit (the client first, the host 3 s
# later) and logs the lobby the client lands in.
func end_screen_actions(delta: float) -> void :
	var scene = get_tree().current_scene
	if scene == null or not scene is BaseEndRun:
		if end_step == 2 and menus() != null:
			end_step = 3
			yield(get_tree().create_timer(0.5), "timeout")
			log_lobby(role + "_after_end_screen")
		elif end_step == 3 and scene != null and scene.filename == MenuData.game_scene:
			end_step = 0
		return
	end_wait += delta
	var tag = role + "_end_screen"
	if end_step == 0 and end_wait >= 1.5:
		log_progress(tag)
		var own = RunData.players_data[0]
		print("[TEST] ", tag, " scene=", scene.filename, " count=", RunData.get_player_count(), " coop=", RunData.is_coop_run, " won=", RunData.run_won, " wave=", RunData.current_wave, " title='", scene._title.text, "' character=", own.current_character.my_id, " gold=", own.gold, " weapons=", own.weapons.size(), " buttons restart=", scene._restart_button.visible, " new_run=", scene._new_run_button.visible, " exit=", scene._exit_button.visible, " exit_focus=", scene._exit_button.has_focus())
		shot(tag)
		end_step = 1
		var player_list = scene.get("_lan_player_list")
		if player_list != null:
			var solo_view = get_node("/root/LanNet").solo_view
			player_list.get_row((solo_view.shown_index + 1) % solo_view.get_player_count()).emit_signal("pressed")
			log_end_screen_player(tag + "_other", scene)
			end_step = 4
	elif end_step == 4 and end_wait >= 2.0:
		shot(tag + "_other")
		scene._lan_player_list.get_row(get_node("/root/LanNet").solo_view.player_index).emit_signal("pressed")
		log_end_screen_player(tag + "_own", scene)
		end_step = 1
	elif end_step == 1 and end_wait >= (2.5 if role != "host" else 5.5) and OS.get_environment("END_STAY") != "1":
		print("[TEST] ", tag, " exit")
		scene._on_ExitButton_pressed()
		end_step = 2
		end_wait = 0.0


func log_end_screen_player(tag: String, scene) -> void :
	var shown = RunData.players_data[0]
	var player_list = scene._lan_player_list
	var highlighted = []
	for player_index in player_list.rows:
		if not player_list.rows[player_index].flat:
			highlighted.append(player_index)
	print("[TEST] ", tag, " shown=", get_node("/root/LanNet").solo_view.shown_index, " highlighted=", highlighted, " rows=", player_list.rows.size(), " character=", shown.current_character.my_id, " weapons=", shown.weapons.size(), " items_shown=", scene._items_container._elements.get_child_count(), " max_hp=", Utils.get_stat(Keys.stat_max_hp_hash, 0), " focus_left=", scene._exit_button.focus_neighbour_left)


func log_saved_run(tag: String) -> void :
	print("[TEST] ", tag, " saved_run_state has_run_state=", ProgressData.saved_run_state.get("has_run_state", false), " wave=", ProgressData.saved_run_state.get("current_wave", "-"), " hash=", ProgressData.saved_run_state.hash())


var shop_step: = 0
var shop_wait: = 0.0


# Between waves, in the solo shop: buys an item, locks another, presses Go. The client presses
# Go, goes back to the shop and presses Go again; the host is done last.
func shop_actions(delta: float) -> void :
	var shop = get_tree().current_scene
	if shop == null or not shop is BaseShop:
		shop_step = 0
		shop_wait = 0.0
		return
	if int(OS.get_environment("IDLE_CHOICE")) >= 1:
		return
	shop_wait += delta
	var net = get_node("/root/LanNet")
	var overlay = shop.get_node_or_null("LanShopWaitingOverlay")
	var tag = role + "_shop"
	var delay = 7.0 if role == "host" else 1.0
	if shop_step == 0 and shop_wait >= delay and role != "host" and OS.get_environment("SHOP_QUIT") == "1":
		# Quit the run from the shop (like the pause menu's Quit): the host stops waiting.
		print("[TEST] ", tag, " quitting to the title screen")
		shop_step = 3
		var _e = get_tree().change_scene(MenuData.title_screen_scene)
		return
	if shop_step == 0 and shop_wait >= delay and role != "host" and OS.get_environment("SHOP_QUIT") == "2":
		# The connection breaks in the shop; the client rejoins and the host doesn't wait for it.
		shop_step = 3
		drop_connection(false)
		return
	if shop_step == 0 and shop_wait >= delay:
		var container = shop._get_shop_items_container(0)
		var own = RunData.players_data[0]
		var gold_before = own.gold
		var bought = "-"
		var locked = "-"
		if OS.get_environment("CURSE_TEST") == "1" and ProgressData.is_dlc_available("abyssal_terrors"):
			for item in container._shop_items:
				if item.active:
					item.set_shop_item(ItemService.get_dlc_data_by_id("abyssal_terrors").curse_item(item.item_data, 0))
		if OS.get_environment("FULL_SLOTS") != "":
			# Buying a weapon with every slot taken: vanilla merges it into one of the same kind.
			for item in container._shop_items:
				if item.active:
					item.set_shop_item(ItemService.get_element_safe(ItemService.weapons, "weapon_knife_1"))
					own.gold = max(own.gold, 100)
					gold_before = own.gold
					break
		for item in container._shop_items:
			if not item.active:
				continue
			if bought == "-":
				container.on_shop_item_buy_button_pressed(item)
				if own.gold < gold_before:
					bought = item.item_data.my_id
					continue
			if locked == "-" and not item.locked:
				# Not an item that is already locked: the real lock button would unlock it.
				item.change_lock_status(true)
				locked = item.item_data.my_id
		print("[TEST] ", tag, " count=", RunData.get_player_count(), " coop=", RunData.is_coop_run, " scene=", shop.filename, " bought=", bought, " gold=", gold_before, "->", own.gold, " locked=", locked, " locked_slot0=", RunData.locked_shop_items[0].size(), " items=", own.items.size(), " weapons=", own.weapons.size())
		shot(tag)
		if OS.get_environment("FULL_SLOTS") == "2":
			# Go a second after the buy, as a player would.
			shop_step = 4
			shop_wait = 0.0
			return
		shop._on_GoButton_pressed(0)
		print("[TEST] ", tag, " go overlay=", overlay.visible if overlay != null else "none", " done=", net.shop_done, " waiting=", net.shop_waiting_names)
		shop_step = 1
		shop_wait = 0.0
	elif shop_step == 4 and shop_wait >= 1.0:
		shop._on_GoButton_pressed(0)
		print("[TEST] ", tag, " go (late) overlay=", overlay.visible if overlay != null else "none", " done=", net.shop_done, " waiting=", net.shop_waiting_names)
		shop_step = 1
		shop_wait = 0.0
	elif shop_step == 1 and shop_wait >= 1.0:
		print("[TEST] ", tag, " waiting=", net.shop_waiting_names, " overlay_text='", overlay._names_label.text if overlay != null else "", "'")
		shot(tag + "_waiting")
		if role != "host":
			overlay._back_button.emit_signal("pressed")
			print("[TEST] ", tag, " back overlay=", overlay.visible, " done=", net.shop_done)
		shop_step = 2
		shop_wait = 0.0
	elif shop_step == 2 and shop_wait >= 1.5 and role != "host":
		shop._on_GoButton_pressed(0)
		print("[TEST] ", tag, " go_again overlay=", overlay.visible, " done=", net.shop_done)
		shop_step = 3


# WAVES=n: play n waves (with upgrades and shop after each) before the end steps.
func waves_target() -> int:
	return int(OS.get_environment("WAVES")) if OS.get_environment("WAVES") != "" else 1


# True 3 s into wave n; otherwise checks again in half a second.
func wait_for_wave(n: int) -> bool:
	var main = get_tree().current_scene
	# A live LanWaveSync: a client still in the last wave's upgrade screen has the new run's wave
	# number before its new wave scene loads.
	if main != null and main.filename == MenuData.game_scene and get_node("/root/LanNet").wave_sync != null and not main._cleaning_up and RunData.current_wave == n + max(first_wave, 1) - 1 and main._wave_timer.time_left > 0 and main._wave_timer.time_left < main._wave_timer.wait_time - 3.0:
		return true
	next_t = t + 0.5
	return false


# Every player's gear in RunData and in the scene, and the digest (both machines must match).
func log_run_check(tag: String) -> void :
	var RB = load("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
	var main = get_tree().current_scene
	var out = []
	for i in RunData.get_player_count():
		var pd = RunData.players_data[i]
		var weapons = []
		for w in pd.weapons:
			weapons.append(w.my_id)
		out.append("%d: gold=%d items=%d weapons=%s nodes=%d locked=%d dead=%s hp=%d/%d" % [i, pd.gold, pd.items.size(), weapons, main._players[i].current_weapons.size(), RunData.locked_shop_items[i].size(), main._players[i].dead, main._players[i].current_stats.health, main._players[i].max_stats.health])
	print("[TEST] ", tag, " wave=", RunData.current_wave, " zone=", RunData.current_zone, " coop=", RunData.is_coop_run, " count=", RunData.get_player_count(), " digest=", RB.digest())
	for line in out:
		print("[TEST] ", tag, "   ", line)
	# Cursed gear (DLC): which items are cursed and a hash of every item's effects and stats.
	for i in RunData.get_player_count():
		var pd = RunData.players_data[i]
		var cursed = []
		var gear = []
		for item in pd.items + pd.weapons + RunData.locked_shop_items[i]:
			var data = item[0] if item is Array else item
			var serialized = data.serialize()
			# The host counts this during the wave (it simulates every hit); clients get it at the wave end.
			serialized.erase("dmg_dealt_last_wave")
			gear.append(serialized)
			if data.is_cursed:
				cursed.append("%s(%.2f)" % [data.my_id, data.curse_factor])
		print("[TEST] ", tag, "   ", i, ": cursed=", cursed, " gear_md5=", to_json(gear).md5_text())
		var per_item = []
		for entry in gear:
			per_item.append("%s:%s" % [entry.my_id, to_json(entry).md5_text().substr(0, 6)])
			# GEAR_DUMP=id,id: those items' serialized data in full.
			if entry.my_id in OS.get_environment("GEAR_DUMP").split(","):
				print("[TEST] ", tag, "   ", i, ": dump ", to_json(entry))
		print("[TEST] ", tag, "   ", i, ": items ", per_item)
	shot(tag)


func next_round() -> bool:
	var rounds = int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 1
	if round_nr >= rounds:
		return false
	round_nr += 1
	run_states_logged = false
	print("[TEST] ", role, " round ", round_nr)
	return true


var ack_failed: = false


# FAIL_ACK=1: the next wave's run counts as different from the host's (as if the digest didn't
# match), once on each side: the host gets a failed ack, the client marks its run as not ok.
func fail_ack_test() -> void :
	if OS.get_environment("FAIL_ACK") != "1" or ack_failed:
		return
	var net = get_node("/root/LanNet")
	if not net.lobby_settings.get("in_wave", false) and not net.run_in_progress:
		return
	if net.is_host:
		for peer_id in net._run_acks:
			if net._run_acks[peer_id] and net._start_requested:
				net._run_acks[peer_id] = false
				ack_failed = true
				print("[TEST] host fail_ack peer=", peer_id)
	elif net._received_run_ok and net.lobby_settings.get("run_id", 0) != 0:
		net._received_run_ok = false
		ack_failed = true
		print("[TEST] client fail_ack run=", net._received_run_id)


func log_wave_end(tag: String) -> void :
	var net = get_node("/root/LanNet")
	var RB = load("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
	print("[TEST] ", tag, " wave_end_state=", net.wave_end_state, " acks=", net._wave_end_acks, " incoming=", not net._incoming_wave_end.empty())
	log_mode(tag)
	print("[TEST] ", tag, " digest=", RB.digest(), " summary=", to_json(RB.summarize()))


func log_run_states(tag: String) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene:
		print("[TEST] ", tag, " not in wave, scene=", scene_name())
		return
	print("[TEST] ", tag, " cleaning_up=", main._cleaning_up, " wave_failed=", main._is_wave_failed, " run_lost=", main._is_run_lost, " run_won=", main._is_run_won)
	print("[TEST] ", tag, " wave_timer time_left=", stepify(main._wave_timer.time_left, 0.01), " paused=", main._wave_timer.paused, " ticking=", not main._wave_timer.tick_timer.is_stopped())


func _client_step() -> void :
	var m = menus()
	var quits = OS.get_environment("CLIENT_QUITS") in ["1", "3", "4"]
	match step:
		0:
			next_t = 4.0
		1:
			m._main_menu.left_container.get_node("LanMultiplayerButton").emit_signal("pressed")
			var client_name = OS.get_environment("PLAYER_NAME") if OS.get_environment("PLAYER_NAME") != "" else "ClientPlayer"
			m.get_node("LanMultiplayerMenu")._name_edit.text = client_name
			m.get_node("LanMultiplayerMenu")._on_NameEdit_text_changed(client_name)
			m.get_node("LanMultiplayerMenu")._join_button.emit_signal("pressed")
			next_t = t + 1.5
		2:
			if OS.get_environment("JOIN_ADDR") != "":
				var join_menu = m.get_node("LanJoinMenu")
				join_menu._address_edit.text = OS.get_environment("JOIN_ADDR")
				join_menu._on_ConnectButton_pressed()
				print("[TEST] join by address ", OS.get_environment("JOIN_ADDR"), " at t=", stepify(t, 0.1))
				next_t = t + 2.5
				return
			# Over WiFi with power saving, broadcast beacons can take a few seconds to arrive.
			var row = m.get_node("LanJoinMenu")._first_row()
			if row == null and t < 10.0:
				step -= 1
				next_t = t + 0.25
				return
			print("[TEST] join first row at t=", stepify(t, 0.1), " found=", row != null)
			if row != null:
				row.emit_signal("pressed")
			next_t = t + 1.5
		3:
			if m == null or not m.get_node("LanLobby").visible:
				# Still connecting (a slow link or a busy host).
				if t < 60.0:
					step -= 1
					next_t = t + 0.5
					return
			pick_and_ready(m.get_node("LanLobby"), int(OS.get_environment("PICK")) if OS.get_environment("PICK") != "" else 1)
			var _e = get_tree().create_timer(1.0).connect("timeout", self, "client_settings_check", [m.get_node("LanLobby")])
			next_t = 14.0
		4:
			# 3.5 s into the wave (the host may start later than usual, e.g. with EXPECT).
			var wave = get_tree().current_scene
			if not get_node("/root/LanNet").active:
				# The host ended the session before a wave (e.g. the lobby role).
				print("[TEST] client: session over before a wave, quitting")
				get_tree().quit()
				return
			if wave == null or wave.filename != MenuData.game_scene or wave._wave_timer.wait_time - wave._wave_timer.time_left < 3.5:
				if t < 180.0:
					step -= 1
					next_t = t + 0.1
					waited_for_wave = true
					return
			if waited_for_wave:
				t = 14.0
			if first_wave == 0:
				first_wave = RunData.current_wave
			aim_test_setup()
			log_sync("client_w14")
			Input.action_press("button_move_right_0")
			next_t = 15.5
		5:
			Input.action_release("button_move_right_0")
			log_sync("client_w15")
			next_t = 16.0
		6:
			# Pause menu on the client: its player stands still, the wave goes on.
			var main = get_tree().current_scene
			# The local player's index, as main._check_for_pause passes it.
			var local_index = main.get_node("LanWaveSync")._local_index
			main._pause_menu.pause(local_index)
			start_pos = main._players[local_index].global_position
			Input.action_press("button_move_down_0")
			progress_test(main)
			meca_test(main)
			print("[TEST] client_pause open=", main._pause_menu.visible, " tree_paused=", get_tree().paused, " net_flag=", get_node("/root/LanNet").pause_menu_open, " time_left=", stepify(main._wave_timer.time_left, 0.1))
			next_t = 17.0
		7:
			# Set before the yields below: _process goes on as soon as this returns at the first one.
			next_t = 18.5
			var main = get_tree().current_scene
			var player = main._players[main.get_node("LanWaveSync")._local_index]
			print("[TEST] client_paused_moved=", player.global_position.distance_to(start_pos), " time_left=", stepify(main._wave_timer.time_left, 0.1))
			Input.action_release("button_move_down_0")
			# Close the menu with the mouse: move onto Resume (shows the cursor), then click it.
			var resume = main._pause_menu._main_menu._resume_button
			# Input events use window coordinates; the game renders at 1920x1080 and is stretched.
			var click_pos = get_tree().root.get_final_transform().xform(resume.get_global_rect().get_center())
			print("[TEST] resume_rect=", resume.get_global_rect(), " click_pos=", click_pos, " visible=", resume.is_visible_in_tree(), " disabled=", resume.disabled)
			var motion = InputEventMouseMotion.new()
			motion.position = click_pos
			motion.global_position = click_pos
			Input.parse_input_event(motion)
			yield(get_tree(), "idle_frame")
			print("[TEST] client_mouse_visible=", Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
			for pressed in [true, false]:
				var click = InputEventMouseButton.new()
				click.button_index = BUTTON_LEFT
				click.pressed = pressed
				click.position = click_pos
				click.global_position = click_pos
				Input.parse_input_event(click)
				yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			print("[TEST] client_unpaused_by_click open=", main._pause_menu.visible, " net_flag=", get_node("/root/LanNet").pause_menu_open)
		8:
			if OS.get_environment("CLIENT_QUITS") == "2":
				# The process ends mid-wave (crash, closed window): the host sees a disconnect.
				get_tree().quit()
				return
			if OS.get_environment("CLIENT_QUITS") in ["3", "4"]:
				# Back in the lobby by step 9 (the first attempt is 2 s later).
				drop_connection(OS.get_environment("CLIENT_QUITS") == "4")
			elif quits:
				# Quit the wave (like the pause menu's Quit): the host's copy of this player dies.
				var _e = get_tree().change_scene(MenuData.title_screen_scene)
			else:
				log_sync("client_w18")
			next_t = 21.0
		9:
			if quits:
				log_lobby("client_left_wave")
				# A different character from the lobby mid-run: the host ignores it.
				pick_and_ready(m.get_node("LanLobby"), 3)
			else:
				log_sync("client_w21")
				if OS.get_environment("TIMER_LAG") != "":
					# The client's wave timer a little behind the host's (within the resync
					# threshold), as network delay leaves it.
					var timer = get_tree().current_scene._wave_timer
					timer.start(timer.time_left + float(OS.get_environment("TIMER_LAG")))
			next_t = 23.6
		10:
			if waves_target() > 1 or OS.get_environment("IDLE_CHOICE") != "":
				if wait_for_wave(waves_target() + 1):
					log_run_check("client_next_wave")
				elif end_step == 3:
					# The run ended first (won at wave 20, or lost) and the end screen is done.
					print("[TEST] client run over before wave ", waves_target() + max(first_wave, 1), ", back in the lobby")
				else:
					step -= 1
					return
			else:
				if quits and OS.get_environment("KILL_ALL") == "1":
					# In the lobby while the run is lost: the hint says the run is over.
					var _e = get_tree().create_timer(4.0).connect("timeout", self, "log_lobby", ["client_run_over"])
				next_t = 55.0 if OS.get_environment("KILL_ALL") != "1" else 39.0
		11:
			log_lobby("client_end")
			log_wave_end("client_wave_end")
			if next_round():
				# Pick and ready again (step 3), then the in-wave steps (4) once the host's next
				# run is up.
				step = 2
				t = 10.0
				next_t = 10.5
				return
			get_tree().quit()


func _solo_step() -> void :
	match step:
		0:
			next_t = 2.0
		1:
			var RB = load("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
			var NetProtocol = load("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
			var entry = NetProtocol.new_player_entry(1, 0, "Solo")
			entry.character_id = "character_well_rounded"
			entry.weapon_ids = ["weapon_knife_1"]
			# Invulnerable, so the wave ends cleared ($SOLO_MORTAL=1 lets it die).
			DebugService.invulnerable = OS.get_environment("SOLO_MORTAL") != "1"
			DebugService.custom_wave_duration = 20
			# Vanilla solo pauses when the window loses focus (someone using the desktop meanwhile).
			ProgressData.settings.pause_on_focus_lost = false
			if OS.get_environment("START_WAVE") != "":
				DebugService.starting_wave = int(OS.get_environment("START_WAVE"))
			if OS.get_environment("ENEMY_MULT") != "":
				DebugService.nb_enemies_mult = float(OS.get_environment("ENEMY_MULT"))
			RB.build_run([entry], {"zone": 0, "difficulty": 0})
			RunData.set_coop_run(false)
			RunData.play_mode = RunData.PlayMode.SOLO
			if OS.get_environment("FULL_SLOTS") != "":
				var knife = ItemService.get_element_safe(ItemService.weapons, "weapon_knife_1")
				while RunData.players_data[0].weapons.size() < RunData.get_player_effect(Keys.weapon_slot_hash, 0):
					var _w = RunData.add_weapon(knife, 0)
				print("[TEST] full_slots weapons=", RunData.players_data[0].weapons.size())
			var _e = get_tree().change_scene(MenuData.game_scene)
			next_t = t + 3.0
		2:
			print("[TEST] solo in wave scene=", scene_name(), " players=", RunData.get_player_count(), " coop=", RunData.is_coop_run)
			shot("solo_wave")
			next_t = t + 24.0
		3:
			print("[TEST] solo after wave scene=", scene_name())
			shot("solo_after")
			get_tree().quit()


func _lobby_step() -> void :
	var m = menus()
	match step:
		0:
			next_t = 2.0
		1:
			m._main_menu.left_container.get_node("LanMultiplayerButton").emit_signal("pressed")
			m.get_node("LanMultiplayerMenu")._host_button.emit_signal("pressed")
			next_t = t + 0.5
		2:
			pick_and_ready(m.get_node("LanLobby"), 0)
			next_t = t + 1.5
		3:
			var lobby = m.get_node("LanLobby")
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			# Mage: has starting items whatever is unlocked (the 5th character changes with unlocks).
			for e in lobby._character_grid.get_children():
				if e.item != null and e.item.my_id == "character_mage":
					lobby._on_CharacterGrid_element_hovered(e)
			next_t = t + 0.5
		4:
			shot("lobby_character_hovered")
			var lobby = m.get_node("LanLobby")
			lobby._on_StartingItems_element_shown(lobby._starting_items.get_child(0))
			next_t = t + 0.5
		5:
			shot("lobby_starting_item_popup")
			var lobby = m.get_node("LanLobby")
			var vb = lobby._character_panel.get_node("MarginContainer/VBoxContainer")
			print("[TEST] lobby sizes holder=", lobby._character_panel.get_parent().rect_size, " panel=", lobby._character_panel.rect_size, " min=", lobby._character_panel.get_combined_minimum_size(), " items=", lobby._starting_items.get_combined_minimum_size(), " children=", vb.get_children().size())
			for c in vb.get_children():
				print("[TEST]   ", c.name, " ", c.rect_size, " min=", c.get_combined_minimum_size())
			for e in lobby._starting_items.get_children():
				print("[TEST]   item ", e.rect_size, " min=", e.rect_min_size, " flags=", e.size_flags_horizontal, "/", e.size_flags_vertical)
			for e in lobby._character_grid.get_children().slice(0, 1):
				print("[TEST]   character element ", e.rect_size, " min=", e.rect_min_size)
			print("[TEST] lobby bottoms ready=", lobby._ready_button.get_global_rect().end.y, " start=", lobby._start_button.get_global_rect().end.y, " character=", lobby._character_panel.get_global_rect().end.y, " weapon=", lobby._item_panel.get_global_rect().end.y, "/", lobby._item_panel.get_parent().get_global_rect().end.y)
			lobby._on_StartingItems_element_unhovered(lobby._starting_items.get_child(0))
			lobby._hovered_character = null
			lobby._on_WeaponGrid_element_hovered(first_element(lobby._weapon_grid, 2))
			next_t = t + 0.5
		6:
			shot("lobby_weapon_hovered")
			var lobby = m.get_node("LanLobby")
			lobby._hovered_weapon = null
			lobby._update_previews()
			next_t = t + 0.5
		7:
			shot("lobby_nothing_hovered")
			# Keyboard: focus a character, then its first starting item; the preview keeps it.
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			var lobby = m.get_node("LanLobby")
			for e in lobby._character_grid.get_children():
				if e.item != null and e.item.my_id == "character_mage":
					e.grab_focus()
			next_t = t + 0.5
		8:
			var lobby = m.get_node("LanLobby")
			print("[TEST] lobby focused character=", lobby._focused_character.item.my_id, " items=", lobby._starting_items.get_child_count())
			lobby._starting_items.get_child(0).grab_focus()
			next_t = t + 0.5
		9:
			var lobby = m.get_node("LanLobby")
			print("[TEST] lobby after item focus: character=", lobby._focused_character.item.my_id if lobby._focused_character != null else "-", " preview=", lobby._starting_items_character.my_id if lobby._starting_items_character != null else "-", " popup=", lobby._starting_item_popup.visible)
			shot("lobby_starting_item_focused")
			lobby._ready_button.grab_focus()
			next_t = t + 0.5
		10:
			var lobby = m.get_node("LanLobby")
			print("[TEST] lobby after ready focus: character=", lobby._focused_character, " preview=", lobby._starting_items_character.my_id if lobby._starting_items_character != null else "-", " popup=", lobby._starting_item_popup.visible)
			# MODE=id: that mode (not remembered) and $FAKES fake players, e.g. teams in the list
			# and the mode's settings rows.
			if OS.get_environment("MODE") != "":
				var net = get_node("/root/LanNet")
				net.lobby_settings.mode = OS.get_environment("MODE")
				add_fake_players(net, int(OS.get_environment("FAKES")) if OS.get_environment("FAKES") != "" else 0)
				net._broadcast_lobby_state()
				# Teams: a click on the other team's header joins it (no headers without teams).
				var lobby_node = m.get_node("LanLobby")
				if lobby_node._team_headers.size() == 2:
					var before = net.get_local_player().get("team", 0)
					lobby_node._team_headers[1 - before].emit_signal("pressed")
					print("[TEST] lobby_team_header before=", before, " after=", net.get_local_player().get("team", 0))
			# Settings page: open, change the choice time, close with ui_cancel.
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			lobby._settings_button.emit_signal("pressed")
			next_t = t + 0.5
		11:
			var page = m.get_node("LanLobby")._settings_page
			print("[TEST] lobby_settings_page visible=", page.visible, " focus=", get_viewport().gui_get_focus_owner().get_path(), " disabled=", page._zone_option.disabled, " zone_left=", page._zone_option.focus_neighbour_left, " back_down=", page._back_button.focus_neighbour_bottom)
			shot("lobby_settings_page")
			# A mode that fixes the loot settings, then co-op with the page open: the loot rows get
			# their options back (MODE=team_race).
			if OS.get_environment("MODE") != "":
				var loot = page._share_materials_option
				var before_items = loot.get_item_count()
				page._on_option_item_selected(0, page._mode_option, "mode")
				print("[TEST] lobby_settings_loot mode=", get_node("/root/LanNet").lobby_settings.mode, " items_before=", before_items, " items_after=", loot.get_item_count(), " disabled=", loot.disabled, " text=", loot.text)
				var mode_index = page._get_mode_index(OS.get_environment("MODE"))
				page._on_option_item_selected(mode_index, page._mode_option, "mode")
			var index = page._choice_time_option.get_item_index(60)
			page._choice_time_option.select(index)
			page._on_option_item_selected(index, page._choice_time_option, "choice_time")
			index = page._scaling_option.get_item_index(2)
			page._scaling_option.select(index)
			page._on_option_item_selected(index, page._scaling_option, "scaling_preset")
			# The help box explains the focused row: the scaling's percentages.
			page._scaling_option.grab_focus()
			next_t = t + 0.5
		12:
			var lobby = m.get_node("LanLobby")
			var net = get_node("/root/LanNet")
			print("[TEST] lobby_settings_changed choice_time=", net.lobby_settings.choice_time, " saved=", net.config.last_choice_time, " preset=", net.lobby_settings.scaling_preset, " saved=", net.config.last_scaling_preset, " scaling=", net.lobby_settings.scaling, " config_scaling=", net.config.scaling, " info='", lobby._settings_page._help_label.text, "' summary='", lobby._settings_label.text, "'")
			shot("lobby_settings_tough")
			for pressed in [true, false]:
				var event = InputEventAction.new()
				event.action = "ui_cancel"
				event.pressed = pressed
				Input.parse_input_event(event)
			next_t = t + 0.5
		13:
			var lobby = m.get_node("LanLobby")
			print("[TEST] lobby_settings_closed page=", lobby._settings_page.visible, " lobby=", lobby.visible, " session=", get_node("/root/LanNet").active, " focus=", get_viewport().gui_get_focus_owner().get_path())
			shot("lobby_settings_summary")
			# The shared test config keeps the default for later runs.
			get_node("/root/LanNet").set_lobby_settings({"choice_time": 90, "scaling_preset": 1})
			print("[TEST] lobby_settings_restored scaling=", get_node("/root/LanNet").lobby_settings.scaling)
			get_tree().quit()
