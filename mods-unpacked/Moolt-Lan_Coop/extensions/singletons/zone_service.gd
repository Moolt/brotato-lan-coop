extends "res://singletons/zone_service.gd"

# During a LAN session the arena grows with the player count (LanGame.get_arena_factor).
# main.gd passes the zone it gives this function to the tile map, the walls and the wave
# manager as well, and the camera bounds come from current_zone_rect, so they all follow.
# The zone is main's own duplicate, so scaling it leaves the zone resource untouched.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func set_current_zone(p_current_zone: ZoneData) -> void :
	if LanGame.in_session():
		var factor: = LanGame.get_arena_factor(RunData.get_player_count())
		p_current_zone.width = int(round(p_current_zone.width * factor))
		p_current_zone.height = int(round(p_current_zone.height * factor))
	.set_current_zone(p_current_zone)
