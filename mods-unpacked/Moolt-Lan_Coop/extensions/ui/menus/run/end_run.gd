extends "res://ui/menus/run/end_run.gd"

# The LAN end screen can show any player's stats, weapons and items: a dropdown next to Exit picks
# the player, the own one at first. The solo view puts that player into slot 0
# (SoloView.show_player), so vanilla's code for player 0 shows it. Rewards stay the own ones.
# Players are listed by index; sorting them by kills needs per-player kill counts first.

# Not "LanGame": the base_end_run.gd extension, which may become the parent, declares that one.
const EndRunLanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")
const LAN_OPTION_THEME = preload("res://resources/themes/zone_selection_button_theme.tres")

var _lan_player_option: OptionButton = null


# Runs after vanilla's _ready.
func _ready() -> void :
	var solo_view = _lan_get_solo_view()
	if solo_view == null or solo_view.get_player_count() < 2:
		return
	_lan_player_option = OptionButton.new()
	_lan_player_option.theme = LAN_OPTION_THEME
	_lan_player_option.rect_min_size = Vector2(500, 0)
	for player_index in solo_view.get_player_count():
		_lan_player_option.add_item(_lan_get_player_label(solo_view, player_index), player_index)
	_lan_player_option.select(_lan_player_option.get_item_index(solo_view.shown_index))
	var _e = _lan_player_option.connect("item_selected", self, "_on_LanPlayerOption_item_selected")

	var buttons: Node = _exit_button.get_parent()
	buttons.add_child(_lan_player_option)
	buttons.move_child(_lan_player_option, _exit_button.get_index())
	var option_path: NodePath = _exit_button.get_path_to(_lan_player_option)
	_exit_button.focus_neighbour_left = option_path
	_exit_button.focus_neighbour_right = option_path
	var exit_path: = _lan_player_option.get_path_to(_exit_button)
	_lan_player_option.focus_neighbour_left = exit_path
	_lan_player_option.focus_neighbour_right = exit_path


func _lan_get_solo_view():
	if not EndRunLanGame.in_session():
		return null
	var solo_view = EndRunLanGame.get_lan_net().solo_view
	return solo_view if solo_view.active else null


func _lan_get_player_label(solo_view, player_index: int) -> String:
	var character_name: String = tr(solo_view.get_player_data(player_index).current_character.name)
	var player_name: String = EndRunLanGame.get_player_name(player_index)
	return character_name if player_name.empty() else "%s - %s" % [player_name, character_name]


func _on_LanPlayerOption_item_selected(index: int) -> void :
	var solo_view = _lan_get_solo_view()
	if solo_view == null or not solo_view.show_player(_lan_player_option.get_item_id(index)):
		return
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
