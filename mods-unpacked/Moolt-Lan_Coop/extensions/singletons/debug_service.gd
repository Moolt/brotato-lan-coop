extends "res://singletons/debug_service.gd"

# Grows the per-player arrays to 12 slots (see LanGame). log_run_info's default arguments
# have 4 slots and it indexes them for every player.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	LanGame.grow(debug_items_added, false)
	LanGame.grow(debug_weapons_added, false)
	LanGame.grow(starting_weapons_removed, false)


func log_run_info(upgrades: Array = [], consumables: Array = []) -> void :
	LanGame.grow(upgrades, [])
	LanGame.grow(consumables, [])
	.log_run_info(upgrades, consumables)
