extends "res://singletons/generation_zone_manager.gd"

# The zone's decoration (Primal Dread's jungle and the Abyss: ferns, trees, rocks around and
# across the map) is rolled at random in main's _ready. In a LAN session every machine rolls it
# from the shared wave seed, so everyone sees the same map.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _generate_all_structures() -> void :
	var shared: bool = LanGame.begin_shared_random("decoration")
	._generate_all_structures()
	if shared:
		LanGame.end_shared_random()
