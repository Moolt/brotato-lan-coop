extends Reference

# Players a run can be started with until Step 4 lifts vanilla's 4-player limits.
const MAX_RUN_PLAYERS: = 4

# What a lobby entry may contain. The lobby UI, the host's validation and the run builder all
# use these, so they never disagree. During a session everything is unlocked on every peer
# (LanNet._apply_multiplayer_unlocks), so the unlock checks only matter outside of one.
# Starting choices follow vanilla weapon_selection.gd: the character's starting weapons and
# starting items, filtered by unlocks. Characters without choices need no weapon_id.


static func get_character(character_id) -> CharacterData:
	if typeof(character_id) != TYPE_STRING or character_id.empty():
		return null
	for character in ItemService.characters:
		if character.my_id == character_id:
			return character
	return null


static func is_character_unlocked(character: CharacterData) -> bool:
	return character != null and ProgressData.characters_unlocked.has(character.my_id_hash)


static func get_unlocked_characters() -> Array:
	var result: = []
	for character in ItemService.characters:
		if is_character_unlocked(character):
			result.append(character)
	return result


# WeaponData and ItemData the character may start with.
static func get_starting_choices(character: CharacterData) -> Array:
	var choices: = []
	if character == null:
		return choices
	for weapon in ItemService.get_ordered_starting_weapons(character.starting_weapons):
		if ProgressData.weapons_unlocked.has(weapon.weapon_id_hash):
			choices.append(weapon)
	for item in ItemService.get_ordered_starting_items(character.starting_items):
		if ProgressData.items_unlocked.has(item.my_id_hash):
			choices.append(item)
	return choices


static func get_starting_choice(character: CharacterData, choice_id):
	if typeof(choice_id) != TYPE_STRING or choice_id.empty():
		return null
	for choice in get_starting_choices(character):
		if choice.my_id == choice_id:
			return choice
	return null


static func needs_starting_choice(character: CharacterData) -> bool:
	return not get_starting_choices(character).empty()


# True when the entry's character is unlocked and its weapon is valid (or none is needed).
static func is_entry_complete(entry: Dictionary) -> bool:
	var character: = get_character(entry.get("character_id"))
	if not is_character_unlocked(character):
		return false
	if not needs_starting_choice(character):
		return true
	return get_starting_choice(character, entry.get("weapon_id")) != null


# Zones and difficulties the host can pick: every zone in ZoneService (as vanilla's zone
# button lists them) and every difficulty, regardless of the host's save progress.
static func get_zone(zone_id) -> ZoneData:
	if typeof(zone_id) != TYPE_INT:
		return null
	for zone in ZoneService.zones:
		if zone.my_id == zone_id:
			return zone
	return null


static func is_valid_zone(zone_id) -> bool:
	return get_zone(zone_id) != null


static func get_difficulty(difficulty_value) -> DifficultyData:
	if typeof(difficulty_value) != TYPE_INT:
		return null
	for difficulty in ItemService.difficulties:
		if difficulty.value == difficulty_value:
			return difficulty
	return null


static func is_valid_difficulty(difficulty_value) -> bool:
	return get_difficulty(difficulty_value) != null
