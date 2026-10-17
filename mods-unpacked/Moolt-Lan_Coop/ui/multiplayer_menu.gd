extends Control

# Title screen page opened by the "Multiplayer" button: player name, Host game, Join game, Back.
# Host game starts hosting right away (lobby_requested); Join game opens the join page.
# Follows the menu_credits.gd page pattern (init, ui_cancel, back_button_pressed).

signal back_button_pressed
signal lobby_requested
signal join_requested

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const WIDTH: = 640.0

var _net: Node = null
var _name_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _back_button: Button
var _status_label: Label

var focus_before_created: Control = null


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	_build_ui()


func init() -> void :
	focus_before_created = get_focus_owner()
	if _net != null:
		_name_edit.text = _net.config.player_name
	show_status("")
	_host_button.grab_focus()


func show_status(text: String, is_error: bool = false) -> void :
	UiKit.set_status(_status_label, text, is_error)


func _input(event: InputEvent) -> void :
	if visible and event.is_action_released("ui_cancel"):
		# Stop the page that becomes visible from handling the same event.
		get_tree().set_input_as_handled()
		_on_BackButton_pressed()


func _build_ui() -> void :
	var column: = UiKit.build_page(self, WIDTH, "LAN_MULTIPLAYER_TITLE")

	var name_row: = HBoxContainer.new()
	name_row.add_constant_override("separation", 24)
	column.add_child(name_row)

	var name_label: = Label.new()
	name_label.text = "LAN_NAME"
	name_label.valign = Label.VALIGN_CENTER
	name_label.size_flags_vertical = SIZE_FILL
	name_row.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.max_length = NetProtocol.MAX_NAME_LENGTH
	_name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_edit.rect_min_size = Vector2(0, 56)
	name_row.add_child(_name_edit)
	var _e = _name_edit.connect("text_changed", self, "_on_NameEdit_text_changed")
	_e = _name_edit.connect("text_entered", self, "_on_NameEdit_text_entered")

	_host_button = UiKit.new_button("LAN_HOST_GAME", Vector2(WIDTH, 72))
	_join_button = UiKit.new_button("LAN_JOIN_GAME", Vector2(WIDTH, 72))
	_back_button = UiKit.new_back_button()
	for button in [_host_button, _join_button, _back_button]:
		column.add_child(button)
	_e = _host_button.connect("pressed", self, "_on_HostButton_pressed")
	_e = _join_button.connect("pressed", self, "_on_JoinButton_pressed")
	_e = _back_button.connect("pressed", self, "_on_BackButton_pressed")

	_status_label = UiKit.new_status_label(WIDTH)
	column.add_child(_status_label)


# Saves the typed name, falling back to the stored one while the field is empty.
func _save_name() -> void :
	if _net == null:
		return
	if not _name_edit.text.strip_edges().empty():
		_net.set_player_name(_name_edit.text)
	_name_edit.text = _net.config.player_name



# Signals

func _on_NameEdit_text_changed(new_text: String) -> void :
	if _net != null and not new_text.strip_edges().empty():
		_net.set_player_name(new_text)


func _on_NameEdit_text_entered(_text: String) -> void :
	_save_name()
	_host_button.grab_focus()


func _on_HostButton_pressed() -> void :
	if _net == null:
		return
	_save_name()
	if _net.host() != OK:
		show_status(_net.last_end_reason, true)
		_net.last_end_reason = ""
		return
	emit_signal("lobby_requested")


func _on_JoinButton_pressed() -> void :
	_save_name()
	emit_signal("join_requested")


func _on_BackButton_pressed() -> void :
	_save_name()
	if is_instance_valid(focus_before_created):
		focus_before_created.grab_focus()
	emit_signal("back_button_pressed")
