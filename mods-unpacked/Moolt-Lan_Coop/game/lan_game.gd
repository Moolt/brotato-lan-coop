extends Reference

# In-wave helpers shared by the extensions.
# Vanilla sizes its per-player arrays for 4 players. They grow to MAX_PLAYERS slots, always and
# not only during a session: vanilla already copes with more slots than players (it keeps 4 slots
# for 1-2 players), so the extra slots are never read outside a session.

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const MOD_ID: = NetProtocol.MOD_ID
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


# The session's game mode (modes/lan_mode.gd), null outside a session.
static func get_mode() -> Reference:
	var lan_net = get_lan_net()
	return lan_net.mode if lan_net != null and lan_net.active else null


# True on a LAN client during a wave.
static func is_wave_client() -> bool:
	var wave_sync = get_wave_sync()
	return wave_sync != null and not wave_sync.is_host


# DLC consumables that ItemService.consumables lacks: the DLCData resources hold them.
const DLC_CONSUMABLE_KEYS: = ["poisoned_fruit", "meca_parts_consumable", "mutation_fruit", "meca_fruit", "mutant_fruit"]


# A consumable by id: vanilla's list (fruit and crates), then the owned DLCs' own (Abyssal Terrors'
# poisoned fruit, Primal Dread's meca parts, mutation, meca and mutant fruit). Null if unknown.
static func get_consumable(consumable_id: String) -> Resource:
	var consumable_data = ItemService.get_element_safe(ItemService.consumables, consumable_id)
	if consumable_data != null:
		return consumable_data
	for dlc_id in ProgressData.available_dlc_ids:
		var dlc_data = ItemService.get_dlc_data_by_id(dlc_id)
		if dlc_data == null:
			continue
		for key in DLC_CONSUMABLE_KEYS:
			var data = dlc_data.get(key)
			if data is ConsumableData and data.my_id == consumable_id:
				return data
	return null


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
# scaling_count: the player count the enemies scale for, if not player_count (a mode's, e.g. a
# team's size); vanilla still multiplies by player_count - 1, so the factors are divided by that.
static func apply_enemy_scaling(player_count: int, scaling_count: int = - 1) -> void :
	if scaling_count < 0:
		scaling_count = player_count
	CoopService.additional_enemy_damage_per_coop_player = get_scaling("enemy_damage_per_player")
	CoopService.additional_enemies_per_coop_player = get_scaling("enemy_count_per_player")
	if player_count > 1:
		var vanilla_extra: = player_count - 1
		var extra: int = int(max(0, scaling_count - 1))
		var count_extra: int = int(max(0, get_count_players(scaling_count) - 1))
		var per_player: float = get_scaling("enemy_count_per_player")
		var count_cut: float = (1.0 + per_player * extra) / (1.0 + per_player * count_extra)
		CoopService.additional_enemies_per_coop_player = per_player * count_extra / vanilla_extra
		var small: = min(extra, VANILLA_MAX_PLAYERS - 1)
		var health: float = 1.0 + small * get_scaling("enemy_health_per_player") + (extra - small) * get_scaling("enemy_health_per_player_beyond_4")
		CoopService.additional_enemy_health_per_coop_player = (health * count_cut - 1.0) / vanilla_extra
		CoopService.additional_enemy_damage_per_coop_player = get_scaling("enemy_damage_per_player") * extra / vanilla_extra
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


# Seeds the global RNG so that every machine rolls the same for tag in this wave (from the host's
# lobby_settings.wave_seed): placements in main's _ready that must match (dig sites, poacher
# zones). False outside a session. Call end_shared_random() after.
static func begin_shared_random(tag: String) -> bool:
	var lan_net = get_lan_net()
	if lan_net == null or not lan_net.active:
		return false
	seed(hash([lan_net.lobby_settings.get("wave_seed", 0), RunData.current_wave, tag]))
	return true


static func end_shared_random() -> void :
	randomize()


# Autoload arrays that vanilla never reassigns, grown once at startup (LanNet._ready).
static func grow_autoload_arrays() -> void :
	for stats in [TempStats, LinkedStats]:
		grow(stats.player_stats, {})
		grow(stats.are_player_stats_dirty, false)
	grow(LinkedStats.update_for_player_every_half_sec, false)
