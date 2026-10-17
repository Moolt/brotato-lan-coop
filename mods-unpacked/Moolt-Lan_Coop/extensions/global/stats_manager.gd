extends "res://global/stats_manager.gd"

# Grows the per-player queues to 12 slots (see LanGame).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _init() -> void :
	LanGame.grow(_structure_queues, {})
	LanGame.grow(_pet_queues, {})
