extends "res://ui/menus/run/end_run.gd"

# The LAN end screen can show any player's stats, weapons and items: a player list left of the
# stats (ui/end_run_player_list.gd, with the mode's ranking and scores) picks the player, the own
# one at first. The solo view puts that player into slot 0 (SoloView.show_player), so vanilla's
# code for player 0 shows it. Rewards stay the own ones.
# The stats panel shows the shown player's name as its title, and under "Current Level" rows like
# vanilla's for the character and the match: the mode's score columns, or the kills in modes
# without scores.

# Not "LanGame": the base_end_run.gd extension, which may become the parent, declares that one.
const EndRunLanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const EndRunPlayerList = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/end_run_player_list.gd")
const EndRunUiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const STAT_ROW_SCENE = preload("res://ui/menus/shop/stat_container.tscn")

var _lan_player_list: PanelContainer = null
var _lan_character_row: Control = null
# [stat row, score key]
var _lan_score_rows: = []


# Runs after vanilla's _ready.
func _ready() -> void :
	var solo_view = _lan_get_solo_view()
	if solo_view == null or solo_view.get_player_count() < 2:
		return
	_lan_player_list = EndRunPlayerList.new()
	_lan_player_list.init(EndRunLanGame.get_mode(), solo_view)
	var _e = _lan_player_list.connect("player_selected", self, "_on_LanPlayerList_player_selected")
	# Room for the list: the inventories get fewer columns (vanilla's 6 + 5 weapons and rewards,
	# 12 items fill the screen's width).
	_weapons_container.reserve_column_count = 5
	_progress_container.reserve_column_count = 3
	_items_container.reserve_column_count = 9
	var panel_row: Node = _stats_container.get_parent()
	panel_row.add_child(_lan_player_list)
	panel_row.move_child(_lan_player_list, _stats_container.get_index())
	_lan_add_stat_rows()
	_lan_update_stat_rows(solo_view.shown_index)

	# Exit <-> the shown player's row.
	var own_row: Button = _lan_player_list.get_row(solo_view.shown_index)
	_exit_button.focus_neighbour_left = _exit_button.get_path_to(own_row)
	_exit_button.focus_neighbour_top = _exit_button.get_path_to(own_row)
	for player_index in _lan_player_list.rows:
		var row: Button = _lan_player_list.rows[player_index]
		row.focus_neighbour_right = row.get_path_to(_exit_button)
		if row.focus_neighbour_bottom.is_empty():
			row.focus_neighbour_bottom = row.get_path_to(_exit_button)


func _lan_get_solo_view():
	if not EndRunLanGame.in_session():
		return null
	var solo_view = EndRunLanGame.get_lan_net().solo_view
	return solo_view if solo_view.active else null


func _on_LanPlayerList_player_selected(player_index: int) -> void :
	var solo_view = _lan_get_solo_view()
	if solo_view == null or not solo_view.show_player(player_index):
		return
	_lan_player_list.select(player_index)
	var row_path: NodePath = _exit_button.get_path_to(_lan_player_list.get_row(player_index))
	_exit_button.focus_neighbour_left = row_path
	_exit_button.focus_neighbour_top = row_path
	# update_player_stats only covers the open tab.
	_stats_container.general_stats[0].update_info(0)
	_lan_update_stat_rows(player_index)
	for stat in _stats_container.primary_stats + _stats_container.secondary_stats:
		stat.update_player_stat(0)
	_weapons_container.set_data("WEAPONS", Category.WEAPON, RunData.get_player_weapons(0))
	_items_container.set_data("ITEMS", Category.ITEM, RunData.get_player_items(0), true, true)
	call_deferred("_lan_sort_inventories")


func _lan_sort_inventories() -> void :
	_items_container._elements.emit_signal("need_to_sort_inventory")
	_weapons_container._elements.emit_signal("need_to_sort_inventory")


func _lan_add_stat_rows() -> void :
	var mode = EndRunLanGame.get_mode()
	_lan_character_row = _lan_new_stat_row(null, "")
	var columns: Array = mode.get_score_columns()
	if columns.empty():
		columns = [[mode.KILLS, "LAN_SCORE_KILLS", mode.KILLS_ICON]]
	for column in columns:
		_lan_score_rows.append([_lan_new_stat_row(column[2], column[1]), column[0]])


# A row like vanilla's stat rows (stat_container.tscn), filled here instead of from a stat.
func _lan_new_stat_row(icon: Texture, label_key: String) -> Control:
	var row: Control = STAT_ROW_SCENE.instance()
	row.focus_mode = Control.FOCUS_NONE
	_stats_container._general_stats.add_child(row)
	row.get_node("VBoxContainer/HBoxContainer/Icon").texture = icon
	# No hover or focus: vanilla's handlers would look up a stat for the row.
	row.get_node("VBoxContainer/HBoxContainer").mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.get_node("VBoxContainer/HBoxContainer/Label").mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.get_node("VBoxContainer/HBoxContainer/Label").focus_mode = Control.FOCUS_NONE
	row.get_node("VBoxContainer/HBoxContainer/Label").text = label_key
	row.get_node("VBoxContainer/HBoxContainer/Value").text = ""
	return row


func _lan_update_stat_rows(player_index: int) -> void :
	var solo_view = _lan_get_solo_view()
	if solo_view == null or _lan_character_row == null:
		return
	var mode = EndRunLanGame.get_mode()
	var title: Label = _stats_container.title_label
	title.set_message_translation(false)
	title.text = mode.get_player_name(player_index)
	title.add_color_override("font_color", EndRunUiKit.get_player_color(player_index))
	var character = solo_view.get_player_data(player_index).current_character
	if character != null:
		_lan_character_row.get_node("VBoxContainer/HBoxContainer/Icon").texture = character.icon
		_lan_character_row.get_node("VBoxContainer/HBoxContainer/Label").text = character.name
	for score_row in _lan_score_rows:
		score_row[0].get_node("VBoxContainer/HBoxContainer/Value").text = str(mode.get_score(score_row[1], player_index))
