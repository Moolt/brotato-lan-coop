extends Control

# Title screen page shown while in a LAN session.
# Left: every player (colour, character, name, weapon, ready), the run settings (host: zone and
# difficulty pickers, clients: a summary), Leave and the host's Start. Right: the local player's
# character grid, info panel, starting weapon grid and Ready button. The grids reuse vanilla's
# Inventory (inventory.tscn) and the info panels the ones from the run selection screens.
# Picks are sent to the host (LanNet.set_local_player_info), which validates them and
# re-broadcasts the lobby. Leaving (button or ui_cancel) ends the session; the title screen
# menus then switch back through LanNet.session_ended.

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")

const INVENTORY_SCENE = preload("res://ui/menus/shop/inventory.tscn")
const CHARACTER_PANEL_SCENE = preload("res://ui/menus/ingame/character_panel_ui.tscn")
const ITEM_PANEL_SCENE = preload("res://ui/menus/ingame/item_panel_ui.tscn")
const RANDOM_ICON = preload("res://items/global/random_icon.png")
const ROW_FONT = preload("res://resources/fonts/actual/base/font_26_outline.tres")
const OPTION_THEME = preload("res://resources/themes/zone_selection_button_theme.tres")

const WIDTH: = 1800.0
const LEFT_WIDTH: = 660.0
const ELEMENT_SIZE: = Vector2(72, 72)
const ROW_ICON_SIZE: = Vector2(40, 40)
const SELECTED_MARKER_NAME: = "LanSelectedMarker"

var _net: Node = null
var _address_label: Label
var _count_label: Label
var _player_list: VBoxContainer
var _leave_button: Button
var _zone_option: OptionButton
var _difficulty_option: OptionButton
var _settings_label: Label
var _hint_label: Label
var _start_button: Button
var _character_grid: GridContainer
var _weapon_grid: GridContainer
var _weapon_scroll: ScrollContainer
var _weapon_label: Label
var _no_choice_label: Label
var _character_panel: Control
var _item_panel: Control
var _ready_button: Button

# Character whose starting choices the weapon grid currently shows.
var _weapon_grid_character_id: = ""
# Where to move focus after the host confirmed the next pick: "", "weapons" or "ready".
var _focus_on_update: = ""
# ui_cancel closes an open dropdown on press; only a press with no dropdown open may leave.
var _cancel_armed: = false


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	_build_ui()
	if _net != null:
		var _e = _net.connect("lobby_changed", self, "_on_LanNet_lobby_changed")
		_e = _net.connect("run_sync_changed", self, "_on_LanNet_run_sync_changed")


func init() -> void :
	_update_address()
	_fill_setting_options()
	_fill_character_grid()
	_weapon_grid_character_id = "-"
	_refresh()
	_character_grid.focus_element_index(0)


func _input(event: InputEvent) -> void :
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_armed = not (_zone_option.get_popup().visible or _difficulty_option.get_popup().visible)
	elif event.is_action_released("ui_cancel") and _cancel_armed:
		_cancel_armed = false
		# Stop the page that becomes visible from handling the same event.
		get_tree().set_input_as_handled()
		_on_LeaveButton_pressed()



# UI construction

func _build_ui() -> void :
	var column: = UiKit.build_page(self, WIDTH, "LAN_LOBBY")
	var columns: = HBoxContainer.new()
	columns.add_constant_override("separation", 40)
	column.add_child(columns)

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

	# Fits 12 rows; scrolls if rows ever get taller.
	var panel: = PanelContainer.new()
	left.add_child(panel)
	var player_scroll: = ScrollContainer.new()
	player_scroll.rect_min_size = Vector2(0, 540)
	player_scroll.scroll_horizontal_enabled = false
	panel.add_child(player_scroll)
	_player_list = VBoxContainer.new()
	_player_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_player_list.add_constant_override("separation", 4)
	player_scroll.add_child(_player_list)

	# Run settings: pickers for the host, a summary line for clients.
	var settings_row: = HBoxContainer.new()
	settings_row.add_constant_override("separation", 16)
	left.add_child(settings_row)
	_zone_option = _new_option_button()
	settings_row.add_child(_zone_option)
	var _e = _zone_option.connect("item_selected", self, "_on_ZoneOption_item_selected")
	_difficulty_option = _new_option_button()
	settings_row.add_child(_difficulty_option)
	_e = _difficulty_option.connect("item_selected", self, "_on_DifficultyOption_item_selected")
	_settings_label = Label.new()
	_settings_label.rect_min_size = Vector2(0, 56)
	_settings_label.valign = Label.VALIGN_CENTER
	settings_row.add_child(_settings_label)

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

	# Right: the local player's picks
	var right: = VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_constant_override("separation", 12)
	columns.add_child(right)

	var character_label: = Label.new()
	character_label.text = "LAN_CHOOSE_CHARACTER"
	right.add_child(character_label)

	var character_scroll: = ScrollContainer.new()
	character_scroll.rect_min_size = Vector2(0, 250)
	character_scroll.scroll_horizontal_enabled = false
	character_scroll.follow_focus = true
	right.add_child(character_scroll)
	_character_grid = _new_inventory(13)
	character_scroll.add_child(_character_grid)
	_e = _character_grid.connect("element_pressed", self, "_on_CharacterGrid_element_pressed")
	_e = _character_grid.connect("element_focused", self, "_on_CharacterGrid_element_focused")
	_e = _character_grid.connect("element_hovered", self, "_on_CharacterGrid_element_focused")

	var bottom: = HBoxContainer.new()
	bottom.add_constant_override("separation", 24)
	right.add_child(bottom)

	var info: = Control.new()
	info.rect_min_size = Vector2(760, 480)
	bottom.add_child(info)
	_character_panel = CHARACTER_PANEL_SCENE.instance()
	_character_panel.set_anchors_and_margins_preset(PRESET_WIDE)
	_character_panel.hide()
	info.add_child(_character_panel)
	_item_panel = ITEM_PANEL_SCENE.instance()
	_item_panel.set_anchors_and_margins_preset(PRESET_WIDE)
	_item_panel.hide()
	info.add_child(_item_panel)

	var weapon_column: = VBoxContainer.new()
	weapon_column.size_flags_horizontal = SIZE_EXPAND_FILL
	weapon_column.add_constant_override("separation", 12)
	bottom.add_child(weapon_column)

	_weapon_label = Label.new()
	_weapon_label.text = "LAN_CHOOSE_WEAPON"
	weapon_column.add_child(_weapon_label)

	# Fixed height (fits inside the info panel's height) so the page never changes size.
	_weapon_scroll = ScrollContainer.new()
	_weapon_scroll.rect_min_size = Vector2(0, 320)
	_weapon_scroll.scroll_horizontal_enabled = false
	_weapon_scroll.follow_focus = true
	weapon_column.add_child(_weapon_scroll)
	_weapon_grid = _new_inventory(3)
	_weapon_scroll.add_child(_weapon_grid)
	_e = _weapon_grid.connect("element_pressed", self, "_on_WeaponGrid_element_pressed")
	_e = _weapon_grid.connect("element_focused", self, "_on_WeaponGrid_element_focused")
	_e = _weapon_grid.connect("element_hovered", self, "_on_WeaponGrid_element_focused")

	_no_choice_label = Label.new()
	_no_choice_label.autowrap = true
	_no_choice_label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	weapon_column.add_child(_no_choice_label)

	var spacer: = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	weapon_column.add_child(spacer)

	_ready_button = UiKit.new_button("LAN_READY", Vector2(0, 72))
	_e = _ready_button.connect("pressed", self, "_on_ReadyButton_pressed")
	weapon_column.add_child(_ready_button)


func _new_option_button() -> OptionButton:
	var option: = OptionButton.new()
	option.theme = OPTION_THEME
	option.rect_min_size = Vector2(0, 56)
	option.size_flags_horizontal = SIZE_EXPAND_FILL
	return option


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



func _fill_setting_options() -> void :
	_zone_option.clear()
	for zone in ZoneService.zones:
		_zone_option.add_item(tr(zone.name), zone.my_id)
	_difficulty_option.clear()
	for difficulty in ItemService.difficulties:
		_difficulty_option.add_item(difficulty.get_name_text(), difficulty.value)



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
	_zone_option.visible = is_host
	_difficulty_option.visible = is_host
	_settings_label.visible = not is_host
	_start_button.visible = is_host

	var zone_id: int = _net.lobby_settings.get("zone", 0)
	var difficulty_value: int = _net.lobby_settings.get("difficulty", 0)
	if is_host:
		# select() doesn't emit item_selected, so this never loops back.
		_zone_option.select(_zone_option.get_item_index(zone_id))
		_difficulty_option.select(_difficulty_option.get_item_index(difficulty_value))
	else:
		var zone: = LobbyRules.get_zone(zone_id)
		var difficulty: = LobbyRules.get_difficulty(difficulty_value)
		_settings_label.text = tr("LAN_SETTINGS_SUMMARY") \
				.replace("{0}", tr(zone.name) if zone != null else "?") \
				.replace("{1}", difficulty.get_name_text() if difficulty != null else "?")

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
		_hint_label.text = "LAN_HINT_HOST_RESULTS" if _net.run_over else "LAN_HINT_HOST_IN_WAVE"
	elif sync.state == "synced":
		_hint_label.text = tr("LAN_RUN_SYNCED").replace("{0}", str(_net.get_player_count()))
		_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_OK)
	elif sync.state == "pending":
		_hint_label.text = tr("LAN_RUN_PENDING").replace("{0}", names) if is_host else tr("LAN_RUN_RECEIVING")
	elif sync.state == "failed":
		_hint_label.text = tr("LAN_RUN_FAILED").replace("{0}", names) if is_host else tr("LAN_RUN_FAILED_CLIENT")
		_hint_label.add_color_override("font_color", UiKit.STATUS_COLOR_ERROR)
	elif not all_ready:
		_hint_label.text = "LAN_HINT_WAITING"
	elif is_host:
		_hint_label.text = "LAN_HINT_HOST_CAN_START"
	else:
		_hint_label.text = "LAN_HINT_CLIENT_WAIT_START"


# Marks the picked character and weapon, and makes "up" from the weapon grid (or from Ready,
# when there are no weapons) return to the picked character instead of the grid's bottom row.
func _update_selection(me: Dictionary) -> void :
	var color: = UiKit.get_player_color(me.player_index)
	var character_element: = _mark_selected(_character_grid, me.character_id, color)
	var _weapon_element: = _mark_selected(_weapon_grid, me.weapon_id, color)

	_weapon_grid.set_neighbour_top = character_element != null
	_weapon_grid.focus_neighbour_top = _weapon_grid.get_path_to(character_element) if character_element != null else NodePath("")
	_weapon_grid.queue_set_focus_neighbours()
	var ready_up: = NodePath("")
	if character_element != null and not _weapon_scroll.visible:
		ready_up = _ready_button.get_path_to(character_element)
	_ready_button.focus_neighbour_top = ready_up


# Adds a border in the player's colour to the element whose item has item_id, removes it
# from the others. Returns the marked element or null.
func _mark_selected(grid: Control, item_id: String, color: Color) -> Control:
	var marked: Control = null
	for element in grid.get_children():
		var is_selected: bool = not item_id.empty() and not element.is_special and element.item != null and element.item.my_id == item_id
		var marker = element.get_node_or_null(SELECTED_MARKER_NAME)
		if is_selected and marker == null:
			element.add_child(_new_selected_marker(color))
		elif not is_selected and marker != null:
			element.remove_child(marker)
			marker.queue_free()
		if is_selected:
			marked = element
	return marked


func _new_selected_marker(color: Color) -> Control:
	var style: = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(5)
	style.set_corner_radius_all(6)
	var marker: = Panel.new()
	marker.name = SELECTED_MARKER_NAME
	marker.mouse_filter = MOUSE_FILTER_IGNORE
	marker.add_stylebox_override("panel", style)
	marker.set_anchors_and_margins_preset(PRESET_WIDE)
	return marker


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
	for entry in _net.players:
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
	_item_panel.hide()
	_character_panel.show()
	if element.is_random:
		_character_panel._show_random()
	elif element.item != null:
		_character_panel.set_data(element.item, 0)


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
	_character_panel.hide()
	_item_panel.show()
	if element.is_random:
		_item_panel._show_random()
	elif element.item != null:
		_item_panel.set_data(element.item, 0)


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


func _on_ZoneOption_item_selected(index: int) -> void :
	_net.set_lobby_settings({"zone": _zone_option.get_item_id(index)})


func _on_DifficultyOption_item_selected(index: int) -> void :
	_net.set_lobby_settings({"difficulty": _difficulty_option.get_item_id(index)})


# Builds the run and syncs it to every client. Once all of them hold it, LanNet loads the wave
# on the host; until Step 6 the clients stay in the lobby.
func _on_StartButton_pressed() -> void :
	var _err = _net.start_run()


func _on_ReadyButton_pressed() -> void :
	var me = _net.get_local_player()
	if me != null:
		_net.set_local_player_info({"ready": not me.ready})


func _on_LeaveButton_pressed() -> void :
	if _net != null:
		_net.leave()
