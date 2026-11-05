extends "res://effect_behaviors/scenes/dig_site_scene_effect_behavior.gd"

# Dig sites (Primal Dread items) lie where they are on every machine of a session: their places
# and dig times are rolled from the shared wave seed. Only the host digs; LanWaveSync sends the
# state (entities/gpe/dig_site/dig_site.gd extension).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func spawn_dig_sites(container: Node) -> void :
	var shared: bool = LanGame.begin_shared_random("dig_sites")
	.spawn_dig_sites(container)
	if shared:
		LanGame.end_shared_random()
