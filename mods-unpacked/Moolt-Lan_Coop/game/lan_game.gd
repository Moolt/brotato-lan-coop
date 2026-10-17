extends Reference

# In-wave helpers shared by the extensions.
# Vanilla sizes its per-player arrays for 4 players. They grow to MAX_PLAYERS slots, always and
# not only during a session: vanilla already copes with more slots than players (it keeps 4 slots
# for 1-2 players), so the extra slots are never read outside a session.

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const MAX_PLAYERS: = NetProtocol.MAX_PLAYERS


static func in_session() -> bool:
	var lan_net = get_lan_net()
	return lan_net != null and lan_net.active


static func get_lan_net() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("LanNet")


# The lobby name of a player, "" outside a session.
static func get_player_name(player_index: int) -> String:
	var lan_net = get_lan_net()
	if lan_net == null or not lan_net.active:
		return ""
	var entry = lan_net.get_player(player_index)
	return entry.name if entry != null else ""


# Appends value until the array has MAX_PLAYERS slots. Arrays and dictionaries are copied per slot.
static func grow(array: Array, value) -> void :
	var copy: = typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY
	while array.size() < MAX_PLAYERS:
		array.append(value.duplicate() if copy else value)


# Autoload arrays that vanilla never reassigns, grown once at startup (LanNet._ready).
static func grow_autoload_arrays() -> void :
	for stats in [TempStats, LinkedStats]:
		grow(stats.player_stats, {})
		grow(stats.are_player_stats_dirty, false)
	grow(LinkedStats.update_for_player_every_half_sec, false)
