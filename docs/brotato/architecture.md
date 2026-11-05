# Architecture

## Autoloads (`project.godot` `[autoload]`, in this order)
1. Before ModLoader (these **cannot** be extended by mods): CrashReporter, BugReporter, Platform, Keys.
2. ModLoaderStore, ModLoader.
3. After ModLoader (these **can** be extended): Utils, MenuData, ProgressData, AnnouncementManager, ItemService, SkinManager, ZoneService, RunData, SoundManager, SoundManager2D, MusicManager, Text, ChallengeService, InputService, WeaponService, TempStats, LinkedStats, DebugService, CursorManager, CoopService, FocusEmulatorSignal, EffectBehaviorService, EntityService, PetService, PopinManager, Streamplay, UIService, SoundService, OS_Seaven.

Some of these are `.tscn` autoloads with exported tuning values: run_data, item_service, zone_service, coop_service, challenge_service, debug_service, and others.

## Boot and scene chain
`run/main_scene = res://pause.tscn`. Despite the name, `pause.gd` is the **boot splash**: it waits for ProgressData to be ready, then calls `change_scene(title_screen.tscn)`.

Every scene change uses `get_tree().change_scene(path)`. Paths live in `singletons/menu_data.gd` (`MenuData.game_scene = "res://main.tscn"`, `shop_scene`, `character_selection_scene`, `weapon_selection_scene`, `difficulty_selection_scene`, `title_screen_scene`).

```
title_screen.tscn (MainMenu) --Start--> character_selection.tscn (main_menu.gd:_on_StartButton_pressed)
  -> weapon_selection.tscn        (character_selection.gd ~L220; skipped if no weapon slots)
  -> difficulty_selection.tscn    (weapon_selection.gd ~L156)
  -> main.tscn  (the wave)        (difficulty_selection.gd ~L124)
  -> RunData.get_shop_scene_path()  shop.tscn | coop_shop.tscn   (main.gd _on_EndWaveTimer_timeout)
  -> main.tscn ... (base_shop.gd ~L346)
  -> RunData.get_end_run_scene_path() end_run.tscn | coop_end_run.tscn
  -> main / character_selection / title  (base_end_run.gd)
```
Run state is reset with `RunData.reset()`. It is called from the title screen, main_menu.init, base_end_run, menu_restart, and progress_data.

## Directory map
- `singletons/`: autoload scripts (services, RunData, ProgressData, CoopService, InputService, Utils).
- `main.gd/.tscn`: the wave scene (HUD, timers, EntitySpawner, WaveManager, camera, pools).
- `global/`: entity_spawner, my_camera, tile maps, stats_manager.
- `zones/`: ZoneData, WaveData, wave_manager, per-zone `.tres` wave files.
- `entities/`: entity → unit → player / enemies / neutral / pets / structures, plus behaviors and births.
- `weapons/`, `projectiles/`, `items/` (pickups plus item data), `effects/`, `effect_behaviors/`.
- `ui/menus/`: title screen, pages, run (selection screens, end run), shop, ingame (pause, upgrades), global widgets.
- `ui/hud/`: in-wave HUD elements.
- `addons/mod_loader/`: ModLoader 6.3.0. `mods-unpacked/`: unpacked mods.

## Platform / DLC
- `Platform` picks steam / epic / gog / local by feature tag. Steam is only used for achievements, DLC and ownership. **There is no networking anywhere in the game.**
- DLC (1.2.0.1): both DLCs are in the main `Brotato.pck`; nothing is mounted. `ProgressData.dlc_ids` = `["primal_dread", "abyssal_terrors"]`; `check_for_available_dlcs()` keeps those `Platform.is_dlc_owned` in `ProgressData.available_dlc_ids` (`is_dlc_available(id)`). Ownership: GOG `AbstractPlatform._has_dlc_marker`, a file `<id>.dlc` in `Utils.get_game_dir()` (`res://` in the editor; the project has the custom feature `gog`, so an editor run is GOG); Steam `isDLCInstalled`; local platform `DebugService.owned_dlc_ids`. A player without a DLC has the same pck, just no marker.
- Content comes in **item sets**: `ItemService.update_data_list` holds `updates/*.tres` (`UpdateData`: `id`, `update_type` DLC or UPDATE, `item_set`, `dlc_data`); `updates/item_sets/*_set.tres` (`ItemSetData`: items, weapons, characters, challenges). `ItemService.items` / `weapons` / `characters` are built from `base_game_item_set` plus the active sets. Players can switch sets off (main menu "Item Sets", `ProgressData.deactivated_update_data`); `ProgressData.active_update_data` = available and not deactivated (`refresh_active_update_data`). A run stores them in `RunData.active_update_data_ids` (run state; `resume_from_state` applies them with `ProgressData.apply_run_update_data`), and `ItemService.init_unlocked_pool()` builds the shop pool from them (and `RunData.current_difficulty` against `item.minimum_difficulty`). Characters can need a set (`required_item_set`).
- `ItemService.get_dlc_data_by_id(id)` gives `dlcs/dlc_1/dlc_1_data.gd` (`DLC1Data`: `curse_item`, poisoned fruit) or `dlcs/dlc_2/dlc_2_data.gd` (`DLC2Data`: meca/mutant items, evolution, mutation). `RunData.enabled_dlcs` = `available_dlc_ids` at run start; vanilla curses with `"abyssal_terrors" in RunData.enabled_dlcs`.
- Zones: `ZoneService.zones` always holds all three (`my_id` 0 crash, 1 abyss, 2 jungle) with `dlc_id`; vanilla lists only owned ones (`zone_selection_button.gd`). Enemies by zone: `entities/units/enemies/crash_zone/`, `abyss/` (the old DLC's), `jungle/`, `bosses/`.
