extends Reference

# Builds the coop run from the lobby on the host, (de)serializes it for clients and digests it
# so every peer can check it holds the same run.
# build_run follows the vanilla chain character_selection -> weapon_selection ->
# difficulty_selection. Serialization reuses the save loader (the same path as "Continue").

const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")


# Host: fills RunData from the lobby entries (sorted by player_index) and settings.
static func build_run(players: Array, settings: Dictionary) -> void :
	RunData.reset()
	RunData.current_zone = settings.zone
	RunData.reset_background()
	RunData.set_player_count(players.size(), true)
	RunData.set_coop_run(true)
	RunData.play_mode = RunData.PlayMode.COOP

	# character_selection._on_selections_completed
	for player_index in players.size():
		RunData.add_character(LobbyRules.get_character(players[player_index].character_id), player_index)

	# weapon_selection._on_selections_completed
	for player_index in players.size():
		var entry: Dictionary = players[player_index]
		var choice = LobbyRules.get_starting_choice(LobbyRules.get_character(entry.character_id), entry.weapon_id)
		if choice is WeaponData:
			var _weapon = RunData.add_weapon(choice, player_index, true)
		elif choice is ItemData:
			RunData.add_item(choice, player_index, true)
	RunData.add_starting_items_and_weapons()

	# difficulty_selection._on_element_pressed (without the save and stats calls).
	# Like vanilla coop, the difficulty effects go to player 0 only: the danger effects are
	# read from player 0 (entity_service.gd) and double_boss is summed over all players.
	var difficulty: = LobbyRules.get_difficulty(settings.difficulty)
	RunData.current_difficulty = difficulty.value
	RunData.reset_elites_spawn()
	RunData.init_elites_spawn()
	RunData.init_events_nightmare()
	RunData.enabled_dlcs = ProgressData.available_dlc_ids.duplicate()
	RunData.active_update_data_ids = ProgressData.active_update_data.duplicate()
	ItemService.init_unlocked_pool()
	for effect in difficulty.effects:
		effect.apply(0)
	for player_data in RunData.players_data:
		player_data.uses_ban = RunData.is_ban_mode_active
		player_data.remaining_ban_token = RunData.BAN_MAX_TOKEN
	RunData.init_bosses_spawn()
	RunData.current_run_accessibility_settings = ProgressData.settings.enemy_scaling.duplicate()


# The current run as JSON text, exactly as vanilla writes it into the run save.
static func serialize_run() -> String:
	return JSON.print(ProgressDataLoaderV3.new().serialize_run_state(ProgressData.get_run_state()))


# Replaces RunData with a run from serialize_run(), following vanilla's load path
# (JSON parse -> deserialize_run_state -> merge into an empty state -> int fixes ->
# resume_from_state). The deserializers expect JSON types, so the run travels as text.
# The host applies its own run this way too, so every peer runs the same deserialized copy.
# Returns false if the text isn't a run.
static func apply_run(run_json: String) -> bool:
	var parsed: = JSON.parse(run_json)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or not parsed.result.get("has_run_state", false):
		return false
	var state: Dictionary = ProgressDataLoaderV3.new().deserialize_run_state(parsed.result)
	state = Utils.merge_dictionaries(ProgressData._get_empty_run_state(), state)
	# progress_data.gd load_from_loader
	for key in ["nb_of_waves", "current_wave", "current_difficulty", "bonus_gold", "retries"]:
		if state.has(key) and typeof(state[key]) == TYPE_REAL:
			state[key] = int(state[key])
	for key in ["reroll_count", "paid_reroll_count", "initial_free_rerolls", "free_rerolls"]:
		if state.has(key) and typeof(state[key]) == TYPE_ARRAY:
			for i in state[key].size():
				if typeof(state[key][i]) == TYPE_REAL:
					state[key][i] = int(state[key][i])
	RunData.reset()
	RunData.resume_from_state(state)
	return true


# Host: a player's solo run from the shop's Go (serialize_run in the solo view), deserialized
# by the save loader like apply_run, without touching RunData. Its slot 0 holds the player:
# players_data, locked_shop_items, tracked_item_effects. Empty if the text isn't a solo run.
static func parse_solo_run(run_json: String) -> Dictionary:
	var parsed: = JSON.parse(run_json)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or not parsed.result.get("has_run_state", false):
		return {}
	var state: Dictionary = ProgressDataLoaderV3.new().deserialize_run_state(parsed.result)
	if not state.get("has_run_state", false) or state.players_data.size() != 1 or not state.players_data[0] is PlayerRunData:
		return {}
	return state


# Host, once everyone pressed Go: a player's solo run from the shop (parse_solo_run) goes into
# its slot of the coop run. Returns false if the text isn't a solo run.
static func merge_solo_run(player_index: int, run_json: String) -> bool:
	var state: = parse_solo_run(run_json)
	if state.empty() or player_index < 0 or player_index >= RunData.get_player_count():
		return false
	RunData.players_data[player_index] = state.players_data[0]
	RunData.locked_shop_items[player_index] = state.locked_shop_items[0]
	# resume_from_state's conversion: JSON made the effect keys strings.
	var tracked: Array = Utils.convert_to_hash_array(state.tracked_item_effects.duplicate())
	if not tracked.empty():
		RunData.tracked_item_effects[player_index] = tracked[0]
	return true


# Host, after merging: what vanilla's shop runs once for all players when the last one presses
# Go (base_shop.gd _on_GoButton_pressed; the candy-bag locking ran on each machine) and when
# the shop closes (_on_tree_exited: cursing locked items). Ends with the next wave number.
static func apply_go() -> void :
	var next_wave: = RunData.get_next_wave()
	for player_index in RunData.get_player_count():
		var effects = RunData.get_player_effects(player_index)
		var hourglass_count = effects[Keys.item_hourglass_hash] if effects.has(Keys.item_hourglass_hash) else 0
		if hourglass_count > 0:
			var source_item = RunData.get_player_item(Keys.item_hourglass_hash, player_index)
			RunData.remove_item(source_item, player_index)

		var extra_elite_spawn_chance = effects[Keys.extra_elite_next_wave_chance_hash] if effects.has(Keys.extra_elite_next_wave_chance_hash) else 0
		if Utils.get_chance_success(float(extra_elite_spawn_chance) / 100):
			var rand_elite_id = ItemService.get_random_neutral_elite_id_hash_from_zone(ZoneService.current_zone.my_id)
			effects[Keys.extra_enemies_next_wave_hash].append(["res://zones/common/elite/group_elite.tres", 1, rand_elite_id])

	RunData.current_wave = next_wave

	for player_index in RunData.get_player_count():
		var effects = RunData.get_player_effects(player_index)
		var lifeform_scanner_count = effects[Keys.item_lifeform_scanner_hash] if effects.has(Keys.item_lifeform_scanner_hash) else 0
		while lifeform_scanner_count > 0:
			var source_item = RunData.get_player_item(Keys.item_lifeform_scanner_hash, player_index)
			if source_item == null:
				break
			if RunData.switch_next_elite_to_horde(RunData.current_wave):
				RunData.remove_item(source_item, player_index)
				lifeform_scanner_count -= 1
			else:
				break

	for player_index in RunData.get_player_count():
		_curse_locked_items(player_index)


# base_shop.gd _on_tree_exited, for one player.
static func _curse_locked_items(player_index: int) -> void :
	var curse_locked_items: int = RunData.get_player_effect(Keys.curse_locked_items_hash, player_index)
	var has_cursed_an_item = false
	var nb_locked_items_that_didnt_get_cursed: int = 0
	var locked_items: Array = RunData.locked_shop_items[player_index]
	var randomized_positions = []

	for i in locked_items.size():
		randomized_positions.push_back(i)

	randomized_positions.shuffle()

	for i in randomized_positions:
		if not ItemService.can_item_be_cursed(locked_items[i][0]):
			continue

		if Utils.get_chance_success((RunData.players_data[player_index].curse_locked_shop_items_pity + curse_locked_items) / 100.0):
			if "abyssal_terrors" in RunData.enabled_dlcs:
				var dlc_data = ItemService.get_dlc_data_by_id("abyssal_terrors")
				if dlc_data:
					has_cursed_an_item = true
					RunData.players_data[player_index].curse_locked_shop_items_pity = 0
					RunData.set_tracked_value(player_index, Keys.item_fish_hook_hash, RunData.players_data[player_index].curse_locked_shop_items_pity)
					locked_items[i][0] = dlc_data.curse_item(locked_items[i][0], player_index)
		else:
			nb_locked_items_that_didnt_get_cursed += 1

	if curse_locked_items > 0 and locked_items.size() > 0 and not has_cursed_an_item and nb_locked_items_that_didnt_get_cursed > 0:
		RunData.players_data[player_index].curse_locked_shop_items_pity += int(nb_locked_items_that_didnt_get_cursed * (curse_locked_items / 4.0))
		RunData.set_tracked_value(player_index, Keys.item_fish_hook_hash, RunData.players_data[player_index].curse_locked_shop_items_pity)


# Host: each player's level-ups and crates still to process, from main's _upgrades_to_process
# and _consumables_to_process (they live in main, not in RunData): [[levels], [consumable ids]]
# per player.
static func pack_pending(upgrades_to_process: Array, consumables_to_process: Array) -> Array:
	var pending: = []
	for player_index in RunData.get_player_count():
		var levels: = []
		if player_index < upgrades_to_process.size():
			for upgrade in upgrades_to_process[player_index]:
				levels.append(upgrade.level)
		var crates: = []
		if player_index < consumables_to_process.size():
			for consumable in consumables_to_process[player_index]:
				crates.append(consumable.consumable_data.my_id)
		pending.append([levels, crates])
	return pending


# Client: whether pending (from pack_pending, over the network) fits the current run.
static func is_valid_pending(pending: Array) -> bool:
	if pending.size() != RunData.get_player_count():
		return false
	for entry in pending:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 2 or typeof(entry[0]) != TYPE_ARRAY or typeof(entry[1]) != TYPE_ARRAY:
			return false
		for level in entry[0]:
			if typeof(level) != TYPE_INT:
				return false
		for consumable_id in entry[1]:
			if typeof(consumable_id) != TYPE_STRING or ItemService.get_element_safe(ItemService.consumables, consumable_id) == null:
				return false
	return true


# What every peer must agree on, readable for logs.
static func summarize() -> Dictionary:
	var players: = []
	for player_index in RunData.get_player_count():
		var player_data = RunData.players_data[player_index]
		var weapons: = []
		for weapon in player_data.weapons:
			weapons.append(weapon.my_id)
		var items: = []
		for item in player_data.items:
			items.append(item.my_id)
		items.sort()
		players.append({
			"character": player_data.current_character.my_id if player_data.current_character != null else "",
			"weapons": weapons,
			"items": items,
			"gold": player_data.gold,
			"max_hp": RunData.get_player_max_health(player_index),
			"level": player_data.current_level,
			"xp": player_data.current_xp,
		})
	return {
		"zone": RunData.current_zone,
		"wave": RunData.current_wave,
		"difficulty": RunData.current_difficulty,
		"coop": RunData.is_coop_run,
		"players": players,
		"elites_spawn": RunData.elites_spawn,
		"bosses_spawn": RunData.bosses_spawn,
		"events_spawn": RunData.events_spawn,
	}


static func digest() -> String:
	return to_json(summarize()).md5_text()
