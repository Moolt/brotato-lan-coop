extends Control

# The lobby's run settings, opened with its Settings button and shown over the lobby: rows
# (label, dropdown) in groups under small headers, and one help box at the bottom that explains
# the row with the focus or the mouse (the mode's description otherwise). Rows of settings the
# mode fixes (ModeRegistry.get_fixed_settings) stay, greyed out and showing "Set by mode".
# Everyone opens it; only the host changes the settings (LanNet.set_lobby_settings, applied at
# once), and not during a run. Read-only, the dropdowns still open and list their choices, all
# disabled, and a note under the title says why. Back or ui_cancel (handled by the lobby) closes
# the page.

signal closed()

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const NetProtocol = preload("res://mods-unpacked/Moolt-Lan_Coop/net/net_protocol.gd")
const LobbyRules = preload("res://mods-unpacked/Moolt-Lan_Coop/net/lobby_rules.gd")
const ModeRegistry = preload("res://mods-unpacked/Moolt-Lan_Coop/modes/mode_registry.gd")

const ROW_FONT = preload("res://resources/fonts/actual/base/font_26_outline.tres")
const INFO_FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const OPTION_THEME = preload("res://resources/themes/zone_selection_button_theme.tres")

const WIDTH: = 860.0
const OPTION_SIZE: = Vector2(380, 52)
# Four lines of the help font, so a longer text doesn't move the page.
const HELP_HEIGHT: = 104.0
const HELP_COLOR: = Color(1, 1, 1, 0.8)
const FIXED_ALPHA: = 0.5
# The item id of a fixed setting's only entry (not -1: add_item takes that as "use the index").
const FIXED_ID: = 2
const LOOT_SETTINGS: = ["share_materials", "share_crates"]
# Item texts of the loot rows: [shared (id 1), picker's (id 0)].
const LOOT_ITEM_KEYS: = {
	"share_materials": ["LAN_LOOT_MATERIALS_SHARED", "LAN_LOOT_PICKER_KEEPS"], 
	"share_crates": ["LAN_LOOT_CRATES_SHARED", "LAN_LOOT_PICKER_KEEPS"], 
}

var _net: Node = null
var _mode_option: OptionButton
var _zone_option: OptionButton
var _difficulty_option: OptionButton
var _choice_time_option: OptionButton
var _scaling_option: OptionButton
var _share_materials_option: OptionButton
var _share_crates_option: OptionButton
var _back_button: Button
var _help_label: Label
var _read_only_label: Label
# setting -> its row (an HBoxContainer: label, dropdown).
var _rows: = {}
# The rows the help box explains: the one under the mouse wins until the focus moves.
var _hovered_setting: = ""
var _focused_setting: = ""


func _init() -> void :
	name = "LanSettingsPage"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: = UiKit.build_page(self, WIDTH, "LAN_SETTINGS")
	# Clicks must not reach the lobby underneath, and its busy grids would show through.
	var background: ColorRect = get_child(0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.color = Color(0.06, 0.06, 0.06, 0.96)
	column.add_constant_override("separation", 8)
	_read_only_label = Label.new()
	_read_only_label.align = Label.ALIGN_CENTER
	_read_only_label.add_font_override("font", INFO_FONT)
	_read_only_label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	column.add_child(_read_only_label)

	_add_header(column, "LAN_SETTINGS_GROUP_GAME")
	_mode_option = _add_row(column, "LAN_SETTING_MODE", "mode")
	_zone_option = _add_row(column, "LAN_SETTING_ZONE", "zone")
	_difficulty_option = _add_row(column, "LAN_SETTING_DANGER", "difficulty")
	_add_header(column, "LAN_SETTINGS_GROUP_BALANCE")
	_scaling_option = _add_row(column, "LAN_SETTING_SCALING", "scaling_preset")
	_choice_time_option = _add_row(column, "LAN_SETTING_CHOICE_TIME", "choice_time")
	_add_header(column, "LAN_SETTINGS_GROUP_LOOT")
	_share_materials_option = _add_row(column, "LAN_SETTING_SHARE_MATERIALS", "share_materials")
	_share_crates_option = _add_row(column, "LAN_SETTING_SHARE_CRATES", "share_crates")

	_add_gap(column, 16)
	var help_box: = PanelContainer.new()
	help_box.add_stylebox_override("panel", UiKit.new_rounded_style(Color(1, 1, 1, 0.06), 8, 16, 10))
	column.add_child(help_box)
	_help_label = Label.new()
	_help_label.add_font_override("font", INFO_FONT)
	_help_label.add_color_override("font_color", HELP_COLOR)
	_help_label.autowrap = true
	_help_label.rect_min_size = Vector2(0, HELP_HEIGHT)
	help_box.add_child(_help_label)

	_add_gap(column, 12)
	_back_button = UiKit.new_back_button()
	var _e = _back_button.connect("pressed", self, "close")
	_e = _back_button.connect("focus_entered", self, "_on_control_focus_entered", [""])
	column.add_child(_back_button)
	visible = false


func open(net: Node) -> void :
	_net = net
	_hovered_setting = ""
	_focused_setting = ""
	_fill_options()
	refresh()
	show()
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
	_read_only_label.visible = not editable
	_read_only_label.text = "LAN_SETTINGS_RUN_READ_ONLY" if _net.is_host else "LAN_SETTINGS_HOST_ONLY"
	for option in _get_options():
		option.disabled = false
		option.focus_mode = Control.FOCUS_ALL
	# select() doesn't emit item_selected, so this never loops back.
	var mode_id: String = settings.get("mode", NetProtocol.DEFAULT_MODE)
	_mode_option.select(_get_mode_index(mode_id))
	_zone_option.select(_zone_option.get_item_index(settings.get("zone", 0)))
	_difficulty_option.select(_difficulty_option.get_item_index(settings.get("difficulty", 0)))
	_choice_time_option.select(_choice_time_option.get_item_index(settings.get("choice_time", 0)))
	_scaling_option.select(_scaling_option.get_item_index(settings.get("scaling_preset", NetProtocol.SCALING_PRESET_NORMAL)))
	var fixed: = ModeRegistry.get_fixed_settings(mode_id)
	for option in [_share_materials_option, _share_crates_option]:
		var setting: String = option.get_meta("setting")
		var is_fixed: = fixed.has(setting)
		_fill_loot_option(option, is_fixed)
		if is_fixed:
			option.disabled = true
			option.focus_mode = Control.FOCUS_NONE
		else:
			option.select(option.get_item_index(1 if settings.get(setting, true) else 0))
		_rows[setting].modulate.a = FIXED_ALPHA if is_fixed else 1.0
	# Read-only: the lists show every choice, but none can be picked.
	for option in _get_options():
		for i in option.get_item_count():
			option.set_item_disabled(i, not editable)
	_update_help()
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
	var fixed: = ModeRegistry.get_fixed_settings(mode_id)
	if not settings.get("share_materials", true) and not fixed.has("share_materials"):
		parts.append(TranslationServer.translate("LAN_SUMMARY_OWN_MATERIALS"))
	if not settings.get("share_crates", true) and not fixed.has("share_crates"):
		parts.append(TranslationServer.translate("LAN_SUMMARY_OWN_CRATES"))
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
	for zone in LobbyRules.get_zones():
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
	for option in [_share_materials_option, _share_crates_option]:
		option.clear()


# In the page's order, top to bottom (the focus chain follows it).
func _get_options() -> Array:
	return [_mode_option, _zone_option, _difficulty_option, _scaling_option, _choice_time_option, _share_materials_option, _share_crates_option]


func _get_mode_index(mode_id: String) -> int:
	for i in ModeRegistry.MODES.size():
		if ModeRegistry.MODES[i].id == mode_id:
			return i
	return 0


# A loot row's entries: shared (id 1) and the picker's (id 0), or only "Set by mode" when the
# mode fixes the setting. Refilled only when that changes, so an open dropdown keeps its list.
func _fill_loot_option(option: OptionButton, is_fixed: bool) -> void :
	if option.get_item_count() > 0 and (option.get_item_id(0) == FIXED_ID) == is_fixed:
		return
	option.clear()
	if is_fixed:
		option.add_item(tr("LAN_SETTING_BY_MODE"), FIXED_ID)
		return
	var keys: Array = LOOT_ITEM_KEYS[option.get_meta("setting")]
	option.add_item(tr(keys[0]), 1)
	option.add_item(tr(keys[1]), 0)


func _get_help_text(setting: String) -> String:
	var mode_id: String = _net.lobby_settings.get("mode", NetProtocol.DEFAULT_MODE)
	match setting:
		"choice_time":
			return tr("LAN_HELP_CHOICE_TIME")
		"scaling_preset":
			# What the preset adds per extra player, from the knobs the clients get.
			var scaling: Dictionary = _net.lobby_settings.get("scaling", NetProtocol.DEFAULT_SCALING)
			return tr("LAN_SCALING_INFO") \
					.replace("{0}", _percent(scaling.get("enemy_count_per_player", 0.0))) \
					.replace("{1}", _percent(scaling.get("enemy_health_per_player", 0.0))) \
					.replace("{2}", _percent(scaling.get("enemy_damage_per_player", 0.0))) \
					.replace("{3}", _percent(scaling.get("enemy_health_per_player_beyond_4", 0.0)))
		"share_materials", "share_crates":
			# A fixed loot row: the mode's description says who gets what.
			if not ModeRegistry.get_fixed_settings(mode_id).has(setting):
				return tr("LAN_HELP_" + setting.to_upper())
	return tr(ModeRegistry.get_description_key(mode_id))


func _update_help() -> void :
	if _net == null:
		return
	_help_label.text = _get_help_text(_hovered_setting if _hovered_setting != "" else _focused_setting)


func _input(event: InputEvent) -> void :
	if not visible or not (event is InputEventMouseMotion) or is_popup_open():
		return
	var mouse: = get_global_mouse_position()
	var hovered: = ""
	for setting in _rows:
		if _rows[setting].get_global_rect().has_point(mouse):
			hovered = setting
	if hovered != _hovered_setting:
		_hovered_setting = hovered
		_update_help()


# setting is "" for the back button.
func _on_control_focus_entered(setting: String) -> void :
	_focused_setting = setting
	_hovered_setting = ""
	_update_help()


func _add_header(column: VBoxContainer, text_key: String) -> void :
	# The first header sits under the title.
	_add_gap(column, 12 if column.get_child_count() > 1 else 4)
	var header: = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	column.add_child(header)
	var label: = Label.new()
	label.text = text_key
	label.uppercase = true
	label.add_font_override("font", INFO_FONT)
	label.add_color_override("font_color", UiKit.STATUS_COLOR_MUTED)
	header.add_child(label)
	var line: = ColorRect.new()
	line.color = Color(1, 1, 1, 0.18)
	line.rect_min_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(line)


func _add_gap(column: VBoxContainer, height: float) -> void :
	var gap: = Control.new()
	gap.rect_min_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)


static func _percent(value: float) -> String:
	return str(int(round(value * 100)))


# A label and a dropdown whose item ids are the setting's values.
func _add_row(column: VBoxContainer, text_key: String, setting: String) -> OptionButton:
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 16)
	column.add_child(row)
	_rows[setting] = row
	var label: = Label.new()
	label.text = text_key
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.valign = Label.VALIGN_CENTER
	label.add_font_override("font", ROW_FONT)
	row.add_child(label)
	var option: = OptionButton.new()
	option.theme = OPTION_THEME
	option.rect_min_size = OPTION_SIZE
	# The theme's dark text is hard to read on the disabled box (fixed settings).
	option.add_color_override("font_color_disabled", Color(1, 1, 1, 0.75))
	option.set_meta("setting", setting)
	var _e = option.connect("item_selected", self, "_on_option_item_selected", [option, setting])
	_e = option.connect("focus_entered", self, "_on_control_focus_entered", [setting])
	row.add_child(option)
	return option


func _on_option_item_selected(index: int, option: OptionButton, setting: String) -> void :
	if _net == null:
		return
	var value = option.get_item_id(index)
	if setting == "mode":
		value = ModeRegistry.MODES[value].id
	elif LOOT_SETTINGS.has(setting):
		value = value == 1
	_net.set_lobby_settings({setting: value})
