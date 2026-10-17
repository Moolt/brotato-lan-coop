extends Control

# Title screen page shown while in a LAN session: lists every joined player.
# Step 3 adds the character grid, weapon picker, ready toggle and the host's Start button.
# Leaving (button or ui_cancel) ends the session; the title screen menus then switch back
# to the multiplayer menu through LanNet.session_ended.

const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const TITLE_FONT = preload("res://resources/fonts/actual/base/font_60_outline.tres")
const BACK_ICON = preload("res://ui/menus/global/arrow_left_border.png")

var _net: Node = null
var _address_label: Label
var _count_label: Label
var _player_list: VBoxContainer
var _leave_button: Button


func _ready() -> void :
	_net = get_node_or_null("/root/LanNet")
	theme = BASE_THEME
	set_anchors_and_margins_preset(PRESET_WIDE)
	_build_ui()

	if _net != null:
		var _e = _net.connect("lobby_changed", self, "_on_LanNet_lobby_changed")


func init() -> void :
	_update_address()
	_refresh_players()
	_leave_button.grab_focus()


func _input(event: InputEvent) -> void :
	if visible and event.is_action_released("ui_cancel"):
		_on_LeaveButton_pressed()



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
	column.add_constant_override("separation", 20)
	center.add_child(column)

	var title: = Label.new()
	title.text = "LAN_LOBBY"
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", TITLE_FONT)
	column.add_child(title)

	_address_label = Label.new()
	_address_label.align = Label.ALIGN_CENTER
	_address_label.autowrap = true
	column.add_child(_address_label)

	_count_label = Label.new()
	column.add_child(_count_label)

	var panel: = PanelContainer.new()
	panel.rect_min_size = Vector2(0, 420)
	column.add_child(panel)

	_player_list = VBoxContainer.new()
	_player_list.add_constant_override("separation", 6)
	panel.add_child(_player_list)

	_leave_button = MyMenuButton.new()
	_leave_button.text = "LAN_LEAVE"
	_leave_button.icon = BACK_ICON
	_leave_button.rect_min_size = Vector2(250, 64)
	_leave_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	var _e = _leave_button.connect("pressed", self, "_on_LeaveButton_pressed")
	column.add_child(_leave_button)



# Content

func _update_address() -> void :
	if _net == null or not _net.is_host:
		_address_label.text = ""
		return
	var addresses: = get_lan_addresses()
	var address_text: String = PoolStringArray(addresses).join(", ") if not addresses.empty() else "127.0.0.1"
	_address_label.text = tr("LAN_JOIN_ADDRESS").replace("{0}", address_text).replace("{1}", str(_net.config.port))


func _refresh_players() -> void :
	for child in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()
	if _net == null:
		return

	_count_label.text = tr("LAN_PLAYER_COUNT").replace("{0}", str(_net.get_player_count())).replace("{1}", str(NetProtocol.MAX_PLAYERS))

	for entry in _net.players:
		var row: = Label.new()
		var text: String = str(entry.player_index + 1) + ".  " + entry.name
		if entry.player_index == 0:
			text += "  " + tr("LAN_TAG_HOST")
		if entry.player_index == _net.local_player_index:
			text += "  " + tr("LAN_TAG_YOU")
		if not entry.connected:
			text += "  " + tr("LAN_TAG_DISCONNECTED")
		row.text = text
		_player_list.add_child(row)


# IPv4 addresses other machines can use to reach this one
# (no loopback, no link-local, no container/VM bridges).
static func get_lan_addresses() -> Array:
	var result: = []
	for interface in IP.get_local_interfaces():
		if _is_virtual_interface(str(interface.name).to_lower()):
			continue
		for address in interface.addresses:
			if not address.is_valid_ip_address() or ":" in address:
				continue
			if address.begins_with("127.") or address.begins_with("169.254."):
				continue
			if not result.has(address):
				result.append(address)
	result.sort()
	return result


static func _is_virtual_interface(interface_name: String) -> bool:
	for prefix in ["lo", "docker", "br-", "veth", "virbr", "vmnet", "vboxnet", "podman", "cni", "flannel"]:
		if interface_name.begins_with(prefix):
			return true
	return false



# Signals

func _on_LanNet_lobby_changed() -> void :
	if visible:
		_refresh_players()


func _on_LeaveButton_pressed() -> void :
	if _net != null:
		_net.leave()
