extends Control

# Title screen page for joining: games found on the LAN (LanNet.discovery), plus a manual
# "ip" / "ip:port" field as a fallback for networks where broadcasts don't arrive.
# Pressing a found game or Connect joins; lobby_requested fires once the host accepted.
# While LanNet reconnects after a lost connection, the page shows it as connecting; Back cancels.

signal back_button_pressed
signal lobby_requested

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")

const WIDTH: = 760.0

var _net: Node = null
var _games_list: VBoxContainer
var _games_placeholder: Label
var _address_edit: LineEdit
var _connect_button: Button
var _back_button: Button
var _status_label: Label
var _connecting: = false

# Discovery key ("ip:port") -> row button
var _game_rows: = {}

var focus_before_created: Control = null


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	_build_ui()
	if _net != null:
		var _e = _net.connect("joined_lobby", self, "_on_LanNet_joined_lobby")
		_e = _net.connect("session_ended", self, "_on_LanNet_session_ended")
		_e = _net.discovery.connect("games_changed", self, "_on_Discovery_games_changed")


func init() -> void :
	focus_before_created = get_focus_owner()
	if _net == null:
		return
	_address_edit.text = _net.config.last_ip
	if _net.config.port != NetProtocol.DEFAULT_PORT:
		_address_edit.text += ":" + str(_net.config.port)
	_set_connecting((_net.active and not _net.joined) or _net.is_reconnecting())
	if not _connecting:
		show_status("")
	_net.discovery.start_listening()
	_update_games()
	if _game_rows.empty():
		_address_edit.grab_focus()
	else:
		_first_row().grab_focus()


func show_status(text: String, is_error: bool = false) -> void :
	UiKit.set_status(_status_label, text, is_error)


func _notification(what: int) -> void :
	# Listen only while this page is shown (LanNet outlives the title screen).
	var hidden_now: = what == NOTIFICATION_VISIBILITY_CHANGED and not visible
	if (hidden_now or what == NOTIFICATION_EXIT_TREE) and is_instance_valid(_net):
		_net.discovery.stop_listening()


func _input(event: InputEvent) -> void :
	if visible and event.is_action_released("ui_cancel"):
		# Stop the page that becomes visible from handling the same event.
		get_tree().set_input_as_handled()
		_on_BackButton_pressed()



# UI construction

func _build_ui() -> void :
	var column: = UiKit.build_page(self, WIDTH, "LAN_JOIN_GAME")

	var found_label: = Label.new()
	found_label.text = "LAN_FOUND_GAMES"
	column.add_child(found_label)

	var panel: = PanelContainer.new()
	panel.rect_min_size = Vector2(0, 320)
	column.add_child(panel)

	var panel_column: = VBoxContainer.new()
	panel.add_child(panel_column)

	_games_placeholder = Label.new()
	_games_placeholder.align = Label.ALIGN_CENTER
	_games_placeholder.autowrap = true
	_games_placeholder.modulate = Color(1, 1, 1, 0.6)
	panel_column.add_child(_games_placeholder)

	_games_list = VBoxContainer.new()
	_games_list.add_constant_override("separation", 8)
	panel_column.add_child(_games_list)

	var address_label: = Label.new()
	address_label.text = "LAN_JOIN_BY_ADDRESS"
	column.add_child(address_label)

	var address_row: = HBoxContainer.new()
	address_row.add_constant_override("separation", 16)
	column.add_child(address_row)

	_address_edit = LineEdit.new()
	_address_edit.max_length = 21
	_address_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_address_edit.rect_min_size = Vector2(0, 56)
	address_row.add_child(_address_edit)
	var _e = _address_edit.connect("text_entered", self, "_on_AddressEdit_text_entered")

	_connect_button = UiKit.new_button("LAN_CONNECT", Vector2(220, 56))
	address_row.add_child(_connect_button)
	_e = _connect_button.connect("pressed", self, "_on_ConnectButton_pressed")

	_status_label = UiKit.new_status_label(WIDTH)
	column.add_child(_status_label)

	_back_button = UiKit.new_back_button()
	column.add_child(_back_button)
	_e = _back_button.connect("pressed", self, "_on_BackButton_pressed")



# Found games

# Updates the rows in place, so the focused row keeps its focus while beacons come in.
func _update_games() -> void :
	var games: Array = _net.discovery.get_games()
	var focus_owner: = get_focus_owner()
	var lost_focus: = false

	var keys: = []
	for game in games:
		keys.append(game.ip + ":" + str(game.port))
	for key in _game_rows.keys():
		if not keys.has(key):
			var row: Button = _game_rows[key]
			lost_focus = lost_focus or row == focus_owner
			_games_list.remove_child(row)
			row.queue_free()
			_game_rows.erase(key)

	for i in games.size():
		var game: Dictionary = games[i]
		var key: String = keys[i]
		var row: Button = _game_rows.get(key)
		if row == null:
			row = UiKit.new_button("", Vector2(0, 64))
			row.align = Button.ALIGN_LEFT
			var _e = row.connect("pressed", self, "_on_GameRow_pressed", [key])
			_games_list.add_child(row)
			_game_rows[key] = row
		_games_list.move_child(row, i)
		row.text = "%s   %d/%d" % [game.name, game.players, game.max_players]
		if not game.compatible:
			row.text += "   " + tr("LAN_INCOMPATIBLE")
		_set_row_enabled(row, game.compatible and not _connecting)

	if _net.discovery.listen_failed:
		_games_placeholder.text = "LAN_DISCOVERY_UNAVAILABLE"
	else:
		_games_placeholder.text = "LAN_SEARCHING"
	_games_placeholder.visible = _game_rows.empty()

	if lost_focus:
		if _game_rows.empty():
			_address_edit.grab_focus()
		else:
			_first_row().grab_focus()


func _first_row() -> Button:
	return _games_list.get_child(0) as Button


func _set_row_enabled(row: Button, enabled: bool) -> void :
	# MyMenuButton re-enables itself after its press delay, so use its own disable/activate.
	if enabled:
		row.activate()
	else:
		row.disable()



# Joining

func _join(ip: String, port: int) -> void :
	if _net == null or _connecting:
		return
	if _net.join(ip, port) != OK:
		show_status(_net.last_end_reason, true)
		_net.last_end_reason = ""
		return
	_set_connecting(true)
	show_status(tr("LAN_CONNECTING").replace("{0}", ip + ":" + str(port)))


func _set_connecting(value: bool) -> void :
	_connecting = value
	_address_edit.editable = not value
	_set_row_enabled(_connect_button, not value)
	if _net != null:
		for game in _net.discovery.get_games():
			var row = _game_rows.get(game.ip + ":" + str(game.port))
			if row != null:
				_set_row_enabled(row, game.compatible and not value)
	if value:
		_back_button.grab_focus()



# Signals

func _on_GameRow_pressed(key: String) -> void :
	var game = _net.discovery.games.get(key)
	if game != null and game.compatible:
		_join(game.ip, game.port)


func _on_AddressEdit_text_entered(_text: String) -> void :
	_on_ConnectButton_pressed()


func _on_ConnectButton_pressed() -> void :
	if _net == null or _connecting:
		return
	var address: = NetProtocol.parse_address(_address_edit.text, NetProtocol.DEFAULT_PORT)
	if address.has("error"):
		show_status(address.error, true)
		return
	_join(address.ip, address.port)


func _on_BackButton_pressed() -> void :
	if _net != null and _connecting:
		_set_connecting(false)
		_net.cancel_reconnect()
		_net.leave()
	if is_instance_valid(focus_before_created):
		focus_before_created.grab_focus()
	emit_signal("back_button_pressed")


func _on_Discovery_games_changed() -> void :
	if visible:
		_update_games()


func _on_LanNet_joined_lobby() -> void :
	if not visible:
		return
	_set_connecting(false)
	show_status("")
	emit_signal("lobby_requested")


func _on_LanNet_session_ended(reason: String) -> void :
	if not visible or not _connecting:
		return
	_net.last_end_reason = ""
	# A reconnect attempt failed; LanNet tries again.
	if _net.is_reconnecting():
		show_status(reason)
		return
	_set_connecting(false)
	show_status(reason, not reason.empty())
	_connect_button.grab_focus()
