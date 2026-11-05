extends "res://entities/units/movement_behaviors/stay_edges_of_map_movement_behavior.gd"

# On a LAN client the copy doesn't tween between the map's edges (Primal Dread's brachiosaurus):
# its position comes from the host's snapshot.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func move_to_new_edge():
	if LanGame.is_wave_client():
		return
	.move_to_new_edge()


func move_away():
	if LanGame.is_wave_client():
		return
	.move_away()
