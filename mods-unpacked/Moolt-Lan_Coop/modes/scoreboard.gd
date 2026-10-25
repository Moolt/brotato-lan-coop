extends Control

# In-wave HUD of a mode with scores (added by LanMode.on_wave_started): top right, one row per
# player in the mode's ranking (colour, name, the mode's columns, a note such as "out"; groups
# such as teams under a header row with their totals), and a banner line under the wave timer
# (LanMode.get_banner). Short toasts (show_toast) replace the banner for a moment. Refreshed when
# the mode state changes and a few times a second. Tab or the gamepad's Back button shows or
# hides the table (remembered in the config); the banner stays.
# It sits in UI/HUD, a MarginContainer: the HUD's margins put it level with the health bars.

const FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")

const FONT_SIZE: = 20
const BANNER_FONT_SIZE: = 30
const WIDTH: = 330.0
const BANNER_TOP: = 140.0
const REFRESH_INTERVAL: = 0.25
const TOAST_TIME: = 3.0
const MUTED_COLOR: = Color(0.6, 0.6, 0.6)

var _mode: Reference = null
var _main: Node = null
var _font: DynamicFont
var _banner_font: DynamicFont
var _panel: PanelContainer
var _grid: GridContainer
var _banner: Label
var _since_refresh: = 0.0
var _toast_left: = 0.0


func init(mode: Reference, main: Node) -> void :
	_mode = mode
	_main = main


func _ready() -> void :
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = FONT.duplicate()
	_font.size = FONT_SIZE
	_font.outline_size = 2
	_font.outline_color = Color.black
	_banner_font = FONT.duplicate()
	_banner_font.size = BANNER_FONT_SIZE
	_banner_font.outline_size = 3
	_banner_font.outline_color = Color.black

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.margin_left = - WIDTH
	_panel.margin_right = 0
	_panel.margin_top = 0
	_panel.visible = _mode.net.config.show_scoreboard
	_panel.self_modulate = Color(1, 1, 1, 0.75)
	add_child(_panel)
	_grid = GridContainer.new()
	_grid.add_constant_override("hseparation", 12)
	_grid.add_constant_override("vseparation", 2)
	_panel.add_child(_grid)

	_banner = Label.new()
	_banner.align = Label.ALIGN_CENTER
	_banner.autowrap = true
	_banner.anchor_right = 1.0
	_banner.margin_left = 300
	_banner.margin_right = - 300
	_banner.margin_top = BANNER_TOP
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_message_translation(false)
	_banner.add_font_override("font", _banner_font)
	add_child(_banner)

	var _e = _mode.connect("state_changed", self, "refresh")
	refresh()


func _exit_tree() -> void :
	if _mode != null and _mode.is_connected("state_changed", self, "refresh"):
		_mode.disconnect("state_changed", self, "refresh")


func _process(delta: float) -> void :
	_since_refresh += delta
	if _toast_left > 0.0:
		_toast_left -= delta
	if _since_refresh >= REFRESH_INTERVAL:
		refresh()


func _unhandled_input(event: InputEvent) -> void :
	var toggle: = false
	if event is InputEventKey:
		toggle = event.pressed and not event.echo and event.scancode == KEY_TAB
	elif event is InputEventJoypadButton:
		toggle = event.pressed and event.button_index == JOY_SELECT
	if not toggle:
		return
	get_tree().set_input_as_handled()
	_panel.visible = not _panel.visible
	_mode.net.config.show_scoreboard = _panel.visible
	_mode.net.config.save_config()


func show_toast(text: String) -> void :
	_toast_left = TOAST_TIME
	_banner.text = text
	_banner.visible = true


func refresh() -> void :
	_since_refresh = 0.0
	if not is_inside_tree():
		return
	var columns: Array = _mode.get_score_columns()
	_grid.columns = 2 + columns.size()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_add_cell("", MUTED_COLOR)
	_add_cell("", MUTED_COLOR, true)
	for column in columns:
		_add_cell(tr(column[1]), MUTED_COLOR)
	var rank: = 1
	var group: = - 1
	for player_index in _mode.get_ranking():
		if _mode.get_group(player_index) != group:
			group = _mode.get_group(player_index)
			if group >= 0:
				if rank > 1:
					# An empty row between groups.
					for _i in _grid.columns:
						_add_cell("", MUTED_COLOR)
				_add_group_row(group, columns)
				rank = 1
		var color: Color = CoopService.get_player_color(player_index)
		var note: String = _mode.get_player_note(player_index)
		var muted: bool = _mode.is_player_out(player_index)
		_add_cell(str(rank), MUTED_COLOR)
		var text: String = _mode.get_player_name(player_index)
		if not note.empty():
			text += " (" + note + ")"
		_add_cell(text, MUTED_COLOR if muted else color, true)
		for column in columns:
			_add_cell(str(_mode.get_score(column[0], player_index)), MUTED_COLOR if muted else Color.white)
		rank += 1
	_refresh_banner()


# A group's header: its title in its colour and its players' totals.
func _add_group_row(group: int, columns: Array) -> void :
	var color: Color = _mode.get_group_color(group)
	_add_cell("", color)
	_add_cell(_mode.get_group_title(group), color, true)
	for column in columns:
		var total: = 0
		for player_index in _mode.get_player_count():
			if _mode.get_group(player_index) == group:
				total += _mode.get_score(column[0], player_index)
		_add_cell(str(total), color)


func _refresh_banner() -> void :
	if _toast_left > 0.0:
		return
	_banner.text = _mode.get_banner(_main)
	_banner.visible = not _banner.text.empty()


# The name column takes the width the others leave (and clips long names); the others fit their
# text, right-aligned.
func _add_cell(text: String, color: Color, is_name: bool = false) -> void :
	var label: = Label.new()
	label.set_message_translation(false)
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_name:
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.align = Label.ALIGN_RIGHT
	label.add_font_override("font", _font)
	label.add_color_override("font_color", color)
	_grid.add_child(label)
