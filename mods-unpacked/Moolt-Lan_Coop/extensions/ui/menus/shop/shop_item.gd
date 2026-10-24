extends "res://ui/menus/shop/shop_item.gd"

# The game mode may turn item locking off (LanMode.allows_item_locking: the draft shop, where a
# locked item would reserve shared stock).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func manage_lock_button_visibility() -> void :
	var mode = LanGame.get_mode()
	if mode != null and not mode.allows_item_locking():
		_lock_button.disable()
		_lock_button.hide()
		return
	.manage_lock_button_visibility()


func change_lock_status(button_pressed: bool) -> void :
	var mode = LanGame.get_mode()
	if button_pressed and mode != null and not mode.allows_item_locking():
		return
	.change_lock_status(button_pressed)
