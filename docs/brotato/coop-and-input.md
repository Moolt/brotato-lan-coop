# Local coop and input

## `singletons/coop_service.gd` (autoload `CoopService`, from coop_service.tscn)
**Constants:** `GAMEPAD_REMAPPED_DEVICE_ID = 6`, `KEYBOARD_REMAPPED_DEVICE_ID = 7`, `REMAP_END = 8`, `UI_MAX_PLAYER_COUNT = 4`, `FIRST_DEBUG_DEVICE_ID = 8`, `DEBUG_DEVICE_COUNT = 4`, `HOLD_DURATION = 0.7`. `enum PlayerType {KEYBOARD_AND_MOUSE, GAMEPAD_XBOX, GAMEPAD_PLAYSTATION, GAMEPAD_SWITCH}`.

**Players**
- `connected_players`: Array of `[device_id, player_type]`. **player_index = position in this array.** Removing a player shifts everyone after it down one index.
- `get_max_players()` returns 4 (2 on Switch).
- Lookups: `get_remapped_player_device(i)`, `get_player_input_type(i)`, `is_player_using_gamepad(i)`, `get_player_color(i)` (4-colour array, crashes for i ≥ 4), `get_player_key_texture(action, i)`.

**Join flow**
1. `_input` reads the device and remaps it: joypad 0 becomes 6, keyboard becomes 7.
2. The player holds `ui_accept_<dev>` for 0.7 s, then `_process` calls `_add_player`.
3. `connected_players_updated(connected_players)` and `connection_progress_updated(progress)` are emitted.
4. `listening_for_inputs` and `set_process_input(true)` turn joining on. Character selection does this.

**Enemy scaling (exported, set in coop_service.tscn)**
- `additional_enemies_per_coop_player = 0.3`
- `additional_enemy_health_per_coop_player = 0.3`
- `additional_enemy_damage_per_coop_player = 0.08`

`clear()` restores them from the `_initial_*` copies. Material compensation: `get_additional_materials_per_coop_player()` and `get_coop_materials_factor()`.

## Per-device input actions (`singletons/input_service.gd`)
- `_copy_device_actions()` (~L222) duplicates every InputMap action as `<action>_<dev>` for dev 0..7. Examples: `ui_accept_7`, `move_left_6`, `analog_move_left_3`, `rjoy_up_6`, `ui_pause_2`.
- **The suffix is the remapped device id, not the player index.** Device 6 maps joypad events back to real device 0; device 7 does the same for key events.
- Debug devices 8–11 get WASD / TFGH / IJKL / arrow keys (~L255-310).
- `MAX_DEVICE_COUNT = 8`. `_emulate_action` adds the suffix only if `CoopService.is_device_assigned(dev)`.
- Focus loss (`NOTIFICATION_WM_FOCUS_OUT`) emits `game_lost_focus` and may disable input (`settings.on_lost_focus`).
- `InputService._input` sets the mouse mode: in a coop run with more than one player it always hides the cursor (and never updates `using_gamepad`); otherwise keyboard/gamepad input hides it and mouse input shows it. Menus still take mouse clicks while the cursor is hidden, unless a FocusEmulator swallows them (below).

## Movement (`entities/units/movement_behaviors/player_movement_behavior.gd`)
- `var device := 0`. `get_movement()` returns the longer of `get_vector_for_input_prefix("analog_")` and `("button_")`. Mouse-only movement works in solo only.
- `get_vector_for_input_prefix(prefix)`: in coop it reads `Input.get_vector(prefix+"move_left_%s" % device, ...)`; in solo it reads the unsuffixed actions.
- The device is assigned in `global/entity_spawner.gd` `init` (~L105): `player._movement_behavior.device = CoopService.connected_players[player_index][0]`.
- The value is consumed in `unit.gd` `_physics_process`: `_current_movement = get_movement()`.

## Aim and other per-player input (`singletons/utils.gd`)
- `is_player_action_pressed/released(event, i, action)` (~L701/710) test `"%s_%s" % [action, device_of(i)]`.
- `get_player_rjoy_vector(i)` (~L729) is the right-stick aim. `main.gd` `_physics_process` (~L452) uses it to set `player.gamepad_attack_vector`.
- `is_manual_aim(i)` (~L813) uses `_manual_aim_cache`, which has 4 slots. It returns `null`, not `false`, when no manual-aim setting is on; compare with `== true` before passing it to a typed `bool`.
- In coop, keyboard players never get manual (mouse) aim: `is_manual_aim` is `not is_coop_run or is_player_using_gamepad(i)`, and the mouse-press check is solo only.
- Pause: `main.gd` `_check_for_pause` (~L417) polls `ui_pause_<dev>` for each player.

## FocusEmulator (per-player UI focus in coop menus)
- `ui/menus/global/focus_emulator.gd`. Nodes are named `FocusEmulator1..4` in each coop scene.
- Each node reads `ui_up_<dev>`, `ui_accept_<dev>`, and so on, using the device from `connected_players[player_index][0]`.
- Lookup: `Utils.get_focus_emulator(i)` returns `"FocusEmulator%s" % (i+1)`.
- The main menu uses **native Godot focus**, not FocusEmulator.
- An active FocusEmulator (device >= 0, a visible focus base) calls `set_input_as_handled()` for every event it doesn't handle and that isn't a coop UI action, so **mouse motion and clicks never reach the GUI** in coop menus.
- Coop UI code asks `FocusEmulatorSignal.get_player_index(control)` which player focused a control; it is -1 unless an emulator just emitted for that control (0 outside coop runs), and several callers `push_error` on -1 (`popup_manager.gd`, `stat_container.gd`, `secondary_stat_container.gd`, `character_selection.gd`).

## Streamplay
`singletons/streamplay.gd` is Nintendo-only GameShare and has no relevance here. It is a useful model, though, for mapping remote players onto local coop slots.
