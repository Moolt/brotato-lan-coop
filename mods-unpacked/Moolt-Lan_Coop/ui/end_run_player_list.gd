extends PanelContainer

# The LAN end screen's player list, left of the stats and styled like them (stats_container.tscn):
# one compact row per player (colour bar, character icon, name shortened with "..."), and in modes
# with scores the winner line, the rank and the first score column (with its icon), in the mode's
# ranking; players who are out are greyed, with the wave they died in. Teams sit in a frame in
# their colour (faded for a team that is out) whose header has the tinted team flag, the team's
# name (and wave when out) and its total of the first column. Only the status' text is shown, no
# icons (crown, boss): the winner line says who won. Everything else (the
# character, all scores) is in the stats panel (end_run.gd extension). The rows scroll if they
# don't fit, so the list never grows the end screen. Pressing a row shows that player's stats,
# weapons and items (signal player_selected); the shown row is highlighted, the own one at first.

signal player_selected(player_index)

const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const NAME_FONT = preload("res://resources/fonts/actual/base/font_26.tres")
const VALUE_FONT = preload("res://resources/fonts/actual/base/font_22.tres")
const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")

const WIDTH: = 400.0
const ROW_HEIGHT: = 44.0
const ICON_SIZE: = 40.0
const VALUE_ICON_SIZE: = 26.0
const TEAM_ICON_SIZE: = 30.0
const RANK_WIDTH: = 28.0
const WINNER_COLOR: = Color(1.0, 0.85, 0.3)
const MUTED_COLOR: = Color(1, 1, 1, 0.6)
const MUTED_MODULATE: = Color(1, 1, 1, 0.45)

var rows: = {}

var _mode: Reference = null
var _solo_view: Reference = null
var _scroll: ScrollContainer = null


func init(mode: Reference, solo_view: Reference) -> void :
	_mode = mode
	_solo_view = solo_view


func _ready() -> void :
	self_modulate = Color(1, 1, 1, 0.478431)
	rect_min_size = Vector2(WIDTH, 0)
	theme = BASE_THEME

	var margin: = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_constant_override("margin_" + side, 15)
	add_child(margin)
	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 10)
	margin.add_child(column)

	var title: = Label.new()
	title.text = "LAN_END_PLAYERS"
	title.align = Label.ALIGN_CENTER
	column.add_child(title)

	var ranked: bool = _mode.has_results()
	if ranked:
		var result: = Label.new()
		result.set_message_translation(false)
		result.text = _mode.get_result_text()
		result.align = Label.ALIGN_CENTER
		result.add_font_override("font", NAME_FONT)
		result.add_color_override("font_color", WINNER_COLOR)
		column.add_child(result)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.scroll_horizontal_enabled = false
	_scroll.follow_focus = true
	column.add_child(_scroll)
	var row_column: = VBoxContainer.new()
	row_column.size_flags_horizontal = SIZE_EXPAND_FILL
	row_column.add_constant_override("separation", 4)
	_scroll.add_child(row_column)

	var score_column: Array = _mode.get_score_columns()[0] if ranked else []
	var player_indices: Array = _mode.get_ranking() if ranked else range(_solo_view.get_player_count())
	# Groups (teams) in a frame in their colour; ranks count within the group.
	var rank: = 0
	var group: = - 1
	var parent: Container = row_column
	for player_index in player_indices:
		if ranked and _mode.get_group(player_index) != group:
			group = _mode.get_group(player_index)
			parent = row_column
			if group >= 0:
				var frame: = UiKit.new_team_frame(_mode.get_group_color(group), _mode.get_group_status(group).get("out", false))
				row_column.add_child(frame)
				parent = frame.get_child(0)
				parent.add_child(_new_group_header(group, score_column))
				rank = 0
		rank += 1
		var row: = _new_row(player_index, rank if ranked else 0, score_column)
		parent.add_child(row)
		rows[player_index] = row

	var previous: Button = null
	for player_index in player_indices:
		var row: Button = rows[player_index]
		if previous != null:
			row.focus_neighbour_top = row.get_path_to(previous)
			previous.focus_neighbour_bottom = previous.get_path_to(row)
		previous = row
	select(_solo_view.shown_index)
	_scroll_to_shown()


# The own row may be below the fold with many players; the rows have their size a frame later.
func _scroll_to_shown() -> void :
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var row = rows.get(_solo_view.shown_index)
	if is_instance_valid(row) and is_instance_valid(_scroll):
		_scroll.ensure_control_visible(row)


# Highlights the shown player's row.
func select(player_index: int) -> void :
	for index in rows:
		var row: Button = rows[index]
		if row.has_meta("original_flat"):
			row.set_meta("original_flat", index != player_index)
		else:
			row.flat = index != player_index


func get_row(player_index: int) -> Button:
	return rows.get(player_index)


# The tinted team flag, the team's name and status text ("(W7)"), the team's total.
func _new_group_header(group: int, score_column: Array) -> Control:
	var color: Color = _mode.get_group_color(group)
	var margin: = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_constant_override("margin_left", 6)
	margin.add_constant_override("margin_right", 10)
	var header: = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_constant_override("separation", 6)
	header.rect_min_size = Vector2(0, 34)
	margin.add_child(header)
	header.add_child(UiKit.new_team_icon(color, TEAM_ICON_SIZE))
	header.add_child(UiKit.new_icon_value(null, _mode.get_group_title(group), VALUE_FONT, color))
	var status_text: String = _mode.get_group_status(group).get("text", "")
	if not status_text.empty():
		header.add_child(UiKit.new_icon_value(null, status_text, VALUE_FONT, color))
	var spacer: = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)
	if not score_column.empty():
		var total: = 0
		for player_index in _mode.get_player_count():
			if _mode.get_group(player_index) == group:
				total += _mode.get_score(score_column[0], player_index)
		header.add_child(UiKit.new_icon_value(score_column[2], str(total), VALUE_FONT, Color.white, VALUE_ICON_SIZE))
	return margin


func _new_row(player_index: int, rank: int, score_column: Array) -> Button:
	var row: Button = MyMenuButton.new()
	row.rect_min_size = Vector2(0, ROW_HEIGHT)
	row.clip_text = true
	UiKit.style_row_button(row)
	var _e = row.connect("pressed", self, "_on_row_pressed", [player_index])

	var line: = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_constant_override("separation", 8)
	line.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	line.margin_right = - 10
	row.add_child(line)

	var status: Dictionary = _mode.get_player_status(player_index) if rank > 0 else {}
	var muted: bool = status.get("muted", false)
	if muted:
		line.modulate = MUTED_MODULATE

	line.add_child(UiKit.new_player_bar(player_index))
	if rank > 0:
		var rank_label: = Label.new()
		rank_label.set_message_translation(false)
		rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rank_label.text = "%d." % rank
		rank_label.align = Label.ALIGN_RIGHT
		rank_label.valign = Label.VALIGN_CENTER
		rank_label.size_flags_vertical = SIZE_FILL
		rank_label.rect_min_size = Vector2(RANK_WIDTH, 0)
		rank_label.add_font_override("font", VALUE_FONT)
		rank_label.add_color_override("font_color", MUTED_COLOR)
		line.add_child(rank_label)
	var character = _solo_view.get_player_data(player_index).current_character
	line.add_child(UiKit.new_icon(character.icon if character != null else null, Vector2(ICON_SIZE, ICON_SIZE)))

	var name_color: Color = MUTED_COLOR if muted else UiKit.get_player_color(player_index)
	line.add_child(UiKit.new_name_label(_mode.get_player_name(player_index), name_color, NAME_FONT))
	if not status.get("text", "").empty():
		line.add_child(UiKit.new_icon_value(null, status.text, VALUE_FONT, MUTED_COLOR))
	if not score_column.empty():
		line.add_child(UiKit.new_icon_value(score_column[2], str(_mode.get_score(score_column[0], player_index)), VALUE_FONT, Color.white, VALUE_ICON_SIZE))
	return row


func _on_row_pressed(player_index: int) -> void :
	emit_signal("player_selected", player_index)
