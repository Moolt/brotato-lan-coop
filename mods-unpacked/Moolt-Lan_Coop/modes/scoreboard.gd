extends Control

# In-wave HUD of a mode with scores (added by LanMode.on_wave_started): top right, one row per
# player in the mode's ranking (rank, colour bar, name shortened with "...", the mode's status
# (an icon such as the crown, or the wave a player died in as "(W7)"), greyed while the player is
# dead or out, the mode's columns headed by their icons; the own row highlighted; groups such as teams
# under a header row with the tinted team flag, the group's name and status and its totals; a dark
# rounded panel), and a banner
# line under the wave timer
# (LanMode.get_banner). Short toasts (show_toast) replace the banner for a moment. Refreshed when
# the mode state changes and a few times a second. Tab or the gamepad's Back button shows or
# hides the table (remembered in the config); the banner stays.
# It sits in UI/HUD, a MarginContainer: the HUD's margins put it level with the health bars.

const FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")

const FONT_SIZE: = 20
const BANNER_FONT_SIZE: = 30
const WIDTH: = 330.0
const VALUE_WIDTH: = 44.0
const RANK_WIDTH: = 20.0
const ICON_SIZE: = 24.0
const STATUS_ICON_SIZE: = 22.0
const BAR_HEIGHT: = 16.0
const BAR_WIDTH: = 4.0
const GROUP_GAP: = 6.0
const PANEL_COLOR: = Color(0, 0, 0, 0.55)
const OWN_ROW_COLOR: = Color(1, 1, 1, 0.12)
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
# The own row's name cell: the grid draws the highlight behind its row.
var _own_cell: Control = null
var _own_row_style: StyleBox = UiKit.new_rounded_style(OWN_ROW_COLOR, 5)
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
	_panel.add_stylebox_override("panel", UiKit.new_rounded_style(PANEL_COLOR, 10, 8, 6))
	add_child(_panel)
	_grid = GridContainer.new()
	_grid.add_constant_override("hseparation", 6)
	_grid.add_constant_override("vseparation", 2)
	var _e = _grid.connect("sort_children", _grid, "update")
	_e = _grid.connect("draw", self, "_on_Grid_draw")
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

	_e = _mode.connect("state_changed", self, "refresh")
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
	_grid.columns = 3 + columns.size()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_own_cell = null
	_add_empty_cells(3)
	for column in columns:
		var header: = HBoxContainer.new()
		header.alignment = BoxContainer.ALIGN_END
		header.rect_min_size = Vector2(VALUE_WIDTH, 0)
		header.add_child(UiKit.new_icon(column[2], Vector2(ICON_SIZE, ICON_SIZE)))
		_grid.add_child(header)
	var rank: = 1
	var group: = - 1
	for player_index in _mode.get_ranking():
		if _mode.get_group(player_index) != group:
			group = _mode.get_group(player_index)
			if group >= 0:
				if rank > 1:
					# A gap between groups.
					_add_empty_cells(_grid.columns, GROUP_GAP)
				_add_group_row(group, columns)
				rank = 1
		var status: Dictionary = _mode.get_player_status(player_index)
		var muted: bool = status.get("muted", false) or _is_dead(player_index)
		var label: = _add_label(str(rank), MUTED_COLOR)
		label.rect_min_size = Vector2(RANK_WIDTH, 0)
		label.align = Label.ALIGN_RIGHT
		_grid.add_child(UiKit.new_player_bar(player_index, BAR_HEIGHT, BAR_WIDTH))
		var name_cell: = _new_name_cell(UiKit.new_name_label(_mode.get_player_name(player_index), MUTED_COLOR if muted else CoopService.get_player_color(player_index), _font), status)
		if player_index == _mode.get_local_index():
			_own_cell = name_cell
		for column in columns:
			_add_value(_mode.get_score(column[0], player_index), MUTED_COLOR if muted else Color.white)
		rank += 1
	_grid.update()
	_refresh_banner()


func _is_dead(player_index: int) -> bool:
	if not is_instance_valid(_main) or player_index < 0 or player_index >= _main._players.size():
		return false
	var player = _main._players[player_index]
	return is_instance_valid(player) and player.dead


# A group's header: the tinted team flag in the rank column, its name and status, its players'
# totals.
func _add_group_row(group: int, columns: Array) -> void :
	var color: Color = _mode.get_group_color(group)
	_grid.add_child(UiKit.new_team_icon(color, STATUS_ICON_SIZE))
	_add_empty_cells(1)
	_new_name_cell(UiKit.new_icon_value(null, _mode.get_group_title(group), _font, color), _mode.get_group_status(group), color)
	for column in columns:
		var total: = 0
		for player_index in _mode.get_player_count():
			if _mode.get_group(player_index) == group:
				total += _mode.get_score(column[0], player_index)
		_add_value(total, color)


# The name column takes the width the others leave; a status icon (and its short text) follows.
func _new_name_cell(content: Control, status: Dictionary, status_color: Color = MUTED_COLOR) -> Control:
	var cell: = HBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_constant_override("separation", 3)
	if not status.empty():
		cell.add_child(content)
		cell.add_child(UiKit.new_icon_value(status.icon, status.get("text", ""), _font, status_color, STATUS_ICON_SIZE))
	else:
		cell.add_child(content)
	_grid.add_child(cell)
	return cell


func _add_value(value: int, color: Color) -> void :
	var label: = _add_label(str(value), color)
	label.align = Label.ALIGN_RIGHT
	label.rect_min_size = Vector2(VALUE_WIDTH, 0)


func _add_empty_cells(count: int, height: float = 0.0) -> void :
	for _i in count:
		var cell: = Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.rect_min_size = Vector2(0, height)
		_grid.add_child(cell)


func _add_label(text: String, color: Color) -> Label:
	var label: = Label.new()
	label.set_message_translation(false)
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.valign = Label.VALIGN_CENTER
	label.add_font_override("font", _font)
	label.add_color_override("font_color", color)
	_grid.add_child(label)
	return label


# Behind the own row, across the whole table.
func _on_Grid_draw() -> void :
	if is_instance_valid(_own_cell) and _own_cell.get_parent() == _grid:
		_grid.draw_style_box(_own_row_style, Rect2(- 4, _own_cell.rect_position.y - 1, _grid.rect_size.x + 8, _own_cell.rect_size.y + 2))


func _refresh_banner() -> void :
	if _toast_left > 0.0:
		return
	_banner.text = _mode.get_banner(_main)
	_banner.visible = not _banner.text.empty()
