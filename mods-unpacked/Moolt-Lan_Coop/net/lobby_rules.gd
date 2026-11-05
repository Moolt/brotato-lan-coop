extends Reference

# What a lobby entry may contain. The lobby UI, the host's validation and the run builder all
# use these, so they never disagree. During a session everything is unlocked on every peer
# (LanNet._apply_multiplayer_unlocks), so the unlock checks only matter outside of one.
# Starting choices follow vanilla weapon_selection.gd: the character's starting weapons and
# starting items, filtered by unlocks. Characters without choices need no weapon_ids; the others
# pick get_pick_count of them (Survivor: 2, the same one twice is fine, as in vanilla).
# Item sets (ProgressData.active_update_data, the host's on every peer: LanNet._apply_host_item_sets):
# a character or starting choice from a set that is off is left out (vanilla greys them out), and
# so is a character whose starting choices all come from such sets.


static func get_character(character_id) -> CharacterData:
	if typeof(character_id) != TYPE_STRING or character_id.empty():
		return null
	for character in ItemService.characters:
		if character.my_id == character_id:
			return character
	return null


static func is_character_unlocked(character: CharacterData) -> bool:
	return character != null and ProgressData.characters_unlocked.has(character.my_id_hash)


# Unlocked, its item set (if any) is on, and it has a starting choice left if it has any at all.
static func is_character_available(character: CharacterData) -> bool:
	if not is_character_unlocked(character) or ItemService.get_disabled_required_update(character) != null:
		return false
	return get_all_starting_choices(character).empty() or not get_starting_choices(character).empty()


static func get_available_characters() -> Array:
	var result: = []
	for character in ItemService.characters:
		if is_character_available(character):
			result.append(character)
	return result


# False for a weapon or item from an item set that is off (vanilla weapon_selection).
static func is_choice_available(choice: ItemParentData) -> bool:
	var update_data: UpdateData = ItemService.get_update_data_by_item_id(choice)
	return update_data == null or ProgressData.has_item_set(update_data.id)


# WeaponData and ItemData the character may start with, including those from item sets that are off.
static func get_all_starting_choices(character: CharacterData) -> Array:
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


# The starting choices that can be picked.
static func get_starting_choices(character: CharacterData) -> Array:
	var choices: = []
	for choice in get_all_starting_choices(character):
		if is_choice_available(choice):
			choices.append(choice)
	return choices


static func get_starting_choice(character: CharacterData, choice_id):
	if typeof(choice_id) != TYPE_STRING or choice_id.empty():
		return null
	for choice in get_starting_choices(character):
		if choice.my_id == choice_id:
			return choice
	return null


# 1 plus the character's extra_starting_weapon_choices (vanilla weapon_selection._get_required_pick_count).
static func get_pick_count(character: CharacterData) -> int:
	var count: = 1
	if character == null:
		return count
	for effect in character.effects:
		if effect.key == "extra_starting_weapon_choices":
			count += int(effect.value)
	return count


# True for an array of at most get_pick_count valid choice ids (fewer while still picking).
static func are_valid_picks(character: CharacterData, choice_ids) -> bool:
	if typeof(choice_ids) != TYPE_ARRAY or choice_ids.size() > get_pick_count(character):
		return false
	for choice_id in choice_ids:
		if get_starting_choice(character, choice_id) == null:
			return false
	return true


# The WeaponData and ItemData for the valid ids, in pick order.
static func get_starting_picks(character: CharacterData, choice_ids) -> Array:
	var picks: = []
	if typeof(choice_ids) != TYPE_ARRAY:
		return picks
	for choice_id in choice_ids:
		var choice = get_starting_choice(character, choice_id)
		if choice != null:
			picks.append(choice)
	return picks


static func needs_starting_choice(character: CharacterData) -> bool:
	return not get_starting_choices(character).empty()


# True when the entry's character is available and all its picks are made (or none is needed).
static func is_entry_complete(entry: Dictionary) -> bool:
	var character: = get_character(entry.get("character_id"))
	if not is_character_available(character):
		return false
	if not needs_starting_choice(character):
		return true
	var choice_ids = entry.get("weapon_ids")
	return are_valid_picks(character, choice_ids) and choice_ids.size() == get_pick_count(character)


# Zones and difficulties the host can pick: every zone in ZoneService whose DLC this machine
# owns (as vanilla's zone button lists them; every peer owns the same DLCs) and every
# difficulty, regardless of the host's save progress.
static func get_zones() -> Array:
	var zones: = []
	for zone in ZoneService.zones:
		if is_zone_available(zone):
			zones.append(zone)
	return zones


static func is_zone_available(zone: ZoneData) -> bool:
	return zone.dlc_id == "" or ProgressData.available_dlc_ids.has(zone.dlc_id)


static func get_zone(zone_id) -> ZoneData:
	if typeof(zone_id) != TYPE_INT:
		return null
	for zone in get_zones():
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
