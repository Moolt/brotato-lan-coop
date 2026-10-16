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
- DLC: `ProgressData.is_dlc_available_and_active("abyssal_terrors")`, `ProgressData.get_active_dlc_ids()`, `RunData.enabled_dlcs`. DLC content is added through `global/dlc_data.gd`.
