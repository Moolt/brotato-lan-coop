# RunData / PlayerRunData

## `singletons/run_data.gd` (autoload `RunData`, from run_data.tscn)
**Players**
- `players_data := []`: an Array of `PlayerRunData`, indexed by `player_index`.
- `get_player_count()` returns `players_data.size()`.
- `set_player_count(count, reset=false)` (~L282) pushes new PlayerRunData objects, then calls `resize`.
- Mode: `is_coop_run` (`set_coop_run(v)` ~L231), `play_mode` (enum PlayMode {SOLO, COOP, STREAMPLAY_LOCAL, STREAMPLAY_INTERNET}), `is_streamplay_run`.
- Global run fields: `current_wave`, `current_zone`, `current_difficulty`, `bonus_gold`, `enabled_dlcs`, `locked_shop_items` (per player), `elites_spawn`, events, `tracked_item_effects` (per player).

**Accessors** (all take `player_index`): `get_player_character/gold/xp/level/weapons/items/effects/effect/selected_weapon/locked_shop_items`, `get_stat(stat_hash, i)` (~L1383), `sum_all_player_effects(hash)`.

**Mutators**
- Gold and XP: `add_gold/remove_gold` (~L879/890), `add_xp` (~L818), `level_up` (~L864).
- Items and weapons: `add_character(char, i)` (~L906, calls add_item), `add_item(item, i, is_selection)` (~L916), `add_weapon(w, i, is_selection)` (~L982), `remove_item`, `remove_weapon*`.
- Stats: `add_stat/remove_stat` (~L1478/1487), `apply_item_effects` (~L1244).
- `add_starting_items_and_weapons()` (~L1618).

**Signals** (most carry player_index): `levelled_up`, `gold_changed(new, i)`, `xp_added`, `stat_added`, `stat_removed`, `stats_updated`, `damage_effect`, `lifesteal_effect`, `healing_effect`, `heal_over_time_effect`, `bonus_gold_changed` (global).

**Lifecycle**
- `reset(restart=false)` (~L480): a fresh run calls `set_player_count(1, true)` and `set_coop_run(false)`. A restart rebuilds the players from their saved selections. `reset` also re-creates `locked_shop_items = [[],[],[],[]]` and calls `ItemService.init_unlocked_pool()`.
- `on_wave_start(timer)` (~L237) stores `start_wave_state = get_state()`. `on_wave_end()` runs at the end of each wave.
- `get_state()` (~L1727) and `resume_from_state(state)` (~L1785) cover the full run snapshot: player duplicates plus wave, zone, difficulty, elites/bosses/events, bonus gold, locked shop items, tracked effects. `reset_to_start_wave_state()` is used for retrying a wave.
- `get_shop_scene_path()` / `get_end_run_scene_path()` (~L1846-1851) pick the coop scenes when `is_coop_run`.

## `singletons/player_run_data.gd` (class `PlayerRunData`, extends Reference)
- Fields: `current_character`, `current_health`, `current_level`, `current_xp`, `gold`, `selected_weapon`, `selected_item`, `weapons[]`, `items[]`, `appearances[]`, `effects` (Dictionary), `active_sets`, `active_set_effects`, `unique_effects`, `additional_weapon_effects`, `tier_iv_weapon_effects`, `tier_i_weapon_effects`, ban fields (`uses_ban`, `remaining_ban_token`, `banned_items`), and challenge counters.
- **Stats are stored inside `effects`**, keyed by `Keys.<stat>_hash`. `init_effects()` merges in `init_stats()`. Read stats with `RunData.get_stat(hash, i)` or `Utils.get_stat`.
- `duplicate()` (~L49), **`serialize() -> Dictionary`** (~L78; items and weapons are serialized, the character is stored by `my_id`), **`deserialize(data)`** (~L131).

## Serializing the whole run (for saves; reusable for network)
- `ProgressData.get_run_state(shop_items, rerolls...)` builds a Dictionary.
- `singletons/progress_data_loader_v3.gd` has `serialize_run_state(state)` (~L582) and `deserialize_run_state(state)` (~L363). `serialize_run_state` turns `players_data` into `serialize()` dicts, the background into a name, and challenges into ids.
- `ProgressData.saved_run_state` holds the saved run, and `save_run_state(...)` writes it.

## Related per-player singletons
`TempStats.player_stats` and `LinkedStats.update_for_player_every_half_sec` are per-player stat caches. So are `Utils._stat_caches` and `Utils._manual_aim_cache`. All of them are sized 4 (see hardcoded-4-players.md).
