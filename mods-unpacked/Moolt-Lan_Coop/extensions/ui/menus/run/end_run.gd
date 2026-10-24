extends "res://ui/menus/run/end_run.gd"

# The LAN end screen can show any player's stats, weapons and items: a player list left of the
# stats (ui/end_run_player_list.gd, with the mode's ranking and scores) picks the player, the own
# one at first. The solo view puts that player into slot 0 (SoloView.show_player), so vanilla's
# code for player 0 shows it. Rewards stay the own ones.

# Not "LanGame": the base_end_run.gd extension, which may become the parent, declares that one.
const EndRunLanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const EndRunPlayerList = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/end_run_player_list.gd")

var _lan_player_list: PanelContainer = null


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
	for stat in _stats_container.primary_stats + _stats_container.secondary_stats:
		stat.update_player_stat(0)
	_weapons_container.set_data("WEAPONS", Category.WEAPON, RunData.get_player_weapons(0))
	_items_container.set_data("ITEMS", Category.ITEM, RunData.get_player_items(0), true, true)
	call_deferred("_lan_sort_inventories")


func _lan_sort_inventories() -> void :
	_items_container._elements.emit_signal("need_to_sort_inventory")
	_weapons_container._elements.emit_signal("need_to_sort_inventory")
