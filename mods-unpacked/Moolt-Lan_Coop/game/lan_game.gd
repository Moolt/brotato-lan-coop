extends Reference

# In-wave helpers shared by the extensions.
# Vanilla sizes its per-player arrays for 4 players. They grow to MAX_PLAYERS slots, always and
# not only during a session: vanilla already copes with more slots than players (it keeps 4 slots
# for 1-2 players), so the extra slots are never read outside a session.

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const MAX_PLAYERS: = NetProtocol.MAX_PLAYERS
# Vanilla coop players; enemy HP grows slower beyond them (see apply_enemy_scaling).
const VANILLA_MAX_PLAYERS: = 4


static func in_session() -> bool:
	var lan_net = get_lan_net()
	return lan_net != null and lan_net.active


static func get_lan_net() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("LanNet")


# The wave's LanWaveSync (net/wave_sync.gd), null outside a wave in a session.
static func get_wave_sync() -> Node:
	var lan_net = get_lan_net()
	return lan_net.wave_sync if lan_net != null else null


# The lobby name of a player, "" outside a session.
static func get_player_name(player_index: int) -> String:
	var lan_net = get_lan_net()
	if lan_net == null or not lan_net.active:
		return ""
	var entry = lan_net.get_player(player_index)
	return entry.name if entry != null else ""


# A scaling knob (see NetProtocol.DEFAULT_SCALING) as the host set it for this session.
static func get_scaling(key: String) -> float:
	var lan_net = get_lan_net()
	var scaling = lan_net.lobby_settings.get("scaling", {}) if lan_net != null else {}
	return float(scaling.get(key, NetProtocol.DEFAULT_SCALING[key]))


# Linear arena size factor: the area grows by arena_area_per_player for each extra player.
static func get_arena_factor(player_count: int) -> float:
	return sqrt(1.0 + get_scaling("arena_area_per_player") * (player_count - 1))


# Enemy cap factor; vanilla's is 1 + (n-1)/8 (entity_spawner.gd on_group_spawn_timing_reached).
static func get_enemy_cap_factor(player_count: int) -> float:
	return 1.0 + get_scaling("enemy_cap_per_player") * (player_count - 1)


# Sets the per-player enemy factors that vanilla reads (EntitySpawner, EntityService), from
# the session's knobs. Enemy HP grows by enemy_health_per_player for players 2-4 and by
# enemy_health_per_player_beyond_4 after that, because in the bigger arena fewer players share
# each enemy. Vanilla multiplies the factor by (n-1), so HP gets the average over all extra
# players. CoopService.clear() (main menu) restores vanilla's values.
static func apply_enemy_scaling(player_count: int) -> void :
	CoopService.additional_enemies_per_coop_player = get_scaling("enemy_count_per_player")
	CoopService.additional_enemy_damage_per_coop_player = get_scaling("enemy_damage_per_player")
	if player_count > 1:
		var extra: = player_count - 1
		var small: = min(extra, VANILLA_MAX_PLAYERS - 1)
		var health: float = small * get_scaling("enemy_health_per_player") + (extra - small) * get_scaling("enemy_health_per_player_beyond_4")
		CoopService.additional_enemy_health_per_coop_player = health / extra
	EntityService.reset_cache()


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
