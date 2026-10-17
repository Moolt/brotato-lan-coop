extends "res://ui/menus/global/popup_manager.gd"

# Grows the per-player arrays to 12 slots (see LanGame). The pause menu adds popups for every player.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	LanGame.grow(_item_popups, null)
	LanGame.grow(_elements_hovered, null)
	LanGame.grow(_elements_focused, null)
	LanGame.grow(_elements_pressed, null)
	LanGame.grow(_stat_popups, null)
