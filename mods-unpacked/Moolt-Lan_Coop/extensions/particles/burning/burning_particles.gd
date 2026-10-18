extends "res://particles/burning/burning_particles.gd"

# Every unit carries burning particles with a SpreadArea (r = 128, enemies mask) that vanilla
# leaves enabled from the start and only disables after a burn, so it pairs with every enemy and
# hitbox nearby (perf). It only matters while burning: Unit.apply_burning enables it then
# (activate_spread). In a session it starts disabled.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _ready() -> void :
	if LanGame.in_session():
		deactivate_spread()
