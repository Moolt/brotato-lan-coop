extends Control

# Title screen page: player name, host IP, port, Host / Join / Back.
# Follows the menu_credits.gd page pattern (init, ui_cancel, back_button_pressed).
# The UI is built in code. A digit pad lets gamepad-only players enter the IP (or port).

signal back_button_pressed
signal lobby_requested

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const TITLE_FONT = preload("res://resources/fonts/actual/base/font_60_outline.tres")
const BACK_ICON = preload("res://ui/menus/global/arrow_left_border.png")

const PAD_KEYS: = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
const STATUS_COLOR_ERROR: = Color(1, 0.45, 0.45)
const STATUS_COLOR_INFO: = Color(1, 1, 1)

var _net: Node = null
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _pad_target: LineEdit
var _pad_buttons: = []
var _host_button: Button
var _join_button: Button
var _back_button: Button
var _status_label: Label
var _connecting: = false

var focus_before_created: Control = null


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	theme = BASE_THEME
	set_anchors_and_margins_preset(PRESET_WIDE)
	_build_ui()

	if _net != null:
		var _e = _net.connect("joined_lobby", self, "_on_LanNet_joined_lobby")
		_e = _net.connect("session_ended", self, "_on_LanNet_session_ended")


func init() -> void :
	focus_before_created = get_focus_owner()
	_load_fields()
	_set_connecting(_net != null and _net.active and not _net.joined)
	if not _connecting:
		show_status("")
	_join_button.grab_focus()


func show_status(text_key: String, is_error: bool = false) -> void :
	_status_label.text = tr(text_key)
	_status_label.add_color_override("font_color", STATUS_COLOR_ERROR if is_error else STATUS_COLOR_INFO)


func _input(event: InputEvent) -> void :
	if visible and event.is_action_released("ui_cancel"):
		_on_BackButton_pressed()



# UI construction

func _build_ui() -> void :
	var background: = ColorRect.new()
	background.color = Color(0, 0, 0, 0.57)
	background.set_anchors_and_margins_preset(PRESET_WIDE)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)

	var center: = CenterContainer.new()
	center.set_anchors_and_margins_preset(PRESET_WIDE)
	add_child(center)

	var column: = VBoxContainer.new()
	column.rect_min_size = Vector2(760, 0)
	column.add_constant_override("separation", 24)
	center.add_child(column)

	var title: = Label.new()
	title.text = "LAN_MULTIPLAYER_TITLE"
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", TITLE_FONT)
	column.add_child(title)

	var fields: = GridContainer.new()
	fields.columns = 2
	fields.add_constant_override("hseparation", 24)
	fields.add_constant_override("vseparation", 12)
	column.add_child(fields)

	_name_edit = _add_field(fields, "LAN_NAME", NetProtocol.MAX_NAME_LENGTH)
	_ip_edit = _add_field(fields, "LAN_HOST_IP", 39)
	_port_edit = _add_field(fields, "LAN_PORT", 5)
	var _e = _name_edit.connect("text_entered", self, "_on_NameEdit_text_entered")
	_e = _ip_edit.connect("text_entered", self, "_on_IpEdit_text_entered")
	_e = _port_edit.connect("text_entered", self, "_on_IpEdit_text_entered")
	_e = _ip_edit.connect("focus_entered", self, "_set_pad_target", [_ip_edit])
	_e = _port_edit.connect("focus_entered", self, "_set_pad_target", [_port_edit])
	_pad_target = _ip_edit

	var pad_center: = CenterContainer.new()
	column.add_child(pad_center)
	var pad: = GridContainer.new()
	pad.columns = 6
	pad.add_constant_override("hseparation", 8)
	pad.add_constant_override("vseparation", 8)
	pad_center.add_child(pad)
	for key in PAD_KEYS:
		var pad_button: = _new_button(key)
		pad_button.rect_min_size = Vector2(80, 56)
		_e = pad_button.connect("pressed", self, "_on_PadButton_pressed", [key])
		pad.add_child(pad_button)
		_pad_buttons.append(pad_button)

	var buttons: = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_CENTER
	buttons.add_constant_override("separation", 24)
	column.add_child(buttons)

	_host_button = _new_button("LAN_HOST")
	_join_button = _new_button("LAN_JOIN")
	_back_button = _new_button("MENU_BACK")
	_back_button.icon = BACK_ICON
	for button in [_host_button, _join_button, _back_button]:
		button.rect_min_size = Vector2(220, 64)
		buttons.add_child(button)
	_e = _host_button.connect("pressed", self, "_on_HostButton_pressed")
	_e = _join_button.connect("pressed", self, "_on_JoinButton_pressed")
	_e = _back_button.connect("pressed", self, "_on_BackButton_pressed")

	_status_label = Label.new()
	_status_label.align = Label.ALIGN_CENTER
	_status_label.autowrap = true
	_status_label.rect_min_size = Vector2(760, 80)
	column.add_child(_status_label)


func _add_field(grid: GridContainer, label_key: String, max_length: int) -> LineEdit:
	var label: = Label.new()
	label.text = label_key
	label.valign = Label.VALIGN_CENTER
	label.size_flags_vertical = SIZE_FILL
	grid.add_child(label)

	var edit: = LineEdit.new()
	edit.max_length = max_length
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	edit.rect_min_size = Vector2(0, 56)
	grid.add_child(edit)
	return edit


func _new_button(text_key: String) -> Button:
	var button: Button = MyMenuButton.new()
	button.text = text_key
	return button



# Fields

func _load_fields() -> void :
	if _net == null:
		return
	_name_edit.text = _net.config.player_name
	_ip_edit.text = _net.config.last_ip
	_port_edit.text = str(_net.config.port)


# Saves the name and returns the port, or -1 (with an error shown) if it is invalid.
func _read_fields() -> int:
	_net.set_player_name(_name_edit.text)
	_name_edit.text = _net.config.player_name

	var port_text: = _port_edit.text.strip_edges()
	if not port_text.is_valid_integer() or int(port_text) <= 0 or int(port_text) > 65535:
		show_status("LAN_MSG_INVALID_PORT", true)
		return - 1
	return int(port_text)


func _set_pad_target(edit: LineEdit) -> void :
	_pad_target = edit


func _set_connecting(value: bool) -> void :
	_connecting = value
	for control in [_name_edit, _ip_edit, _port_edit]:
		control.editable = not value
	# MyMenuButton re-enables itself after its press delay, so use its own disable/activate.
	for button in _pad_buttons + [_host_button, _join_button]:
		if value:
			button.disable()
		else:
			button.activate()
	if value:
		_back_button.grab_focus()



# Signals

func _on_PadButton_pressed(key: String) -> void :
	if _connecting:
		return
	var text: = _pad_target.text
	if key == "<":
		text = text.left(text.length() - 1)
	elif _pad_target != _port_edit or key != ".":
		text += key
	_pad_target.text = text.left(_pad_target.max_length)
	_pad_target.caret_position = _pad_target.text.length()


func _on_NameEdit_text_entered(_text: String) -> void :
	_ip_edit.grab_focus()


func _on_IpEdit_text_entered(_text: String) -> void :
	_on_JoinButton_pressed()


func _on_HostButton_pressed() -> void :
	if _net == null or _connecting:
		return
	var port: = _read_fields()
	if port < 0:
		return
	if _net.host(port) != OK:
		show_status(_net.last_end_reason, true)
		_net.last_end_reason = ""
		return
	show_status("")
	emit_signal("lobby_requested")


func _on_JoinButton_pressed() -> void :
	if _net == null or _connecting:
		return
	var port: = _read_fields()
	if port < 0:
		return
	if _net.join(_ip_edit.text, port) != OK:
		show_status(_net.last_end_reason, true)
		_net.last_end_reason = ""
		return
	_set_connecting(true)
	_status_label.text = tr("LAN_CONNECTING").replace("{0}", _net.config.last_ip + ":" + str(port))
	_status_label.add_color_override("font_color", STATUS_COLOR_INFO)


func _on_BackButton_pressed() -> void :
	if _net != null and _connecting:
		_set_connecting(false)
		_net.leave()
	if is_instance_valid(focus_before_created):
		focus_before_created.grab_focus()
	emit_signal("back_button_pressed")


func _on_LanNet_joined_lobby() -> void :
	if not visible:
		return
	_set_connecting(false)
	show_status("")
	emit_signal("lobby_requested")


func _on_LanNet_session_ended(reason: String) -> void :
	if not visible or not _connecting:
		return
	_set_connecting(false)
	show_status(reason, not reason.empty())
	_net.last_end_reason = ""
	_join_button.grab_focus()
