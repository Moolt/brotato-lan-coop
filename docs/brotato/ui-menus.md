# UI and menus

## Menu switching
- `ui/menus/menus.gd` (class `Menus`) has **no stack**. `switch(from, to)` calls `to.show(); to.init(); from.hide()` and emits `menu_page_switched`. `back()` and `reset()` return to `_main_menu`.
- `ui/menus/title_screen/title_screen_menus.gd` (`TitleScreenMenus extends Menus`) holds `_menu_credits`, `_menu_mods`, `_profile_scene`, and handlers such as `switch(_main_menu, _menu_mods)`.
  - In `title_screen.tscn`, the `Menus` node is an instance of menus.tscn with this script. Its children are MenuProfile, MainMenu, MenuCredits, and MenuMods.
  - Signals are connected in the .tscn.
- `title_screen.gd` calls `_main_menu.init()`. Its `on_menu_page_switched` toggles `AttenuateBackground`.

## Main menu (`ui/menus/pages/main_menu.gd/.tscn`, class MainMenu)
**Containers**
- `left_container = MarginContainer/VBoxContainer/HBoxContainer/ButtonsLeft` holds Continue, Start, empty_space, Profile, Codex, Options, Quit.
- `right_container = .../ButtonsRight` holds Mods, MoreGames, Newsletter, Community, Credits.

**Buttons**
- Every button is a plain `Button` with script `ui/menus/global/my_menu_button.gd` (class MyMenuButton). The script handles sounds, a short press delay, focus on hover, `activate()`, and `disable()`.
- `text` holds a translation key and is auto-translated.
- Focus neighbours are explicit NodePaths. Quit's bottom neighbour wraps to Start.

**Flow**
- `_on_StartButton_pressed` → `change_scene(MenuData.character_selection_scene)`.
- Page buttons emit signals: `options_button_pressed`, `mods_button_pressed`, and so on.
- `init()` calls `reset_resume_state()` (which runs `CoopService.clear()`) and `setup_menu()`. `setup_menu()` sets focus neighbours and grabs focus on the Start or Continue button.
- On consoles, `setup_console_common` moves buttons by hard-coded child index.

**Page template** (`ui/menus/pages/menu_credits.gd`, `pages/mods/menu_mods.gd`):
```gdscript
signal back_button_pressed
func init() -> void: focus_before_created = get_focus_owner(); _back_button.grab_focus()
func _input(event): if visible and event.is_action_released("ui_cancel"): _on_BackButton_pressed()
func _on_BackButton_pressed(): focus_before_created.grab_focus(); emit_signal("back_button_pressed")
```

## Run selection screens (`ui/menus/run/`)
**`base_selection.gd`** is the common base:
- Per-player inventories `_inventory1-4` and panels `_panel1-4`.
- `_set_base_ui_player_count`.
- `_set_selected_element`: once everyone has selected, it waits 0.8 s and calls `_on_selections_completed`.
- Elements are locked where `not unlocked_elements.has(element.my_id_hash)`.

**`character_selection.gd`**
- `_get_unlocked_elements()` returns `ProgressData.characters_unlocked`. `_get_all_possible_elements()` returns `ItemService.characters`.
- Coop: `init_coop_service()`, `_on_connected_players_updated`, `CoopJoinPanel1-4`.
- `_on_selections_completed` calls `RunData.add_character(c, i)` for each player.

**`weapon_selection.gd`**
- Lists the character's starting weapons that appear in `ProgressData.weapons_unlocked` (~L90).
- On completion: `add_weapon(w, i, true)`, then `add_starting_items_and_weapons()`.

**`difficulty_selection/difficulty_selection.gd`**: only player 0 picks. It sets `RunData.current_difficulty` and applies the difficulty effects to player 0.

## In-wave and between-wave UIs
- **HUD:** `ui/hud/` and `player_ui_elements.gd`. `set_hud_position(i)` assumes 4 corners.
- **Level-up:** `ui/menus/ingame/upgrades_ui.gd`. It is used both solo and as `coop_upgrades_ui.tscn`, and emits `options_processed`.
- **Shop:**
  - `ui/menus/shop/base_shop.gd` is the shared base: rerolls, items, Go button.
  - The Go button leads to `change_scene(main)` (~L346).
  - It keeps per-player arrays of 4.
  - `shop.gd` is the solo shop; `coop_shop.gd` is the coop shop (4 player containers).
- **End run:** `ui/menus/run/end_run.gd` (solo) and `coop_end_run.gd`. Both share the base `base_end_run.gd`.
- **Popups:** `ui/menus/global/popup_manager.gd` (item and stat popups, per player).
- **Pause:** `ui/menus/ingame/pause_menu.gd`.

## Text and translations
- Strings are in `resources/translations/translations.csv` (`key,en,fr,zh,ja,ko,zh_TW,ru,pl,es,pt,de,tr,it`), imported to `.translation` files.
- Keys are UPPER_SNAKE (`MENU_START`, `COOP`). Use them as `Label.text`/`Button.text`, or with `tr("KEY")`.
- `Text.text("KEY", [args])` replaces `{0}`, `{1}` and can add BBCode colours.
- Language changes go through `ProgressData.change_language()`, which emits `language_changed`.
- **Mods:** a CSV in mods-unpacked is not imported at runtime. Build translations in code instead:
  ```gdscript
  var t = Translation.new(); t.locale = "en"; t.add_message("MENU_MULTIPLAYER", "Multiplayer"); TranslationServer.add_translation(t)
  ```
  Alternatively, ship pre-imported `.translation` files and load them with `ModLoaderMod.add_translation(path)`.
