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
- Vanilla `class_name` children of an extended script are reloaded, so `TitleScreenMenus` picks up a `Menus` extension.
- **Autoloads listed before ModLoader cannot be extended:** CrashReporter, BugReporter, Platform, Keys. Later ones can: Utils, RunData, CoopService, ZoneService, and the rest.
- **Godot 3 runs engine callbacks at every inheritance level:** `_init`, `_ready`, `_process`, `_physics_process`, `_input`, `_enter_tree`. An override **does not** replace the vanilla callback, and both run. To stop a vanilla callback, call `set_process(false)` / `set_physics_process(false)` / `set_process_input(false)`, or override the regular methods it calls.
- Regular methods are true overrides. Call the parent with `.method(args)`.
- Member variables: vanilla initialisers run first, then the extension's. Reassign arrays in the extension's `_init()` or with its own initialiser.

## Loading and the crash trap
- Mods load from `res://mods-unpacked` (unpacked) and `<game>/mods/*.zip`. The Steam profile loads workshop zips only. CLI flags: `--mods-path`, `--disable-mods`, `-vvv`.
- **Crash recovery** (`singletons/crash_reporter.gd` ~L55-98): if the previous log contains an `ERROR:` line that mentions `mods-unpacked`, mods are **disabled** on the next start for the steam and epic profiles, and `main_menu` shows `CRASH_RECOVERY_MESSAGE_*`. Keep mod code free of errors and `push_error`.

## This mod
- `mods-unpacked/Moolt-Lan_Coop/mod_main.gd`. Extensions go in `extensions/` and mirror vanilla paths.
- Networking uses Godot 3 high-level multiplayer (`NetworkedMultiplayerENet`, `rpc`). The game has no networking code of its own.
