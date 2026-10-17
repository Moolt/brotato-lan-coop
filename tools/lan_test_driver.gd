extends Node

# Test-only driver (not part of the mod, not in the release zip). tools/make_test_copy.sh links it
# into a throwaway game copy as the LanTestDriver autoload. Role = argument after "--":
#   host: hosts, picks and readies, adds 10 fake lobby players, starts a 40 s 12-player wave with
#         $ENEMY_MULT (default 6) times the enemies and invulnerable players, logs arena size,
#         enemy scaling, enemy counts and FPS, kills the host player to check the spectator
#         camera, waits for the wave end, leaves
#   join: joins the first discovered game, picks and readies, logs the lobby hints
#   solo: builds a 1-player run without a session and plays a vanilla wave
#   quit: quits once the title screen is up (cheap check for parse errors)
#   (none): idle, for manual tests
# The step scripts follow the latest feature under test; edit them for the next one.
# Lines start with [TEST]; screenshots go to $SHOT_DIR.
var role: = ""
var t: = 0.0
var step: = 0
var next_t: = 0.0
var start_pos = null
var started: = false


func _ready() -> void :
	pause_mode = PAUSE_MODE_PROCESS
	for a in OS.get_cmdline_args():
		if a in ["host", "join", "quit", "solo"]:
			role = a
	print("[TEST] role=", role)


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


func log_lobby(tag: String) -> void :
	shot(tag)
	var net = get_node("/root/LanNet")
	var m = menus()
	if m == null:
		print("[TEST] ", tag, " scene=", scene_name(), " run_in_progress=", net.run_in_progress, " settings=", net.lobby_settings)
		return
	var lobby = m.get_node("LanLobby")
	print("[TEST] ", tag, " page=", m._current_page.name, " run_in_progress=", net.run_in_progress, " settings=", net.lobby_settings, " players=", net.players.size(), " coop_players=", CoopService.connected_players)
	print("[TEST] ", tag, " hint='", tr(lobby._hint_label.text), "' start_disabled=", lobby._start_button.disabled)


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


func pick_and_ready(lobby, nth: = 0) -> void :
	lobby._on_CharacterGrid_element_pressed(first_element(lobby._character_grid, nth))
	yield(get_tree().create_timer(0.3), "timeout")
	lobby._on_WeaponGrid_element_pressed(first_element(lobby._weapon_grid))
	yield(get_tree().create_timer(0.3), "timeout")
	lobby._on_ReadyButton_pressed()


func _process(delta: float) -> void :
	if role == "":
		return
	if not started:
		started = menus() != null
		return
	t += delta
	if t < next_t:
		return
	if role == "quit" or get_node_or_null("/root/LanNet") == null:
		get_tree().quit()
		return
	if role == "solo":
		_solo_step()
	elif role == "host":
		_host_step()
	else:
		_client_step()
	step += 1


func add_fake_players(net, count: int) -> void :
	var LobbyRules = load("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
	var NetProtocol = load("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
	var characters = LobbyRules.get_unlocked_characters()
	for i in count:
		var index = net.players.size()
		var entry = NetProtocol.new_player_entry(1000 + index, index, "Fake%d" % index)
		var character = characters[(index * 7) % characters.size()]
		entry.character_id = character.my_id
		var choices = LobbyRules.get_starting_choices(character)
		if not choices.empty():
			entry.weapon_id = choices[0].my_id
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
	print("[TEST] ", tag, " coop enemies=", CoopService.additional_enemies_per_coop_player, " hp=", CoopService.additional_enemy_health_per_coop_player, " dmg=", CoopService.additional_enemy_damage_per_coop_player, " hp100=", EntityService.get_final_enemy_health(100), " dmg100=", EntityService.get_final_enemy_damage(100.0), " max_enemies=", main._entity_spawner._current_wave_data.max_enemies)


func log_camera(tag: String) -> void :
	var main = get_tree().current_scene
	var cam = main._camera
	print("[TEST] ", tag, " camera targets=", cam.targets.size(), " snapped=", cam._is_snapped, " dynamic=", cam.dynamic_camera_enabled, " zoom=", cam.zoom, " pos=", cam.global_position.round(), " p0=", main._players[0].global_position.round())


func log_enemies(tag: String) -> void :
	var main = get_tree().current_scene
	var spawner = main._entity_spawner
	print("[TEST] ", tag, " enemies=", spawner.enemies.size(), " queued=", spawner.queue_to_spawn.size(), " removed_for_perf=", spawner.enemies_removed_for_perf, " fps=", Engine.get_frames_per_second(), " time_left=", main._wave_timer.time_left)


func _host_step() -> void :
	var net = get_node("/root/LanNet")
	var m = menus()
	match step:
		0:
			next_t = 3.0
		1:
			m._main_menu.left_container.get_node("LanMultiplayerButton").emit_signal("pressed")
			m.get_node("LanMultiplayerMenu")._name_edit.text = "HostPlayer"
			m.get_node("LanMultiplayerMenu")._on_NameEdit_text_changed("HostPlayer")
			m.get_node("LanMultiplayerMenu")._host_button.emit_signal("pressed")
			next_t = t + 0.5
		2:
			pick_and_ready(m.get_node("LanLobby"), 0)
			next_t = 9.0
		3:
			add_fake_players(net, 10)
			next_t = t + 1.0
		4:
			log_lobby("host_before_start")
			# Stress test: many enemies, and nobody dies from them.
			DebugService.nb_enemies_mult = float(OS.get_environment("ENEMY_MULT")) if OS.get_environment("ENEMY_MULT") != "" else 6.0
			DebugService.invulnerable = true
			DebugService.custom_wave_duration = 40
			m.get_node("LanLobby")._start_button.emit_signal("pressed")
			next_t = t + 3.0
		5:
			log_scaling("host_in_wave")
			log_camera("host_in_wave")
			log_hud("host_in_wave")
			shot("host_in_wave")
			next_t = t + 8.0
		6:
			log_enemies("host_t11")
			log_camera("host_t11")
			shot("host_t11")
			next_t = t + 8.0
		7:
			log_enemies("host_t19")
			get_tree().current_scene._players[0].die()
			next_t = t + 4.0
		8:
			log_camera("host_spectate")
			log_enemies("host_t23")
			shot("host_spectate")
			next_t = t + 8.0
		9:
			log_enemies("host_t31")
			log_camera("host_t31")
			shot("host_t31")
			next_t = t + 14.0
		10:
			log_lobby("host_after_wave_end")
			next_t = t + 2.0
		11:
			net.leave()
			get_tree().quit()


func _client_step() -> void :
	var m = menus()
	match step:
		0:
			next_t = 4.0
		1:
			m._main_menu.left_container.get_node("LanMultiplayerButton").emit_signal("pressed")
			m.get_node("LanMultiplayerMenu")._name_edit.text = "ClientPlayer"
			m.get_node("LanMultiplayerMenu")._on_NameEdit_text_changed("ClientPlayer")
			m.get_node("LanMultiplayerMenu")._join_button.emit_signal("pressed")
			next_t = t + 1.5
		2:
			m.get_node("LanJoinMenu")._first_row().emit_signal("pressed")
			next_t = t + 1.5
		3:
			pick_and_ready(m.get_node("LanLobby"), 1)
			next_t = 11.0
		4:
			log_lobby("client_lobby_12")
			next_t = 16.0
		5:
			log_lobby("client_host_in_wave")
			next_t = 62.0
		6:
			log_lobby("client_end")
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
			entry.weapon_id = "weapon_knife_1"
			RB.build_run([entry], {"zone": 0, "difficulty": 0})
			RunData.set_coop_run(false)
			RunData.play_mode = RunData.PlayMode.SOLO
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
