extends "res://singletons/progress_data_loader_v3.gd"

# The run (de)serializer builds locked_shop_items and shop_items with 4 slots, then loops over
# all of the state's slots (12 in a session, see LanGame), so it fails once a player with index 4
# or more has one. Vanilla handles the first 4 slots; the rest are (de)serialized here the same
# way. The run state of every LAN sync goes through these (RunBuilder).
# Vanilla's effect serializers also leave out a few exported fields, which deserialize_run_state
# takes back from the item's base resource (_lan_restore_unserialized). In a session every wave
# end goes through this; vanilla only through Continue.

const VANILLA_SLOTS: = 4
const SLOT_KEYS: = ["locked_shop_items", "shop_items"]


func serialize_run_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = .serialize_run_state(_lan_first_slots(state))
	for key in SLOT_KEYS:
		var slots: Array = state.get(key, [])
		for player_index in range(VANILLA_SLOTS, slots.size()):
			var serialized: = []
			for item in slots[player_index]:
				serialized.push_back([item[0].serialize(), item[1]])
			result[key].push_back(serialized)
	return result


func deserialize_run_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = .deserialize_run_state(_lan_first_slots(state))
	if not result.get("has_run_state", false):
		return result
	for key in SLOT_KEYS:
		var slots: Array = state.get(key, [])
		for player_index in range(VANILLA_SLOTS, slots.size()):
			var deserialized: = []
			for item in slots[player_index]:
				var item_data = _lan_deserialize_item(item[0])
				if item_data != null:
					deserialized.push_back([item_data, item[1]])
			result[key].push_back(deserialized)
	_lan_restore_unserialized(result)
	return result


# Effects come back as fresh instances with the serialized fields only. Fields vanilla doesn't
# serialize: WeaponGainStatForEveryStatEffect.increased_stat_name (empty, the DLC's captain's sword
# from tier 3 then raises script errors at every stats update), OneShotOnHitEffect's sound and
# particles, LinearScalingEffect.invert_scaling. Any exported field missing from an effect's
# serialize() is copied from the same effect of the base item (same index and script; a curse
# only changes values and appends effects).
func _lan_restore_unserialized(result: Dictionary) -> void :
	for player_data in result.get("players_data", []):
		if player_data is PlayerRunData:
			for item in player_data.items + player_data.weapons:
				_lan_restore_item(item)
	for key in SLOT_KEYS:
		for slot in result.get(key, []):
			for entry in slot:
				if typeof(entry) == TYPE_ARRAY and not entry.empty():
					_lan_restore_item(entry[0])


func _lan_restore_item(item) -> void :
	if not item is ItemParentData:
		return
	var base = ItemService.get_element_safe(ItemService.weapons if item is WeaponData else ItemService.items, item.my_id)
	if base == null:
		return
	for i in min(item.effects.size(), base.effects.size()):
		var effect = item.effects[i]
		var source = base.effects[i]
		if effect == null or source == null or effect.get_script() != source.get_script():
			continue
		var serialized: Dictionary = effect.serialize()
		for property in effect.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR and not serialized.has(property.name):
				effect.set(property.name, source.get(property.name))


# A copy of state whose slot arrays hold only the first VANILLA_SLOTS players.
func _lan_first_slots(state: Dictionary) -> Dictionary:
	var copy: = state.duplicate()
	for key in SLOT_KEYS:
		if copy.has(key) and typeof(copy[key]) == TYPE_ARRAY and copy[key].size() > VANILLA_SLOTS:
			copy[key] = copy[key].slice(0, VANILLA_SLOTS - 1)
	return copy


# deserialize_run_state's lookup for one shop or locked item (a weapon or an item).
func _lan_deserialize_item(serialized):
	if typeof(serialized) != TYPE_DICTIONARY or not serialized.has("my_id"):
		return null
	var item_data = ItemService.get_element_safe(ItemService.items, serialized.my_id)
	if item_data == null:
		item_data = ItemService.get_element_safe(ItemService.weapons, serialized.my_id)
	if item_data == null:
		return null
	item_data = item_data.duplicate()
	item_data.deserialize_and_merge(serialized)
	return item_data
