extends "res://singletons/progress_data_loader_v3.gd"

# The run (de)serializer builds locked_shop_items and shop_items with 4 slots, then loops over
# all of the state's slots (12 in a session, see LanGame), so it fails once a player with index 4
# or more has one. Vanilla handles the first 4 slots; the rest are (de)serialized here the same
# way. The run state of every LAN sync goes through these (RunBuilder).

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
	return result


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
