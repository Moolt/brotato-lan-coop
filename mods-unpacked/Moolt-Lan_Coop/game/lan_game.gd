extends Reference

# In-wave helpers shared by the extensions.
# Vanilla sizes its per-player arrays for 4 players. They grow to MAX_PLAYERS slots, always and
# not only during a session: vanilla already copes with more slots than players (it keeps 4 slots
# for 1-2 players), so the extra slots are never read outside a session.

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const MAX_PLAYERS: = NetProtocol.MAX_PLAYERS
# Vanilla coop players; enemy HP grows slower beyond them (see apply_enemy_scaling).
const VANILLA_MAX_PLAYERS: = 4
# Enemy cap factor at most (250 enemies in a normal wave): past ~300 enemies vanilla physics
# can't keep 60 ticks a second, on a laptop host already earlier.
const MAX_ENEMY_CAP_FACTOR: = 2.5
# In a session enemy hitboxes move off the enemies layer (Utils.ENEMIES_BIT) onto unused
# layer 20, and hurtboxes that listen to enemies listen to it too (extensions: enemy.gd,
# overlap/hurtbox.gd). On the
# enemies layer every enemy body and every weapon range also paired with nearby hitboxes.
const ENEMY_HITBOX_BIT: = 1 << 19


static func in_session() -> bool:
	var lan_net = get_lan_net()
	return lan_net != null and lan_net.active


static func get_lan_net() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("LanNet")


# The wave's LanWaveSync (net/wave_sync.gd), null outside a wave in a session.
static func get_wave_sync() -> Node:
	var lan_net = get_lan_net()
	return lan_net.wave_sync if lan_net != null else null


# True on a LAN client during a wave.
static func is_wave_client() -> bool:
	var wave_sync = get_wave_sync()
	return wave_sync != null and not wave_sync.is_host


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
	return min(1.0 + get_scaling("enemy_cap_per_player") * (player_count - 1), MAX_ENEMY_CAP_FACTOR)


# Sets the per-player enemy factors that vanilla reads (EntitySpawner, EntityService), from
# the session's knobs. Enemy HP grows by enemy_health_per_player for players 2-4 and by
# enemy_health_per_player_beyond_4 after that, because in the bigger arena fewer players share
# each enemy. Vanilla multiplies the factors by (n-1), so they get the average over all extra
# players. CoopService.clear() (main menu) restores vanilla's values.
# The spawn count grows only while the enemy cap does (get_count_players): past that, vanilla
# would cull random enemies without loot at every group spawn. The count it would have added
# goes into enemy HP instead. Vanilla's coop material bonus (CoopService
# get_additional_materials_per_coop_player) reads the lower count, so materials keep up.
static func apply_enemy_scaling(player_count: int) -> void :
	CoopService.additional_enemy_damage_per_coop_player = get_scaling("enemy_damage_per_player")
	CoopService.additional_enemies_per_coop_player = get_scaling("enemy_count_per_player")
	if player_count > 1:
		var extra: = player_count - 1
		var count_extra: = get_count_players(player_count) - 1
		var per_player: float = get_scaling("enemy_count_per_player")
		var count_cut: float = (1.0 + per_player * extra) / (1.0 + per_player * count_extra)
		CoopService.additional_enemies_per_coop_player = per_player * count_extra / extra
		var small: = min(extra, VANILLA_MAX_PLAYERS - 1)
		var health: float = 1.0 + small * get_scaling("enemy_health_per_player") + (extra - small) * get_scaling("enemy_health_per_player_beyond_4")
		CoopService.additional_enemy_health_per_coop_player = (health * count_cut - 1.0) / extra
	EntityService.reset_cache()


# The player count up to which the spawn count grows: where the enemy cap factor reaches
# MAX_ENEMY_CAP_FACTOR (7 with the default knobs), at most player_count.
static func get_count_players(player_count: int) -> int:
	var cap_per_player: = get_scaling("enemy_cap_per_player")
	if cap_per_player <= 0.0:
		return player_count
	return int(min(player_count, 1 + floor((MAX_ENEMY_CAP_FACTOR - 1.0) / cap_per_player + 0.0001)))


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
