# Hardcoded 4-player limits

Lifting the cap means fixing everything below. Line numbers are approximate.

## Caps and constants
- `CoopService.get_max_players()` returns 4 (2 on Switch). `UI_MAX_PLAYER_COUNT = 4`.
- `player_colors` has 4 entries, so `get_player_color(i)` crashes for i ≥ 4. It has about 22 callers.
- `InputService` creates device actions only for dev 0..7 (`REMAP_END = 8`, `MAX_DEVICE_COUNT = 8`).

## Arrays initialised with 4 slots
| File | Arrays |
|---|---|
| `singletons/run_data.gd` | `_players_die_args` (L30); `remove_speed_effect_cache`, `items_nb_cache`, `different_items_nb_cache`, `duplicate_items_cache`, `max_consumable_stats_gained_this_wave`, `tracked_item_effects`, `_are_player_stats_dirty` (L148-154); `current_charmed_enemies`, `steps_taken_this_wave` (L163-164, reset ~L268); `locked_shop_items` (L193 and inside `reset` ~L556); `duplicate_items_cache` (~L606) |
| `main.gd` | `_upgrades_to_process`, `_consumables_to_process` (L31-32); `_proj_on_death_stat_caches` (L48); `_player_is_under_half_health` (L50); local `player_gold`/`player_xp` in `on_gold_picked_up` (~L879) |
| `global/entity_spawner.gd` | `lootworms` (L33); `queues_to_spawn_structures`, `queues_to_spawn_pets` (L40-41); spawn positions only give 4 spots (L93-98) |
| `global/stats_manager.gd` | `_structure_queues`, `_pet_queues` (L10-11) |
| `singletons/utils.gd` | `last_elt_selected` (L60, ~L653); `_stat_caches` (L65, ~L454); `_manual_aim_cache` (L66; `_process` resets it to 4 slots every frame, ~L126) |
| `singletons/temp_stats.gd` | `player_stats`, `are_player_stats_dirty` (L5-6) |
| `singletons/linked_stats.gd` | `update_for_player_every_half_sec` (L4) |
| `singletons/debug_service.gd` | L53-55; `for i in 4` (L61); `log_run_info` default arguments `[[], [], [], []]` (L175), indexed for every player and called from `main.gd` (~L1455) |
| `ui/menus/ingame/upgrades_ui.gd` | `_showing_option`, `_player_is_choosing`, `_extra_items_to_process` (L34-36); `_ready` indexes `_get_player_container(i)` and 4 stat popups for every player, so the coop UI in `main.tscn` fails with > 4 players |
| `ui/menus/global/popup_manager.gd` | `_item_popups`, `_elements_hovered`, `_elements_focused`, `_elements_pressed`, `_stat_popups` (L11-15) |
| `ui/menus/shop/base_shop.gd` | 13 per-player arrays (L8-20). `if (i < 4)` at ~L400 is the shop slot count, not a player count. |
| `progress_data_loader_*.gd` | `locked_shop_items`, `shop_items`, `item_steals` defaults for loading saves |

## Scenes with P1–P4 / 1–4 nodes
- `main.tscn`: `LifeContainerP1-4`, `UILifeBarP1-4`, `UIXPBarP1-4`, `UIGoldP1-4`, `PlayerLifeBarContainerP1-4`, `UIThingsToProcessPlayerContainer1-4`. They are fetched with `get_node("%...P%s")` (~L217, ~L1383).
- `ui/hud/player_ui_elements.gd` `set_hud_position(i)` uses 4 screen corners.
- `FocusEmulator1-4` appear in character_selection, weapon_selection, coop_shop, coop_upgrades_ui, and coop_end_run.
- `character_selection.gd`: `CoopJoinPanel1-4`, `LockedPanel1-4`, `_player_characters` (4). `base_selection.gd`: `_inventory1-4`, `_panel1-4`.
- `coop_shop.gd`: `_player_container1-4`, `_stat_popup1-4`. `upgrades_ui.gd`: `_player_container1-4`, `_stat_popup1-4`. `coop_end_run.gd`: `_player_container1-4`.
- Layout special cases: `coop_shop_player_container.gd` (2 players; synergies only at ≤3 players), `coop_item_popup.gd`, `coop_upgrades_ui_player_container.gd`, `coop_resume.gd` (PS colours ×4).

## Not player-related (ignore)
`focus_emulator.gd` `points.resize(4)` / `range(4)` are rectangle corners. `effect[4]`, `weapons.size() == 4`, and `input_style == 4` are unrelated too.
