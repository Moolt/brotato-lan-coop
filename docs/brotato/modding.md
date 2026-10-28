# Modding with ModLoader 6.3.0 (`addons/mod_loader`)

## Mod structure
- The folder is `mods-unpacked/<namespace>-<name>/`, and the name **must equal** `namespace-name` from `manifest.json`. For this mod: `Moolt-Lan_Coop`.
- Names may only use `[a-zA-Z0-9_]`. The `compatible_*_version` fields are only checked for valid semver format.
- `mod_main.gd`:
  - `_init()` runs inside `ModLoader._init()`. This is before Utils, ProgressData, and the other later autoloads exist, so install extensions here.
  - The node is added as a child of ModLoader, so its `_ready` runs early.
  - Use `call_deferred` to add nodes to `/root`.
- An optional `overwrites.gd` runs before mod_main.

## API (`addons/mod_loader/api/`)
**`ModLoaderMod`** (all static):
- `install_script_extension(path)`
- `register_global_classes_from_array`
- `add_translation(resource_path)`
- `append_node_in_scene(scene, name, parent, instance_path, visible)`
- `save_scene(scene, path)` (`take_over_path`, replaces a vanilla .tscn globally)
- `get_unpacked_dir()` returns `"res://mods-unpacked/"`
- `get_mod_data`, `is_mod_loaded`

**Other classes:**
- `ModLoaderLog`: `info/warning/error/success/debug(msg, mod_name)`.
- `ModLoaderConfig`: `get_current_config(mod_id)`, using `config_schema` from the manifest.
- `ModLoaderModManager`, `ModLoaderUserProfile`.

**There is no method-hook system** (that arrived in 7.x).

## Script extensions: rules and gotchas
- The extension file does `extends "res://<vanilla>.gd"`. It **must not** declare `class_name`.
- The file must live inside `res://mods-unpacked/<mod dir>/`, because the mod id is derived from the path.
- How it works: `child_script.take_over_path(vanilla_path)`. Every **new** instance or `load` of the vanilla path then gets the subclass; nodes that already exist keep the old script.
- Extensions are applied after all mod `_init`s, sorted by inheritance depth.
- Vanilla `class_name` children of an extended script are reloaded (`reload()`), so `TitleScreenMenus` picks up a `Menus` extension. Only direct children: grandchildren (`BulletHellProjectile` < `EnemyProjectile` < `Projectile`) keep the old member layout, and the extension's variables can't be read on them.
- **That reload breaks the shipped game.** Its scripts are compiled `.gdc` without source, and `reload()` on one reparses an empty source: the class becomes an empty `Reference` script (`Consumable` no longer extends `Item`; `main.gdc` then fails with "The assigned value type (Node) doesn't match the variable's type (consumable.gd)" and the game doesn't start). The decompiled sources reload fine, so this only shows in a shipped build. So: never `reload()` a vanilla script, and install extensions of classes with `class_name` subclasses yourself, before anything compiles a subclass (the mod's `EARLY_EXTENSIONS`, [lan-coop-mod.md](../lan-coop-mod.md#pitfalls-learned)).
- `take_over_path` doesn't keep the script alive: the resource cache holds no reference. An extension installed by hand must be referenced (ModLoader keeps its own in `ModLoaderStore.saved_scripts`), or it is freed and the vanilla script is back at its path.
- Scripts compile their type hints against the class installed at that moment. A vanilla `.gdc` compiled before an extension of a class in one of its function signatures is installed doesn't match an override compiled after ("The function signature doesn't match the parent").
- **Autoloads listed before ModLoader cannot be extended:** CrashReporter, BugReporter, Platform, Keys. Later ones can: Utils, RunData, CoopService, ZoneService, and the rest.
- **Godot 3 runs engine callbacks at every inheritance level:** `_init`, `_ready`, `_process`, `_physics_process`, `_input`, `_enter_tree`. An override **does not** replace the vanilla callback, and both run. To stop a vanilla callback, call `set_process(false)` / `set_physics_process(false)` / `set_process_input(false)`, or override the regular methods it calls.
- Regular methods are true overrides. Call the parent with `.method(args)`.
- Member variables: vanilla initialisers run first, then the extension's. Reassign arrays in the extension's `_init()` or with its own initialiser.
- **A parse error makes the extension silently absent.** ModLoader then logs `Invalid get index 'resource_path' (on base: 'null instance')` from `script_extension.gd`, and vanilla runs unchanged. A common cause: `var x: = expr` where `expr` has no static type (e.g. arithmetic on an untyped member such as `args.player_index`). Write `var x: float = ...` instead. Run a quick `quit`-role launch after editing to catch these.
- **Adding nodes with unique names (`%Name`) at runtime:** `duplicate()` a node set, rename the copies, add them to the tree, then set `owner` and `unique_name_in_owner`. Setting the owner while a copy still has the original's name fails, because the unique name is already taken. Do it in the extension's `_enter_tree` if vanilla's `_ready` looks the nodes up (see `extensions/main.gd`).

## Loading and the crash trap
- Mods load from `res://mods-unpacked` (unpacked) and `<game>/mods/*.zip`. The Steam profile loads workshop zips only. CLI flags: `--mods-path`, `--disable-mods`, `-vvv`.
- **Crash recovery** (`singletons/crash_reporter.gd` ~L55-98): if the previous log contains an `ERROR:` line that mentions `mods-unpacked`, mods are **disabled** on the next start for the steam and epic profiles, and `main_menu` shows `CRASH_RECOVERY_MESSAGE_*`. Keep mod code free of errors and `push_error`. `SCRIPT ERROR:` lines count too (they contain `ERROR:`). The disable only flips `enable_mods` on the steam/epic option resources in memory, so a run from the editor or a test copy is not affected.

## This mod
- `mods-unpacked/Moolt-Lan_Coop/mod_main.gd`. Extensions go in `extensions/` and mirror vanilla paths.
- Networking uses Godot 3 high-level multiplayer (`NetworkedMultiplayerENet`, `rpc`). The game has no networking code of its own.
