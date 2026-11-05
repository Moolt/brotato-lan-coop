extends "res://effect_behaviors/scenes/poacher_zone_scene_effect_behavior.gd"

# Poacher zones (Primal Dread items) start where they are on every machine of a session: their
# places are rolled from the shared wave seed. Moves and kill marks happen on the host and reach
# the clients through LanWaveSync.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func spawn_poacher_zone(container: Node) -> void :
	var shared: bool = LanGame.begin_shared_random("poacher_zones")
	.spawn_poacher_zone(container)
	if shared:
		LanGame.end_shared_random()
