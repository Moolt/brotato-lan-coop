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
	RunData.enabled_dlcs = ProgressData.get_active_dlc_ids()
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
