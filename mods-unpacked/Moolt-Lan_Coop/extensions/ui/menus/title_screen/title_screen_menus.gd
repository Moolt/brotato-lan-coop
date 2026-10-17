extends "res://ui/menus/title_screen/title_screen_menus.gd"

# Adds the "Multiplayer" main menu button (below Start) and the multiplayer menu + lobby pages.
# Opens the multiplayer menu on load if a session just ended with a reason (host left,
# rejected, ...), or the lobby if a session is still active.

const MultiplayerMenu = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/multiplayer_menu.gd")
const Lobby = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/lobby.gd")

var _lan_net: Node = null
var _multiplayer_menu: Control = null
var _lobby: Control = null
var _multiplayer_button: Button = null


func _ready() -> void :
	_lan_net = get_node_or_null("/root/LanNet")
	if _lan_net == null:
		return

	_multiplayer_menu = MultiplayerMenu.new()
	_multiplayer_menu.name = "LanMultiplayerMenu"
	_multiplayer_menu.hide()
	add_child(_multiplayer_menu)
	var _e = _multiplayer_menu.connect("back_button_pressed", self, "_on_LanMultiplayerMenu_back_button_pressed")
	_e = _multiplayer_menu.connect("lobby_requested", self, "_on_LanMultiplayerMenu_lobby_requested")

	_lobby = Lobby.new()
	_lobby.name = "LanLobby"
	_lobby.hide()
	add_child(_lobby)

	_add_multiplayer_button()
	_e = _lan_net.connect("session_ended", self, "_on_LanNet_session_ended")
	call_deferred("_restore_lan_page")


func _add_multiplayer_button() -> void :
	var start_button: Button = _main_menu.start_button
	_multiplayer_button = MyMenuButton.new()
	_multiplayer_button.name = "LanMultiplayerButton"
	_multiplayer_button.text = "MENU_MULTIPLAYER"
	_multiplayer_button.rect_min_size = start_button.rect_min_size
	_multiplayer_button.align = start_button.align
	_multiplayer_button.expand_icon = start_button.expand_icon
	_multiplayer_button.size_flags_horizontal = start_button.size_flags_horizontal

	var container: Control = _main_menu.left_container
	container.add_child(_multiplayer_button)
	container.move_child(_multiplayer_button, start_button.get_index() + 1)

	var mods_path: = _multiplayer_button.get_path_to(_main_menu.mods_button)
	_multiplayer_button.focus_neighbour_left = mods_path
	_multiplayer_button.focus_neighbour_right = mods_path
	var _e = _multiplayer_button.connect("pressed", self, "_on_MainMenu_multiplayer_button_pressed")


# Runs after TitleScreen._ready, which focuses the main menu.
func _restore_lan_page() -> void :
	if _lan_net.active and _lan_net.joined:
		switch(_main_menu, _multiplayer_menu)
		switch(_multiplayer_menu, _lobby)
	elif not _lan_net.last_end_reason.empty():
		switch(_main_menu, _multiplayer_menu)
		_multiplayer_menu.show_status(_lan_net.last_end_reason, true)
		_lan_net.last_end_reason = ""
	elif _lan_net.active:
		# Still connecting (cannot normally happen on a fresh title screen): start over.
		_lan_net.leave()


func _on_MainMenu_multiplayer_button_pressed() -> void :
	switch(_main_menu, _multiplayer_menu)


func _on_LanMultiplayerMenu_back_button_pressed() -> void :
	switch(_multiplayer_menu, _main_menu)


func _on_LanMultiplayerMenu_lobby_requested() -> void :
	switch(_multiplayer_menu, _lobby)


func _on_LanNet_session_ended(reason: String) -> void :
	if _current_page != _lobby:
		return
	switch(_lobby, _multiplayer_menu)
	if not reason.empty():
		_multiplayer_menu.show_status(reason, true)
		_lan_net.last_end_reason = ""
