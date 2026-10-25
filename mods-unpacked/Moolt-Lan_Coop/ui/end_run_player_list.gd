extends PanelContainer

# The LAN end screen's player list, left of the stats and styled like them (stats_container.tscn):
# every player with character, and in modes with scores the winner, the rank, the mode's note
# and the scores, in the mode's ranking (the character only as its icon then). The rows scroll
# if they don't fit (12 players fit at 1080p), so the list never grows the end screen. Pressing a row shows that player's stats, weapons and items (signal
# player_selected); the shown row is highlighted, the own one at first.

signal player_selected(player_index)

const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const NAME_FONT = preload("res://resources/fonts/actual/base/font_26.tres")
const DETAIL_FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")

const WIDTH: = 400.0
const ROW_HEIGHT: = 70.0
const ICON_SIZE: = 56.0
const DETAIL_FONT_SIZE: = 20
const WINNER_COLOR: = Color(1.0, 0.85, 0.3)
const DETAIL_COLOR: = Color(1, 1, 1, 0.7)

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
		result.autowrap = true
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
	row_column.add_constant_override("separation", 6)
	_scroll.add_child(row_column)

	var detail_font: DynamicFont = DETAIL_FONT.duplicate()
	detail_font.size = DETAIL_FONT_SIZE
	var player_indices: Array = _mode.get_ranking() if ranked else range(_solo_view.get_player_count())
	# Groups (teams) under a header in their colour; ranks count within the group.
	var rank: = 0
	var group: = - 1
	for player_index in player_indices:
		if ranked and _mode.get_group(player_index) != group:
			group = _mode.get_group(player_index)
			if group >= 0:
				var header: = _new_label(_mode.get_group_title(group), NAME_FONT)
				header.add_color_override("font_color", _mode.get_group_color(group))
				header.clip_text = false
				header.autowrap = true
				row_column.add_child(header)
				rank = 0
		rank += 1
		var row: = _new_row(player_index, rank if ranked else 0, detail_font)
		row_column.add_child(row)
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


func _new_row(player_index: int, rank: int, detail_font: Font) -> Button:
	var row: Button = MyMenuButton.new()
	row.rect_min_size = Vector2(0, ROW_HEIGHT)
	row.clip_text = true
	var _e = row.connect("pressed", self, "_on_row_pressed", [player_index])

	var line: = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_constant_override("separation", 10)
	line.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	line.margin_left = 10
	line.margin_right = - 10
	row.add_child(line)

	var character = _solo_view.get_player_data(player_index).current_character
	if rank > 0:
		var rank_label: = _new_label("%d." % rank, NAME_FONT)
		rank_label.rect_min_size = Vector2(36, 0)
		line.add_child(rank_label)
	var icon: = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = character.icon if character != null else null
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(icon)

	var text: = VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGN_CENTER
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_constant_override("separation", 0)
	line.add_child(text)

	var player_name: String = _mode.get_player_name(player_index)
	var name_label: = _new_label(player_name, NAME_FONT)
	name_label.add_color_override("font_color", UiKit.get_player_color(player_index))
	text.add_child(name_label)

	var details: = []
	if rank > 0:
		var note: String = _mode.get_player_note(player_index)
		if not note.empty():
			details.append(note)
		for score_column in _mode.get_score_columns():
			details.append("%s %d" % [tr(score_column[1]), _mode.get_score(score_column[0], player_index)])
	elif character != null:
		details.append(tr(character.name))
	text.add_child(_new_detail_label(PoolStringArray(details).join(" · "), detail_font))
	return row


func _new_detail_label(text: String, font: Font) -> Label:
	var label: = _new_label(text, font)
	label.add_color_override("font_color", DETAIL_COLOR)
	return label


func _new_label(text: String, font: Font) -> Label:
	var label: = Label.new()
	label.set_message_translation(false)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.clip_text = true
	label.add_font_override("font", font)
	return label


func _on_row_pressed(player_index: int) -> void :
	emit_signal("player_selected", player_index)
