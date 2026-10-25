extends Control

# Title screen page shown while in a LAN session.
# The page takes the screen's height, so Leave, Start and Ready sit at the bottom and the player
# list and both grids get the rest. Left: every player (colour, character, name, weapon,
# ready), the host's Settings button (ui/settings_page.gd over the lobby), a summary of the run
# settings, a status line only when something is going on (run sync, a wave in progress, run
# over), Leave and the host's Start. Right: the local player's
# character and starting weapon grids side by side, each with its preview below, and the Ready
# button; the grids grow so the previews and Ready end level with Start. The grids reuse
# vanilla's Inventory (inventory.tscn). Both previews are vanilla's small item panel
# (item_panel_ui.tscn) without the icon the grid already shows; the character one lists the
# starting weapons and items below, with vanilla's item popup (item_popup.tscn) on hover and
# focus. A preview shows, with the cursor visible, the last hovered entry while the mouse stays
# in that grid or its preview; with the cursor hidden (keyboard, gamepad), the focused entry
# (kept while the focus is on its starting items); else the player's pick.
# Picks are sent to the host (LanNet.set_local_player_info), which validates them and
# re-broadcasts the lobby. Leaving (button or ui_cancel) ends the session; the title screen
# menus then switch back through LanNet.session_ended.

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
const SettingsPage = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/settings_page.gd")
const ModeRegistry = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/mode_registry.gd")

const INVENTORY_SCENE = preload("res://ui/menus/shop/inventory.tscn")
const CHARACTER_PANEL_SCENE = preload("res://ui/menus/ingame/character_panel_ui.tscn")
const ITEM_PANEL_SCENE = preload("res://ui/menus/ingame/item_panel_ui.tscn")
const ITEM_POPUP_SCENE = preload("res://ui/menus/shop/item_popup.tscn")
const RANDOM_ICON = preload("res://items/global/random_icon.png")
const ROW_FONT = preload("res://resources/fonts/actual/base/font_26_outline.tres")

const WIDTH: = 1800.0
# Space above the title and below the buttons.
const PAGE_MARGIN: = 40.0
const PLAYER_LIST_MIN_HEIGHT: = 200.0
const LEFT_WIDTH: = 620.0
const CHARACTER_COLUMN_WIDTH: = 760.0
const GRID_MIN_HEIGHT: = 150.0
const PREVIEW_HEIGHT: = 440.0
const READY_HEIGHT: = 72.0
const COLUMN_SEPARATION: = 12.0
const ELEMENT_SIZE: = Vector2(72, 72)
const STARTING_ITEM_SIZE: = Vector2(56, 56)
const STARTING_ITEM_COLUMNS: = 11
# Name and category of a preview; without the icon box (96 px) the header would collapse.
const PREVIEW_HEADER_HEIGHT: = 64.0
const PREVIEW_DETAILS_MIN_HEIGHT: = 100.0
const ROW_ICON_SIZE: = Vector2(40, 40)
const SELECTED_MARKER_NAME: = "LanSelectedMarker"
const SELECTED_FILL_NAME: = "LanSelectedFill"
const SELECTED_FILL_ALPHA: = 0.45

var _net: Node = null
var _page_column: VBoxContainer
var _address_label: Label
var _count_label: Label
var _player_list: VBoxContainer
var _leave_button: Button
var _settings_label: Label
var _settings_button: Button
# Modes with teams: everyone switches their own team here (the rows show the team colour).
var _team_button: Button
var _settings_page: Control
var _hint_label: Label
var _start_button: Button
var _character_scroll: ScrollContainer
var _character_grid: GridContainer
var _weapon_area: VBoxContainer
var _weapon_grid: GridContainer
var _weapon_scroll: ScrollContainer
var _weapon_label: Label
var _no_choice_label: Label
var _character_panel: Control
var _starting_items: GridContainer
var _starting_item_popup: Control
# Character whose starting items _starting_items holds (refilled only when it changes, so a
# focused starting item survives lobby updates).
var _starting_items_character: ItemParentData = null
var _item_panel: Control
var _ready_button: Button

# Grid elements last hovered (cleared when the mouse leaves the grid and its preview) and with
# the focus, per grid (null if none).
var _hovered_character = null
var _focused_character = null
var _hovered_weapon = null
var _focused_weapon = null
# Whether the cursor was visible at the last preview update (mouse in use, see _uses_focus).
var _mouse_visible: = false

# Character whose starting choices the weapon grid currently shows.
var _weapon_grid_character_id: = ""
# Where to move focus after the host confirmed the next pick: "", "weapons" or "ready".
var _focus_on_update: = ""
# ui_cancel closes an open dropdown on press; only a press with no dropdown open may close the
# settings page or leave.
var _cancel_armed: = false


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	_build_ui()
	_fit_to_screen()
	var _e = get_viewport().connect("size_changed", self, "_fit_to_screen")
	if _net != null:
		_e = _net.connect("lobby_changed", self, "_on_LanNet_lobby_changed")
		_e = _net.connect("run_sync_changed", self, "_on_LanNet_run_sync_changed")


func init() -> void :
	_update_address()
	_settings_page.hide()
	_fill_character_grid()
	_weapon_grid_character_id = "-"
	_refresh()
	_character_grid.focus_element_index(0)


func _input(event: InputEvent) -> void :
	if not visible:
		return
	if (Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE) != _mouse_visible:
		# LanNet shows or hides the cursor in its own _input; update once it has.
		call_deferred("_update_previews")
	if event is InputEventMouseMotion:
		_clear_hover_outside()
	if event.is_action_pressed("ui_cancel"):
		_cancel_armed = not (_settings_page.visible and _settings_page.is_popup_open())
	elif event.is_action_released("ui_cancel") and _cancel_armed:
		_cancel_armed = false
		# Stop the page that becomes visible from handling the same event.
		get_tree().set_input_as_handled()
		if _settings_page.visible:
			_settings_page.close()
		else:
			_on_LeaveButton_pressed()



# UI construction

func _build_ui() -> void :
	_page_column = UiKit.build_page(self, WIDTH, "LAN_LOBBY")
	var columns: = HBoxContainer.new()
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.add_constant_override("separation", 40)
	_page_column.add_child(columns)

	# Left: players
	var left: = VBoxContainer.new()
	left.rect_min_size = Vector2(LEFT_WIDTH, 0)
	left.add_constant_override("separation", 12)
	columns.add_child(left)

	_address_label = Label.new()
	_address_label.autowrap = true
	left.add_child(_address_label)

	_count_label = Label.new()
	left.add_child(_count_label)

	# Takes the height the rest of the left side leaves (12 rows fit on 1080 px); scrolls if not.
	var panel: = PanelContainer.new()
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(panel)
	var player_scroll: = ScrollContainer.new()
	player_scroll.rect_min_size = Vector2(0, PLAYER_LIST_MIN_HEIGHT)
	player_scroll.scroll_horizontal_enabled = false
	panel.add_child(player_scroll)
	_player_list = VBoxContainer.new()
	_player_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_player_list.add_constant_override("separation", 4)
	player_scroll.add_child(_player_list)

	_team_button = UiKit.new_button("LAN_SWITCH_TEAM", Vector2(0, 64))
	var _e = _team_button.connect("pressed", self, "_on_TeamButton_pressed")
	left.add_child(_team_button)

	_settings_button = UiKit.new_button("LAN_SETTINGS", Vector2(0, 64))
	_e = _settings_button.connect("pressed", self, "_on_SettingsButton_pressed")
	left.add_child(_settings_button)

	# Run settings summary (wraps to two lines if long).
	_settings_label = Label.new()
	_settings_label.autowrap = true
	_settings_label.max_lines_visible = 2
	_settings_label.add_font_override("font", ROW_FONT)
	left.add_child(_settings_label)

	_hint_label = Label.new()
	_hint_label.add_font_override("font", ROW_FONT)
	_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	left.add_child(_hint_label)

	var buttons: = HBoxContainer.new()
	buttons.add_constant_override("separation", 16)
	left.add_child(buttons)
	_leave_button = UiKit.new_back_button("LAN_LEAVE")
	_e = _leave_button.connect("pressed", self, "_on_LeaveButton_pressed")
	buttons.add_child(_leave_button)
	_start_button = UiKit.new_button("LAN_START", Vector2(0, 64))
	_start_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_e = _start_button.connect("pressed", self, "_on_StartButton_pressed")
	buttons.add_child(_start_button)

	# Right: the local player's picks, two columns. Character: grid, preview. Weapon: grid,
	# preview, Ready. The grids take the height the previews leave, so the previews and Ready
	# end level with Leave and Start at the bottom.
	var right: = HBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_constant_override("separation", 30)
	columns.add_child(right)

	var character_column: = _new_column(right)
	character_column.rect_min_size = Vector2(CHARACTER_COLUMN_WIDTH, 0)
	var character_label: = Label.new()
	character_label.text = "LAN_CHOOSE_CHARACTER"
	character_column.add_child(character_label)

	_character_scroll = ScrollContainer.new()
	_character_scroll.rect_min_size = Vector2(0, GRID_MIN_HEIGHT)
	_character_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_character_scroll.scroll_horizontal_enabled = false
	_character_scroll.follow_focus = true
	character_column.add_child(_character_scroll)
	_character_grid = _new_inventory(9)
	_character_scroll.add_child(_character_grid)
	_e = _character_grid.connect("element_pressed", self, "_on_CharacterGrid_element_pressed")
	_e = _character_grid.connect("element_focused", self, "_on_CharacterGrid_element_focused")
	_e = _character_grid.connect("element_unfocused", self, "_on_CharacterGrid_element_unfocused")
	_e = _character_grid.connect("element_hovered", self, "_on_CharacterGrid_element_hovered")

	_character_panel = _new_preview_panel(character_column, Vector2(CHARACTER_COLUMN_WIDTH, PREVIEW_HEIGHT))
	# The starting weapons and items, with vanilla's item popup on hover and focus.
	_starting_items = _new_inventory(STARTING_ITEM_COLUMNS)
	_starting_items.element_size = STARTING_ITEM_SIZE
	# Elements are Buttons: with the page theme's font, an empty one is 68 px high and the row
	# would stretch the 56 px icons.
	var small_theme: = Theme.new()
	small_theme.set_font("font", "Button", ROW_FONT)
	_starting_items.theme = small_theme
	_character_panel.get_node("MarginContainer/VBoxContainer").add_child(_starting_items)
	_e = _starting_items.connect("element_hovered", self, "_on_StartingItems_element_shown")
	_e = _starting_items.connect("element_focused", self, "_on_StartingItems_element_shown")
	_e = _starting_items.connect("element_pressed", self, "_on_StartingItems_element_shown")
	_e = _starting_items.connect("element_unhovered", self, "_on_StartingItems_element_unhovered")
	_e = _starting_items.connect("element_unfocused", self, "_on_StartingItems_element_unfocused")

	var weapon_column: = _new_column(right)
	weapon_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_weapon_label = Label.new()
	_weapon_label.text = "LAN_CHOOSE_WEAPON"
	weapon_column.add_child(_weapon_label)

	# The grid or the no-choice text, in the same space, so the preview never moves.
	_weapon_area = VBoxContainer.new()
	_weapon_area.rect_min_size = Vector2(0, GRID_MIN_HEIGHT)
	_weapon_area.size_flags_vertical = SIZE_EXPAND_FILL
	weapon_column.add_child(_weapon_area)
	_weapon_scroll = ScrollContainer.new()
	_weapon_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_weapon_scroll.scroll_horizontal_enabled = false
	_weapon_scroll.follow_focus = true
	_weapon_area.add_child(_weapon_scroll)
	_weapon_grid = _new_inventory(4)
	_weapon_scroll.add_child(_weapon_grid)
	_e = _weapon_grid.connect("element_pressed", self, "_on_WeaponGrid_element_pressed")
	_e = _weapon_grid.connect("element_focused", self, "_on_WeaponGrid_element_focused")
	_e = _weapon_grid.connect("element_unfocused", self, "_on_WeaponGrid_element_unfocused")
	_e = _weapon_grid.connect("element_hovered", self, "_on_WeaponGrid_element_hovered")

	_no_choice_label = Label.new()
	_no_choice_label.autowrap = true
	_no_choice_label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	_weapon_area.add_child(_no_choice_label)

	# Preview and Ready together as tall as the character preview.
	_item_panel = _new_preview_panel(weapon_column, Vector2(0, PREVIEW_HEIGHT - READY_HEIGHT - COLUMN_SEPARATION))
	_ready_button = UiKit.new_button("LAN_READY", Vector2(0, READY_HEIGHT))
	_e = _ready_button.connect("pressed", self, "_on_ReadyButton_pressed")
	weapon_column.add_child(_ready_button)

	# Last children, so they draw over the page.
	_starting_item_popup = ITEM_POPUP_SCENE.instance()
	add_child(_starting_item_popup)
	_starting_item_popup.hide()
	_settings_page = SettingsPage.new()
	add_child(_settings_page)
	_e = _settings_page.connect("closed", self, "_on_SettingsPage_closed")


# The page's column from below the top margin to above the bottom one (the page centres it).
func _fit_to_screen() -> void :
	_page_column.rect_min_size.y = get_viewport_rect().size.y - 2 * PAGE_MARGIN


func _new_column(parent: Control) -> VBoxContainer:
	var column: = VBoxContainer.new()
	column.add_constant_override("separation", COLUMN_SEPARATION)
	parent.add_child(column)
	return column


# Vanilla's small item panel in a holder of a fixed size (the panel hides while there is nothing
# to show), without the icon box: the grid above shows the icon already. The description scrolls
# within the panel (expand_indefinitely, read in the description's _ready) and takes the height
# the panel leaves, instead of vanilla's fixed one.
func _new_preview_panel(parent: Control, min_size: Vector2) -> Control:
	var holder: = Control.new()
	holder.rect_min_size = min_size
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var panel: Control = ITEM_PANEL_SCENE.instance()
	var description: Node = panel.get_node("MarginContainer/VBoxContainer/ItemDescription")
	description.expand_indefinitely = false
	description.get_node("HBoxContainer/IconPanel").hide()
	description.get_node("HBoxContainer/ScrollContainer").rect_min_size.y = PREVIEW_HEADER_HEIGHT
	description.size_flags_vertical = SIZE_EXPAND_FILL
	var details: Control = description.get_node("ScrollContainer")
	details.rect_min_size.y = PREVIEW_DETAILS_MIN_HEIGHT
	details.size_flags_vertical = SIZE_EXPAND_FILL
	panel.set_anchors_and_margins_preset(PRESET_WIDE)
	panel.hide()
	holder.add_child(panel)
	return panel


func _new_inventory(columns: int) -> GridContainer:
	var inventory: GridContainer = INVENTORY_SCENE.instance()
	inventory.element_size = ELEMENT_SIZE
	inventory.columns = columns
	return inventory



# Grids

func _fill_character_grid() -> void :
	var elements: = []
	for character in ItemService.characters:
		var element = character.duplicate()
		element.is_locked = not LobbyRules.is_character_unlocked(character)
		elements.append(element)
	_character_grid.clear_elements()
	_character_grid.add_special_element(RANDOM_ICON, true)
	_character_grid.set_elements(elements, false, false)


func _fill_weapon_grid(character: CharacterData) -> void :
	var choices: = LobbyRules.get_starting_choices(character)
	_hovered_weapon = null
	_focused_weapon = null
	_weapon_grid.clear_elements()
	if choices.size() > 1:
		_weapon_grid.add_special_element(RANDOM_ICON, true)
	if not choices.empty():
		_weapon_grid.set_elements(choices, false, false)

	_weapon_scroll.visible = not choices.empty()
	_weapon_scroll.scroll_vertical = 0
	_weapon_label.visible = character == null or not choices.empty()
	_no_choice_label.visible = character == null or choices.empty()
	_no_choice_label.text = "LAN_PICK_CHARACTER_FIRST" if character == null else "LAN_NO_STARTING_CHOICE"



# Content

func _refresh() -> void :
	if _net == null:
		return
	_refresh_players()
	_refresh_settings()

	var me = _net.get_local_player()
	if me == null:
		return
	if me.character_id != _weapon_grid_character_id:
		_weapon_grid_character_id = me.character_id
		_fill_weapon_grid(LobbyRules.get_character(me.character_id))

	_update_selection(me)
	_update_previews()

	var can_ready: bool = me.ready or LobbyRules.is_entry_complete(me)
	_ready_button.text = "LAN_UNREADY" if me.ready else "LAN_READY"
	if can_ready:
		_ready_button.activate()
	else:
		_ready_button.disable()

	var focus_target: = _focus_on_update
	_focus_on_update = ""
	if focus_target == "weapons" and _weapon_scroll.visible and _weapon_grid.get_child_count() > 0:
		_weapon_grid.focus_element_index(0)
	elif focus_target != "" and can_ready:
		_ready_button.call_deferred("grab_focus")


func _refresh_settings() -> void :
	var is_host: bool = _net.is_host
	_start_button.visible = is_host
	_settings_button.visible = is_host
	_team_button.visible = ModeRegistry.uses_teams(_net.lobby_settings.get("mode", NetProtocol.DEFAULT_MODE))
	if _net.run_in_progress or _net.lobby_settings.get("in_wave", false):
		_team_button.disable()
	else:
		_team_button.activate()
	if not is_host:
		_settings_page.close()
	_settings_label.text = SettingsPage.get_summary(_net.lobby_settings)
	if _settings_page.visible:
		_settings_page.refresh()

	var all_ready: bool = _net.are_all_ready()
	if is_host:
		if all_ready:
			_start_button.activate()
		else:
			_start_button.disable()

	var sync: Dictionary = _net.get_run_sync_status()
	var names: = PoolStringArray(sync.names).join(", ")
	_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	if not is_host and _net.lobby_settings.get("in_wave", false):
		var run_over: bool = _net.run_over or _net.lobby_settings.get("run_over", false)
		_hint_label.text = "LAN_HINT_HOST_RESULTS" if run_over else "LAN_HINT_HOST_IN_WAVE"
	elif sync.state == "synced":
		_hint_label.text = tr("LAN_RUN_SYNCED").replace("{0}", str(_net.get_player_count()))
		_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_OK)
	elif sync.state == "pending":
		_hint_label.text = tr("LAN_RUN_PENDING").replace("{0}", names) if is_host else tr("LAN_RUN_RECEIVING")
	elif sync.state == "failed":
		_hint_label.text = tr("LAN_RUN_FAILED").replace("{0}", names) if is_host else tr("LAN_RUN_FAILED_CLIENT")
		_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_ERROR)
	else:
		# Waiting for picks or for Start: the player list and Start already show it.
		_hint_label.text = ""
	_hint_label.visible = not _hint_label.text.empty()


# Marks the picked character and weapon, and makes "left" from the weapon grid's first column
# and from Ready (and "up" from Ready, when there are no weapons) return to the picked character
# instead of the nearest one.
func _update_selection(me: Dictionary) -> void :
	var color: = UiKit.get_player_color(me.player_index)
	var character_element: = _mark_selected(_character_grid, me.character_id, color)
	var _weapon_element: = _mark_selected(_weapon_grid, me.weapon_id, color)

	_weapon_grid.set_neighbour_left = character_element != null
	_weapon_grid.focus_neighbour_left = _weapon_grid.get_path_to(character_element) if character_element != null else NodePath("")
	_weapon_grid.queue_set_focus_neighbours()
	var ready_left: = NodePath("")
	var ready_up: = NodePath("")
	if character_element != null:
		ready_left = _ready_button.get_path_to(character_element)
		if not _weapon_scroll.visible:
			ready_up = ready_left
	_ready_button.focus_neighbour_left = ready_left
	_ready_button.focus_neighbour_top = ready_up


# Adds a border in the player's colour to the element whose item has item_id, removes it
# from the others. Returns the marked element or null.
func _mark_selected(grid: Control, item_id: String, color: Color) -> Control:
	var marked: Control = null
	for element in grid.get_children():
		var is_selected: bool = not item_id.empty() and not element.is_special and element.item != null and element.item.my_id == item_id
		var marker = element.get_node_or_null(SELECTED_MARKER_NAME)
		if is_selected and marker == null:
			# The fill behind the icon, the border over everything (the element's frame too).
			var fill: = _new_marker_panel(SELECTED_FILL_NAME, Color(color.r, color.g, color.b, SELECTED_FILL_ALPHA), Color.transparent)
			element.add_child(fill)
			element.move_child(fill, 0)
			element.add_child(_new_marker_panel(SELECTED_MARKER_NAME, Color.transparent, color))
		elif not is_selected and marker != null:
			for node_name in [SELECTED_MARKER_NAME, SELECTED_FILL_NAME]:
				var node = element.get_node_or_null(node_name)
				if node != null:
					element.remove_child(node)
					node.queue_free()
		if is_selected:
			marked = element
	return marked


# As vanilla's coop selection: a half transparent background and a border in the player's colour.
func _new_marker_panel(node_name: String, fill: Color, border: Color) -> Control:
	var style: = StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = fill.a > 0.0
	style.border_color = border
	style.set_border_width_all(5 if border.a > 0.0 else 0)
	style.set_corner_radius_all(6)
	var marker: = Panel.new()
	marker.name = node_name
	marker.mouse_filter = MOUSE_FILTER_IGNORE
	marker.add_stylebox_override("panel", style)
	marker.set_anchors_and_margins_preset(PRESET_WIDE)
	return marker


# Previews

# Not while the page leaves the tree (scene change): the focused grid element reports losing the
# focus after the panels' nodes have left, and filling them then fails in vanilla's EffectLine.
func _update_previews() -> void :
	if not _character_panel.is_inside_tree() or not _item_panel.is_inside_tree():
		return
	_mouse_visible = Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
	var me = _net.get_local_player() if _net != null else null
	var character = LobbyRules.get_character(me.character_id) if me != null else null
	var weapon = LobbyRules.get_starting_choice(character, me.weapon_id) if me != null else null
	_show_preview(_character_panel, _get_preview_element(_hovered_character, _focused_character), character)
	_show_preview(_item_panel, _get_preview_element(_hovered_weapon, _focused_weapon), weapon)


# With the cursor visible, the hovered element; with it hidden (keyboard or gamepad), the focused
# one (with the mouse, focus stays where a pick moved it); else null.
func _get_preview_element(hovered, focused):
	var element = hovered if _mouse_visible else focused
	if element != null and is_instance_valid(element):
		return element
	return null


# Ends a hover once the mouse leaves the grid and its preview, so the mouse can move from a
# character to its starting items without the preview switching back to the pick.
func _clear_hover_outside() -> void :
	var changed: = false
	if _hovered_character != null and not _has_mouse(_character_scroll) and not _has_mouse(_character_panel.get_parent()):
		_hovered_character = null
		changed = true
	if _hovered_weapon != null and not _has_mouse(_weapon_area) and not _has_mouse(_item_panel.get_parent()):
		_hovered_weapon = null
		changed = true
	if changed:
		_update_previews()


func _has_mouse(control: Control) -> bool:
	return control.is_visible_in_tree() and control.get_global_rect().has_point(control.get_global_mouse_position())


# Drops the focused character once the focus is neither on the character grid nor on the
# starting items (deferred: while focus moves, the old element reports the loss first).
func _check_character_focus() -> void :
	if not is_inside_tree() or _focused_character == null:
		return
	var focus_owner: = get_focus_owner()
	if focus_owner != null and (_character_grid.is_a_parent_of(focus_owner) or _starting_items.is_a_parent_of(focus_owner)):
		return
	_focused_character = null
	_update_previews()


func _show_preview(panel: Control, element, selected: ItemParentData) -> void :
	var data: ItemParentData = selected
	if element != null and element.is_random:
		panel.show()
		panel._show_random()
		if panel == _character_panel:
			_fill_starting_items(null)
		return
	if element != null and element.item != null:
		data = element.item
	panel.visible = data != null
	if data == null:
		return
	panel.set_data(data, 0)
	if panel == _character_panel:
		_fill_starting_items(data)


# The character's starting weapons and items, as vanilla's character panel lists them.
func _fill_starting_items(character: ItemParentData) -> void :
	if character == _starting_items_character:
		return
	_starting_items_character = character
	_starting_item_popup.hide()
	_starting_items.clear_elements()
	if character == null:
		return
	var items: = []
	for effect in character.effects:
		var item: ItemParentData = null
		if effect.custom_key_hash == Keys.starting_weapon_hash or effect.custom_key_hash == Keys.cursed_starting_weapon_hash:
			item = ItemService.get_element(ItemService.weapons, effect.key_hash)
		elif effect.custom_key_hash == Keys.starting_item_hash or effect.custom_key_hash == Keys.cursed_starting_item_hash:
			item = ItemService.get_element(ItemService.items, effect.key_hash)
		if item != null:
			items.append(item)
	_starting_items.set_elements(items, false, false)



func _update_address() -> void :
	if _net == null or not _net.is_host:
		_address_label.text = ""
		_address_label.hide()
		return
	var address: = NetProtocol.get_primary_lan_address()
	if address.empty():
		address = "127.0.0.1"
	_address_label.text = tr("LAN_JOIN_ADDRESS").replace("{0}", address + ":" + str(_net.config.port))
	_address_label.show()


func _refresh_players() -> void :
	for child in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()

	_count_label.text = tr("LAN_PLAYER_COUNT").replace("{0}", str(_net.get_player_count())).replace("{1}", str(NetProtocol.MAX_PLAYERS))
	if not ModeRegistry.uses_teams(_net.lobby_settings.get("mode", NetProtocol.DEFAULT_MODE)):
		for entry in _net.players:
			_player_list.add_child(_new_player_row(entry))
		return
	# Modes with teams: each team under its name, in its colour (players by index within it). A
	# click on the name joins that team (mouse only; gamepads have the Switch team button).
	var can_switch: bool = not _net.run_in_progress and not _net.lobby_settings.get("in_wave", false)
	for team in NetProtocol.TEAM_COUNT:
		var color: Color = ModeRegistry.TEAM_COLORS[team % ModeRegistry.TEAM_COLORS.size()]
		var header: = Button.new()
		header.flat = true
		header.focus_mode = Control.FOCUS_NONE
		header.align = Button.ALIGN_LEFT
		var members: = 0
		for entry in _net.players:
			if int(entry.get("team", 0)) % NetProtocol.TEAM_COUNT == team:
				members += 1
		header.text = "%s (%d)" % [tr(ModeRegistry.TEAM_NAMES[team]), members]
		header.disabled = not can_switch
		header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_switch else Control.CURSOR_ARROW
		header.add_font_override("font", ROW_FONT)
		for state in ["font_color", "font_color_pressed", "font_color_disabled"]:
			header.add_color_override(state, color)
		header.add_color_override("font_color_hover", color.lightened(0.4))
		# No padding: the name lines up with the rows below.
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			header.add_stylebox_override(style, StyleBoxEmpty.new())
		var _e = header.connect("pressed", self, "_on_TeamHeader_pressed", [team])
		_player_list.add_child(header)
		for entry in _net.players:
			if int(entry.get("team", 0)) % NetProtocol.TEAM_COUNT == team:
				_player_list.add_child(_new_player_row(entry))


func _new_player_row(entry: Dictionary) -> Control:
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 10)

	var swatch: = ColorRect.new()
	swatch.rect_min_size = Vector2(8, ROW_ICON_SIZE.y)
	swatch.color = UiKit.get_player_color(entry.player_index)
	row.add_child(swatch)

	var character: = LobbyRules.get_character(entry.character_id)
	row.add_child(_new_row_icon(character.get_icon() if character != null else null))

	var name_label: = Label.new()
	var text: String = entry.name
	if entry.player_index == 0:
		text += "  " + tr("LAN_TAG_HOST")
	if entry.player_index == _net.local_player_index:
		text += "  " + tr("LAN_TAG_YOU")
	if not entry.connected:
		text += "  " + tr("LAN_TAG_DISCONNECTED")
	name_label.text = text
	name_label.add_font_override("font", ROW_FONT)
	name_label.clip_text = true
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.valign = Label.VALIGN_CENTER
	name_label.size_flags_vertical = SIZE_FILL
	row.add_child(name_label)

	var choice = LobbyRules.get_starting_choice(character, entry.weapon_id)
	row.add_child(_new_row_icon(choice.get_icon() if choice != null else null))

	var status: = Label.new()
	status.rect_min_size = Vector2(150, 0)
	status.align = Label.ALIGN_RIGHT
	status.valign = Label.VALIGN_CENTER
	status.size_flags_vertical = SIZE_FILL
	status.text = "LAN_STATUS_READY" if entry.ready else "LAN_STATUS_CHOOSING"
	status.add_font_override("font", ROW_FONT)
	status.add_color_override("font_color", UiKit.STATUS_COLOR_OK if entry.ready else UiKit.STATUS_COLOR_MUTED)
	row.add_child(status)
	return row


func _new_row_icon(texture: Texture) -> TextureRect:
	var icon: = TextureRect.new()
	icon.rect_min_size = ROW_ICON_SIZE
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
	return icon



# Signals

func _on_LanNet_lobby_changed() -> void :
	if visible:
		_refresh()


func _on_LanNet_run_sync_changed() -> void :
	if visible:
		_refresh_settings()


func _on_CharacterGrid_element_focused(element) -> void :
	_focused_character = element
	_update_previews()


func _on_CharacterGrid_element_unfocused(_element) -> void :
	call_deferred("_check_character_focus")


func _on_CharacterGrid_element_hovered(element) -> void :
	_hovered_character = element
	_update_previews()


# Without the last-wave line vanilla adds for inventory elements (it reads run data).
func _on_StartingItems_element_shown(element) -> void :
	if element.item == null:
		return
	_starting_item_popup.set_synergies_visible(false)
	_starting_item_popup.display_item_data(element.item, element)


func _on_StartingItems_element_unhovered(_element) -> void :
	_starting_item_popup.hide()


func _on_StartingItems_element_unfocused(_element) -> void :
	_starting_item_popup.hide()
	call_deferred("_check_character_focus")


func _on_CharacterGrid_element_pressed(element) -> void :
	var character_id: = ""
	if element.is_random:
		var unlocked: = LobbyRules.get_unlocked_characters()
		if unlocked.empty():
			return
		character_id = Utils.get_rand_element(unlocked).my_id
	elif element.is_special:
		return
	else:
		character_id = element.item.my_id

	_focus_on_update = "weapons"
	_net.set_local_player_info({"character_id": character_id})


func _on_WeaponGrid_element_focused(element) -> void :
	_focused_weapon = element
	_update_previews()


func _on_WeaponGrid_element_unfocused(element) -> void :
	if _focused_weapon == element:
		_focused_weapon = null
		_update_previews()


func _on_WeaponGrid_element_hovered(element) -> void :
	_hovered_weapon = element
	_update_previews()


func _on_WeaponGrid_element_pressed(element) -> void :
	var me = _net.get_local_player()
	if me == null:
		return
	var choice_id: = ""
	if element.is_random:
		var choices: = LobbyRules.get_starting_choices(LobbyRules.get_character(me.character_id))
		if choices.empty():
			return
		choice_id = Utils.get_rand_element(choices).my_id
	elif element.is_special:
		return
	else:
		choice_id = element.item.my_id

	_focus_on_update = "ready"
	_net.set_local_player_info({"weapon_id": choice_id})


func _on_SettingsButton_pressed() -> void :
	_settings_page.open(_net)


func _on_SettingsPage_closed() -> void :
	_settings_button.grab_focus()


# Builds the run and syncs it to every client. Once all of them hold it, LanNet loads the wave
# on the host; until Step 6 the clients stay in the lobby.
func _on_StartButton_pressed() -> void :
	var _err = _net.start_run()


func _on_TeamButton_pressed() -> void :
	var me = _net.get_local_player()
	if me != null:
		_net.set_local_player_info({"team": (int(me.get("team", 0)) + 1) % NetProtocol.TEAM_COUNT})


func _on_TeamHeader_pressed(team: int) -> void :
	var me = _net.get_local_player()
	if me != null and int(me.get("team", 0)) != team:
		_net.set_local_player_info({"team": team})


func _on_ReadyButton_pressed() -> void :
	var me = _net.get_local_player()
	if me != null:
		_net.set_local_player_info({"ready": not me.ready})


func _on_LeaveButton_pressed() -> void :
	if _net != null:
		_net.leave()
