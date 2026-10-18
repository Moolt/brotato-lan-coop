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
#         CLIENT_QUITS=1) quits the wave, (with CLIENT_QUITS=2) closes the game, or stays and
#         logs the host's run verdict, follows the host back to the lobby and logs the
#         wave-end state it received
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
var run_states_logged: = false


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
		if started and get_node_or_null("/root/LanNet") != null:
			var _e = get_node("/root/LanNet").connect("wave_end_ready", self, "solo_view_test")
		return
	t += delta
	# The wave's verdict, once, as soon as its cleanup starts (the scene changes soon after).
	var scene = get_tree().current_scene
	if not run_states_logged and scene != null and scene.filename == MenuData.game_scene and scene._cleaning_up:
		run_states_logged = true
		log_run_states(role + "_cleanup")
	pick_upgrades(delta)
	shop_actions(delta)
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
		if i == 0:
			# Engineer: starts with a turret, so structures get tested.
			for c in characters:
				if c.my_id == "character_engineer":
					character = c
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


func center_offset(i: int) -> Vector2:
	return ZoneService.get_map_center() + Vector2(450, 0).rotated(i * PI / 2)


func visible_children(node) -> int:
	var n = 0
	if is_instance_valid(node):
		for c in node.get_children():
			if c.visible and c.get("velocity") != null and c.velocity != Vector2.ZERO:
				n += 1
	return n


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
	print("[TEST] ", tag, " time_left=", stepify(main._wave_timer.time_left, 0.1), " players=", out, " cam_targets=", cam.targets.size(), " sync=", main.get_node_or_null("LanWaveSync") != null)
	var spawner = main._entity_spawner
	var boss_hp = []
	for boss in spawner.bosses:
		boss_hp.append("%d/%d bar=%s" % [boss.current_stats.health, boss.max_stats.health, boss.life_bar.visible])
	print("[TEST] ", tag, " enemies=", spawner.enemies.size(), " bosses=", spawner.bosses.size(), " boss_hp=", boss_hp, " neutrals=", spawner.neutrals.size(), " structures=", spawner.structures.size(), " pets=", spawner.pets.size(), " births=", spawner.active_births, " gold=", main._active_golds.size(), " consumables=", main._consumables.size(), " p0_upgrade_icons=", main._things_to_process_player_containers[0].upgrades.get_child_count(), " p0_crate_icons=", main._things_to_process_player_containers[0].consumables.get_child_count())
	var sync = main.get_node_or_null("LanWaveSync")
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
		print("[TEST] ", tag, " net_entities=", ids.size(), " fps=", Engine.get_frames_per_second(), " snapshot_bytes~", 15 + 23 * main._players.size() + 7 * ids.size(), " sample=", sample)
	shot(tag)


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
			add_fake_players(net, int(OS.get_environment("FAKES")) if OS.get_environment("FAKES") != "" else 1)
			next_t = 10.0
		4:
			log_lobby("host_before_start")
			DebugService.invulnerable = true
			DebugService.custom_wave_duration = 20
			if OS.get_environment("ENEMY_MULT") != "":
				DebugService.nb_enemies_mult = float(OS.get_environment("ENEMY_MULT"))
			m.get_node("LanLobby")._start_button.emit_signal("pressed")
			next_t = 13.0
		5:
			log_sync("host_w13")
			Input.action_press("button_move_left_7")
			# A boss and three trees, which wave 1 doesn't have.
			var spawner = get_tree().current_scene._entity_spawner
			var rect = ZoneService.get_current_zone_rect()
			spawner.queue_to_spawn_bosses.push_back([EntityType.BOSS, load("res://entities/units/enemies/rhino/rhino.tscn"), rect.end - Vector2(150, 150)])
			for i in 3:
				spawner.queue_to_spawn_trees.push_back([EntityType.NEUTRAL, load("res://entities/units/neutral/tree.tscn"), Vector2(150 + i * 120, rect.end.y - 150)])
			# An enemy spawning right on the host player: vanilla moves its marker elsewhere.
			spawner.queue_to_spawn.push_back([EntityType.ENEMY, load("res://entities/units/enemies/spitter/spitter.tscn"), get_tree().current_scene._players[0].global_position])
			# Spitters shoot enemy projectiles.
			for i in 4:
				spawner.queue_to_spawn.push_back([EntityType.ENEMY, load("res://entities/units/enemies/spitter/spitter.tscn"), center_offset(i)])
			next_t = 14.0
		6:
			Input.action_release("button_move_left_7")
			log_sync("host_w14")
			next_t = 16.0
		7:
			var main7 = get_tree().current_scene
			# A level-up for the host player and the client's, and three crates right next to the
			# host (vanilla hands each to a player with the fewest, so everyone gets one).
			RunData.add_xp(30, 0)
			RunData.add_xp(30, 1)
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
			var _explosion = WeaponService.explode(load("res://items/all/landmines/landmine_exploding_effect.tres"), explode_args)
			# The injected boss has 1 HP in wave 1.
			for boss in get_tree().current_scene._entity_spawner.bosses:
				boss.max_stats.health = 5000
				boss.current_stats.health = 5000
				boss.emit_signal("health_updated", boss, 5000, 5000)
			log_sync("host_w16")
			next_t = 18.0
		8:
			var main = get_tree().current_scene
			main._players[2].die()
			var spawner = main._entity_spawner
			if not spawner.neutrals.empty():
				spawner.neutrals[0].die()
			for boss in spawner.bosses:
				boss.current_stats.health = 2500
				boss.emit_signal("health_updated", boss, boss.current_stats.health, boss.max_stats.health)
			next_t = 20.0
		9:
			log_sync("host_w20")
			# Pause menu on the host: the wave keeps running everywhere.
			get_tree().current_scene._pause_menu.pause(0)
			print("[TEST] host_pause open=", get_tree().current_scene._pause_menu.visible, " tree_paused=", get_tree().paused)
			next_t = 23.0
		10:
			log_sync("host_w23")
			var main = get_tree().current_scene
			main._pause_menu.unpause()
			if OS.get_environment("KILL_ALL") == "1":
				# Everyone dies: the run is lost.
				for p in main._players:
					if not p.dead:
						p.die()
			next_t = 24.0
		11:
			next_t = 55.0 if OS.get_environment("KILL_ALL") != "1" else 30.0
		12:
			log_lobby("host_after_wave_end")
			log_wave_end("host_wave_end")
			next_t = t + 2.0
		13:
			net.leave()
			get_tree().quit()


# Right after the wave-end state (the host's scene changes next): enter and leave the solo view,
# check the solo invariants in between and that the run is unchanged afterwards.
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


# Between waves: in the solo upgrades UI, picks the first upgrade or takes the crate's item.
func pick_upgrades(delta: float) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene or not main._upgrades_ui.visible:
		return
	pick_wait += delta
	if pick_wait < 1.0:
		return
	pick_wait = 0.0
	var container = main._upgrades_ui._player_container1
	var own = RunData.players_data[0]
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
	if shop_step == 0 and shop_wait >= delay:
		var container = shop._get_shop_items_container(0)
		var own = RunData.players_data[0]
		var gold_before = own.gold
		var bought = "-"
		var locked = "-"
		for item in container._shop_items:
			if not item.active:
				continue
			if bought == "-":
				container.on_shop_item_buy_button_pressed(item)
				if own.gold < gold_before:
					bought = item.item_data.my_id
					continue
			if locked == "-":
				item.change_lock_status(true)
				locked = item.item_data.my_id
		print("[TEST] ", tag, " count=", RunData.get_player_count(), " coop=", RunData.is_coop_run, " scene=", shop.filename, " bought=", bought, " gold=", gold_before, "->", own.gold, " locked=", locked, " locked_slot0=", RunData.locked_shop_items[0].size(), " items=", own.items.size(), " weapons=", own.weapons.size())
		shot(tag)
		shop._on_GoButton_pressed(0)
		print("[TEST] ", tag, " go overlay=", overlay.visible if overlay != null else "none", " done=", net.shop_done, " waiting=", net.shop_waiting_names)
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


func log_wave_end(tag: String) -> void :
	var net = get_node("/root/LanNet")
	var RB = load("res://mods-unpacked/Moolt-Lan_Coop/net/run_builder.gd")
	print("[TEST] ", tag, " wave_end_state=", net.wave_end_state, " acks=", net._wave_end_acks, " incoming=", not net._incoming_wave_end.empty())
	print("[TEST] ", tag, " digest=", RB.digest(), " summary=", to_json(RB.summarize()))


func log_run_states(tag: String) -> void :
	var main = get_tree().current_scene
	if main == null or main.filename != MenuData.game_scene:
		print("[TEST] ", tag, " not in wave, scene=", scene_name())
		return
	print("[TEST] ", tag, " cleaning_up=", main._cleaning_up, " wave_failed=", main._is_wave_failed, " run_lost=", main._is_run_lost, " run_won=", main._is_run_won)


func _client_step() -> void :
	var m = menus()
	var quits = OS.get_environment("CLIENT_QUITS") == "1"
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
			next_t = 14.0
		4:
			log_sync("client_w14")
			Input.action_press("button_move_right_7")
			next_t = 15.5
		5:
			Input.action_release("button_move_right_7")
			log_sync("client_w15")
			next_t = 16.0
		6:
			# Pause menu on the client: its player stands still, the wave goes on.
			var main = get_tree().current_scene
			# The local player's index, as main._check_for_pause passes it.
			var local_index = main.get_node("LanWaveSync")._local_index
			main._pause_menu.pause(local_index)
			start_pos = main._players[local_index].global_position
			Input.action_press("button_move_down_7")
			print("[TEST] client_pause open=", main._pause_menu.visible, " tree_paused=", get_tree().paused, " net_flag=", get_node("/root/LanNet").pause_menu_open, " time_left=", stepify(main._wave_timer.time_left, 0.1))
			next_t = 17.0
		7:
			var main = get_tree().current_scene
			var player = main._players[main.get_node("LanWaveSync")._local_index]
			print("[TEST] client_paused_moved=", player.global_position.distance_to(start_pos), " time_left=", stepify(main._wave_timer.time_left, 0.1))
			Input.action_release("button_move_down_7")
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
			next_t = 18.5
		8:
			if OS.get_environment("CLIENT_QUITS") == "2":
				# The process ends mid-wave (crash, closed window): the host sees a disconnect.
				get_tree().quit()
				return
			if quits:
				# Quit the wave (like the pause menu's Quit): the host's copy of this player dies.
				var _e = get_tree().change_scene(MenuData.title_screen_scene)
			else:
				log_sync("client_w18")
			next_t = 21.0
		9:
			if quits:
				log_lobby("client_left_wave")
			else:
				log_sync("client_w21")
			next_t = 23.6
		10:
			next_t = 55.0 if OS.get_environment("KILL_ALL") != "1" else 29.0
		11:
			log_lobby("client_end")
			log_wave_end("client_wave_end")
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
			# Invulnerable, so the wave ends cleared ($SOLO_MORTAL=1 lets it die).
			DebugService.invulnerable = OS.get_environment("SOLO_MORTAL") != "1"
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
