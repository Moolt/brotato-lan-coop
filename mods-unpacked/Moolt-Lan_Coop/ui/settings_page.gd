extends Control

# The lobby's run settings, opened with its Settings button and shown over the lobby: one row
# per setting (label, dropdown). Only the host opens it and changes them
# (LanNet.set_lobby_settings, applied at once); during a run they are read-only. Back or
# ui_cancel (handled by the lobby) closes the page.

signal closed()

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
const ModeRegistry = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/mode_registry.gd")

const ROW_FONT = preload("res://resources/fonts/actual/base/font_26_outline.tres")
const INFO_FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const OPTION_THEME = preload("res://resources/themes/zone_selection_button_theme.tres")

const WIDTH: = 860.0
const OPTION_SIZE: = Vector2(440, 52)

var _net: Node = null
var _mode_option: OptionButton
var _mode_info: Label
var _zone_option: OptionButton
var _difficulty_option: OptionButton
var _choice_time_option: OptionButton
var _scaling_option: OptionButton
var _scaling_info: Label
var _back_button: Button


func _init() -> void :
	name = "LanSettingsPage"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: = UiKit.build_page(self, WIDTH, "LAN_SETTINGS")
	# Clicks must not reach the lobby underneath, and its busy grids would show through.
	var background: ColorRect = get_child(0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.color = Color(0.06, 0.06, 0.06, 0.96)
	column.add_constant_override("separation", 8)
	var title_gap: = Control.new()
	title_gap.rect_min_size = Vector2(0, 16)
	column.add_child(title_gap)

	_mode_option = _add_row(column, "LAN_SETTING_MODE", "mode")
	_mode_info = _add_info(column)
	_zone_option = _add_row(column, "LAN_SETTING_ZONE", "zone")
	_difficulty_option = _add_row(column, "LAN_SETTING_DANGER", "difficulty")
	_choice_time_option = _add_row(column, "LAN_SETTING_CHOICE_TIME", "choice_time")
	_scaling_option = _add_row(column, "LAN_SETTING_SCALING", "scaling_preset")
	# What the preset adds per extra player, from the knobs the clients get.
	_scaling_info = _add_info(column)

	var spacer: = Control.new()
	spacer.rect_min_size = Vector2(0, 12)
	column.add_child(spacer)
	_back_button = UiKit.new_back_button()
	var _e = _back_button.connect("pressed", self, "close")
	column.add_child(_back_button)
	visible = false


func open(net: Node) -> void :
	_net = net
	_fill_options()
	refresh()
	show()
	if _mode_option.disabled:
		_back_button.grab_focus()
	else:
		_mode_option.grab_focus()


func close() -> void :
	if not visible:
		return
	hide()
	emit_signal("closed")


# Shows the current lobby settings; editable for the host outside a run.
func refresh() -> void :
	if _net == null:
		return
	var settings: Dictionary = _net.lobby_settings
	var editable: bool = _net.is_host and not _net.run_in_progress
	for option in _get_options():
		option.disabled = not editable
		option.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	# select() doesn't emit item_selected, so this never loops back.
	var mode_id: String = settings.get("mode", NetProtocol.DEFAULT_MODE)
	_mode_option.select(_get_mode_index(mode_id))
	_mode_info.text = tr(ModeRegistry.get_description_key(mode_id))
	_zone_option.select(_zone_option.get_item_index(settings.get("zone", 0)))
	_difficulty_option.select(_difficulty_option.get_item_index(settings.get("difficulty", 0)))
	_choice_time_option.select(_choice_time_option.get_item_index(settings.get("choice_time", 0)))
	_scaling_option.select(_scaling_option.get_item_index(settings.get("scaling_preset", NetProtocol.SCALING_PRESET_NORMAL)))
	var scaling: Dictionary = settings.get("scaling", NetProtocol.DEFAULT_SCALING)
	_scaling_info.text = tr("LAN_SCALING_INFO") \
			.replace("{0}", _percent(scaling.get("enemy_count_per_player", 0.0))) \
			.replace("{1}", _percent(scaling.get("enemy_health_per_player", 0.0))) \
			.replace("{2}", _percent(scaling.get("enemy_damage_per_player", 0.0))) \
			.replace("{3}", _percent(scaling.get("enemy_health_per_player_beyond_4", 0.0)))
	_chain_focus()


# An open dropdown takes ui_cancel itself (the lobby checks this before closing the page).
func is_popup_open() -> bool:
	for option in _get_options():
		if option.get_popup().visible:
			return true
	return false


# "<zone> · <danger>", then the settings that differ from their default (lobby summary line).
static func get_summary(settings: Dictionary) -> String:
	var zone: = LobbyRules.get_zone(settings.get("zone", 0))
	var difficulty: = LobbyRules.get_difficulty(settings.get("difficulty", 0))
	var parts: = [TranslationServer.translate(zone.name) if zone != null else "?", difficulty.get_name_text() if difficulty != null else "?"]
	var mode_id: String = settings.get("mode", NetProtocol.DEFAULT_MODE)
	if mode_id != NetProtocol.DEFAULT_MODE:
		parts.push_front(TranslationServer.translate(ModeRegistry.get_name_key(mode_id)))
	var choice_time: = int(settings.get("choice_time", NetProtocol.DEFAULT_CHOICE_TIME))
	if choice_time == 0:
		parts.append(TranslationServer.translate("LAN_SUMMARY_NO_CHOICE_TIME"))
	elif choice_time != NetProtocol.DEFAULT_CHOICE_TIME:
		parts.append(TranslationServer.translate("LAN_SUMMARY_CHOICE_TIME").replace("{0}", str(choice_time)))
	match int(settings.get("scaling_preset", NetProtocol.SCALING_PRESET_NORMAL)):
		NetProtocol.SCALING_PRESET_RELAXED:
			parts.append(TranslationServer.translate("LAN_SUMMARY_SCALING_RELAXED"))
		NetProtocol.SCALING_PRESET_TOUGH:
			parts.append(TranslationServer.translate("LAN_SUMMARY_SCALING_TOUGH"))
	return PoolStringArray(parts).join(" · ")


# The lobby's controls stay visible under the page, so focus moves only between the page's own
# controls, top to bottom.
func _chain_focus() -> void :
	var controls: = []
	for control in _get_options() + [_back_button]:
		if control.focus_mode != Control.FOCUS_NONE:
			controls.append(control)
	for i in controls.size():
		var control: Control = controls[i]
		var previous: NodePath = control.get_path_to(controls[max(i - 1, 0)])
		var next: NodePath = control.get_path_to(controls[min(i + 1, controls.size() - 1)])
		control.focus_neighbour_top = previous
		control.focus_previous = previous
		control.focus_neighbour_bottom = next
		control.focus_next = next
		control.focus_neighbour_left = NodePath(".")
		control.focus_neighbour_right = NodePath(".")


func _fill_options() -> void :
	# OptionButton ids are ints: the mode's index in ModeRegistry.MODES.
	_mode_option.clear()
	for i in ModeRegistry.MODES.size():
		_mode_option.add_item(tr(ModeRegistry.MODES[i].name), i)
	_zone_option.clear()
	for zone in ZoneService.zones:
		_zone_option.add_item(tr(zone.name), zone.my_id)
	_difficulty_option.clear()
	for difficulty in ItemService.difficulties:
		_difficulty_option.add_item(difficulty.get_name_text(), difficulty.value)
	_choice_time_option.clear()
	for seconds in NetProtocol.CHOICE_TIMES:
		_choice_time_option.add_item(tr("LAN_CHOICE_TIME_OFF") if seconds == 0 else tr("LAN_CHOICE_TIME_SECONDS").replace("{0}", str(seconds)), seconds)
	_scaling_option.clear()
	for preset in NetProtocol.SCALING_PRESET_KEYS.size():
		_scaling_option.add_item(tr(NetProtocol.SCALING_PRESET_KEYS[preset]), preset)


func _get_options() -> Array:
	return [_mode_option, _zone_option, _difficulty_option, _choice_time_option, _scaling_option]


func _get_mode_index(mode_id: String) -> int:
	for i in ModeRegistry.MODES.size():
		if ModeRegistry.MODES[i].id == mode_id:
			return i
	return 0


func _add_info(column: VBoxContainer) -> Label:
	var info: = Label.new()
	info.add_font_override("font", INFO_FONT)
	info.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	info.autowrap = true
	column.add_child(info)
	return info


static func _percent(value: float) -> String:
	return str(int(round(value * 100)))


# A label and a dropdown whose item ids are the setting's values.
func _add_row(column: VBoxContainer, text_key: String, setting: String) -> OptionButton:
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 16)
	column.add_child(row)
	var label: = Label.new()
	label.text = text_key
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.valign = Label.VALIGN_CENTER
	label.add_font_override("font", ROW_FONT)
	row.add_child(label)
	var option: = OptionButton.new()
	option.theme = OPTION_THEME
	option.rect_min_size = OPTION_SIZE
	var _e = option.connect("item_selected", self, "_on_option_item_selected", [option, setting])
	row.add_child(option)
	return option


func _on_option_item_selected(index: int, option: OptionButton, setting: String) -> void :
	if _net == null:
		return
	var value = option.get_item_id(index)
	if setting == "mode":
		value = ModeRegistry.MODES[value].id
	_net.set_lobby_settings({setting: value})
