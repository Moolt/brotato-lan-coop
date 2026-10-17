extends "res://main.gd"

# LAN session changes to the wave scene.
# - Per-player arrays grow to 12 slots (see LanGame). on_gold_picked_up splits gold over a local
#   4-slot array, so it has a copy for more than 4 players.
# - main.tscn has HUD nodes for P1-P4 only. In a session, _enter_tree copies the P4 sets as
#   P5-P12 before vanilla's _ready looks them up by unique name. Only the local player's screen
#   HUD is shown (P1 slot).
# - Other players get their name over their head, in their colour, above the vanilla over-head
#   health bar, which stays visible for them even at full HP. Dead players' names turn grey.
# - The coop UpgradesUI has 4 player containers and fails in _ready with more players. It is
#   never shown in a session (see _on_EndWaveTimer_timeout), so it is marked non-coop, which
#   makes its _ready return early.
# - Enemy scaling follows the session's knobs (LanGame.apply_enemy_scaling, set before vanilla's
#   _ready spawns anything). The arena grows in the ZoneService extension.
# - Every machine has its own screen, so the camera follows the local player like in solo play,
#   and the lock_coop_camera option is ignored. Once the local player dies, the camera follows
#   the players still alive.
# - Remote players have device -1 (see LanNet._fill_coop_players), so the pause check skips them.
# - Temporary until Step 7: the end of a wave goes back to the title screen (and its lobby)
#   instead of the coop upgrade UI and shop, which only have 4 slots.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const NAME_FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")

const VANILLA_HUD_SLOTS: = 4
const NAME_LABEL_NAME: = "LanNameLabel"
const NAME_FONT_SIZE: = 22
const NAME_OUTLINE_SIZE: = 2
const NAME_DEAD_COLOR: = Color(0.55, 0.55, 0.55)
# Box of the name label, relative to the over-head bar container. The bar itself spans
# (-32, -72) to (32, -56) in main.tscn; the name sits right above it.
const NAME_RECT: = Rect2(-150, -106, 300, 32)
# Unique node name of each P4 node set and the suffix that holds the player number.
const HUD_TEMPLATES: = [
	["LifeContainerP4", "P4", "P"],
	["PlayerLifeBarContainerP4", "P4", "P"],
	["UIThingsToProcessPlayerContainer4", "4", ""],
]


func _init() -> void :
	LanGame.grow(_upgrades_to_process, [])
	LanGame.grow(_consumables_to_process, [])
	LanGame.grow(_proj_on_death_stat_caches, null)
	LanGame.grow(_player_is_under_half_health, false)


func _enter_tree() -> void :
	if not LanGame.in_session() or get_node_or_null("%LifeContainerP5") != null:
		return
	LanGame.apply_enemy_scaling(RunData.get_player_count())
	if RunData.get_player_count() > VANILLA_HUD_SLOTS:
		$UI / CoopUpgradesUI.is_coop_ui = false
	for template in HUD_TEMPLATES:
		var original: Node = get_node("%" + template[0])
		for player_index in range(VANILLA_HUD_SLOTS, LanGame.MAX_PLAYERS):
			_add_hud_copy(original, template[1], template[2] + str(player_index + 1))


# Copies a HUD node set with the player number in its names. Names are changed before the owner
# is set, because setting the owner claims the unique names.
func _add_hud_copy(original: Node, old_suffix: String, new_suffix: String) -> void :
	var copy: Node = original.duplicate()
	copy.name = _lan_hud_name(original.name, old_suffix, new_suffix)

	# Which copied nodes belong to main.tscn (and may have unique names), by path in the original.
	var owned: = []
	for node in _lan_subtree(copy):
		var source: Node = original.get_node_or_null(copy.get_path_to(node))
		if source != null and source.owner == self:
			owned.append([node, source.unique_name_in_owner])

	original.get_parent().add_child(copy)
	for pair in owned:
		var node: Node = pair[0]
		node.name = _lan_hud_name(node.name, old_suffix, new_suffix)
		node.owner = self
		node.unique_name_in_owner = pair[1]


func _lan_hud_name(node_name: String, old_suffix: String, new_suffix: String) -> String:
	if node_name.ends_with(old_suffix):
		return node_name.left(node_name.length() - old_suffix.length()) + new_suffix
	return node_name


func _lan_subtree(node: Node) -> Array:
	var result: = [node]
	for child in node.get_children():
		result.append_array(_lan_subtree(child))
	return result


func _on_EntitySpawner_players_spawned(players: Array) -> void :
	._on_EntitySpawner_players_spawned(players)
	if not LanGame.in_session():
		return
	for i in range(1, _players_ui.size()):
		_players_ui[i].hud_container.hide()
		_things_to_process_player_containers[i].hide()

	var local_player_index: int = LanGame.get_lan_net().local_player_index
	if local_player_index >= 0 and local_player_index < players.size():
		_camera.targets = [players[local_player_index]]
		_camera._is_snapped = true

	var font: DynamicFont = NAME_FONT.duplicate()
	font.size = NAME_FONT_SIZE
	font.outline_size = NAME_OUTLINE_SIZE
	for i in _players_ui.size():
		if not _lan_is_local_player(i):
			_lan_add_name_label(_players_ui[i].player_life_bar_container, i, font)


func _lan_add_name_label(container: Node, player_index: int, font: DynamicFont) -> void :
	var label: = Label.new()
	label.name = NAME_LABEL_NAME
	label.set_message_translation(false)
	label.text = LanGame.get_player_name(player_index)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_BOTTOM
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.rect_position = NAME_RECT.position
	label.rect_size = NAME_RECT.size
	label.add_font_override("font", font)
	label.add_color_override("font_color", CoopService.get_player_color(player_index))
	container.add_child(label)


func _lan_is_local_player(player_index: int) -> bool:
	return player_index == LanGame.get_lan_net().local_player_index


# Other players' over-head bars stay visible at full HP (vanilla: only below max, if the
# hp_bar_on_character option is on). The local player's bar follows the option.
func _on_player_health_updated(player: Player, current_val: int, max_val: int) -> void :
	._on_player_health_updated(player, current_val, max_val)
	if not LanGame.in_session() or player.dead or _lan_is_local_player(player.player_index):
		return
	var player_life_bar = _players_ui[player.player_index].player_life_bar
	player_life_bar.show()
	player_life_bar.update_value(current_val, max_val)


func _on_player_died(p_player: Player, _args: Entity.DieArgs) -> void :
	._on_player_died(p_player, _args)
	var label = _players_ui[p_player.player_index].player_life_bar_container.get_node_or_null(NAME_LABEL_NAME)
	if label != null:
		label.add_color_override("font_color", NAME_DEAD_COLOR)
	if LanGame.in_session() and _lan_is_local_player(p_player.player_index):
		_lan_spectate()


# The camera follows the living players with vanilla's coop camera: it moves smoothly, zooms
# out to fit them, and snaps to the last one standing.
func _lan_spectate() -> void :
	_camera.targets = _players
	_camera._is_snapped = false
	_camera._snap_progress = 0.0


func on_lock_coop_camera_changed(value: int) -> void :
	if LanGame.in_session():
		_camera.dynamic_camera_enabled = true
		return
	.on_lock_coop_camera_changed(value)


func on_gold_picked_up(gold: Node, player_index: int) -> void :
	if RunData.get_player_count() <= VANILLA_HUD_SLOTS:
		.on_gold_picked_up(gold, player_index)
		return

	# Copy of vanilla's on_gold_picked_up with player_gold/player_xp sized for every player.
	if gold.already_picked_up:
		return

	gold.already_picked_up = true
	_active_golds.erase(gold)
	add_node_to_pool(gold, _gold_pool_id)

	if player_index >= 0:
		if ProgressData.settings.alt_gold_sounds:
			SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), - 5, 0.2)
		else:
			SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)

		var increase_effect: int = RunData.get_player_effect(Keys.increase_material_value_hash, player_index)
		var value = gold.value
		value += value * (increase_effect / 100.0)

		var boost = RunData.apply_common_gold_pickup_effects(gold.value, player_index)
		value *= boost
		gold.boosted *= boost

		if Utils.get_chance_success(RunData.get_player_effect(Keys.heal_when_pickup_gold_hash, player_index) / 100.0):
			RunData.emit_signal("healing_effect", 1, player_index, Keys.item_cute_monkey_hash)

		var dmg_when_pickup_gold_effect = RunData.get_player_effect(Keys.dmg_when_pickup_gold_hash, player_index)
		if dmg_when_pickup_gold_effect.size() > 0:
			handle_stat_damages(dmg_when_pickup_gold_effect, player_index)

		var highest_cd_weapon_that_should_reload = null

		for weapon in _players[player_index].current_weapons:
			for effect in weapon.effects:
				if effect.key_hash == Keys.reload_when_pickup_gold_hash:
					if not weapon._is_shooting and (highest_cd_weapon_that_should_reload == null or weapon._current_cooldown > highest_cd_weapon_that_should_reload._current_cooldown):
						highest_cd_weapon_that_should_reload = weapon

		if highest_cd_weapon_that_should_reload:
			highest_cd_weapon_that_should_reload._current_cooldown = 0

		for structure in _entity_spawner.structures:
			if structure is BuilderTurret:
				for effect in structure.effects:
					if effect.key_hash == Keys.reload_when_pickup_gold_hash:
						structure._cooldown = 0

		if RunData.get_player_effect_bool(Keys.reload_when_pickup_gold_hash, player_index):
			for weapon in _players[player_index].current_weapons:
				weapon._current_cooldown = 0

		var player_gold: = []
		var player_xp: = []
		player_gold.resize(RunData.get_player_count())
		player_xp.resize(RunData.get_player_count())
		for i in RunData.get_player_count():
			player_gold[i] = 0
			player_xp[i] = 0
		while value > 0:
			player_gold[_next_gold_player] += 1
			player_xp[_next_gold_player] += 1
			value -= 1
			_next_gold_player = (_next_gold_player + 1) % RunData.get_player_count()

		for i in RunData.get_player_count():
			RunData.add_gold(player_gold[i], i)
			RunData.add_xp(player_xp[i], i)

		ProgressData.increment_stat("materials_collected")
		return

	if _cleaning_up:
		RunData.add_bonus_gold(gold.value)


func _check_for_pause() -> void :
	if not LanGame.in_session() or RunData.is_streamplay_run:
		._check_for_pause()
		return
	if _skip_pause_check:
		_skip_pause_check = false
		return
	for player_index in RunData.get_player_count():
		var remapped_device = CoopService.get_remapped_player_device(player_index)
		if remapped_device >= 0 and Input.is_action_just_released("ui_pause_%s" % remapped_device):
			_pause_menu.pause(player_index)
			break


func _on_EndWaveTimer_timeout() -> void :
	if not LanGame.in_session():
		._on_EndWaveTimer_timeout()
		return
	SoundManager.clear_queue()
	SoundManager2D.clear_queue()
	InputService.set_gamepad_echo_processing(true)
	_end_wave_timer_timedout = true
	_change_scene(MenuData.title_screen_scene)
