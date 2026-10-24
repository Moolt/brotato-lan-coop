extends "res://singletons/zone_service.gd"

# During a LAN session the arena grows with the player count (LanGame.get_arena_factor).
# main.gd passes the zone it gives this function to the tile map, the walls and the wave
# manager as well, and the camera bounds come from current_zone_rect, so they all follow.
# The zone is main's own duplicate, so scaling it leaves the zone resource untouched.
# The game mode has the last word on the size (LanMode.get_arena_size: two halves in Team Race).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func set_current_zone(p_current_zone: ZoneData) -> void :
	if LanGame.in_session():
		var size: Vector2 = LanGame.get_mode().get_arena_size(Vector2(p_current_zone.width, p_current_zone.height), RunData.get_player_count())
		p_current_zone.width = int(size.x)
		p_current_zone.height = int(size.y)
	.set_current_zone(p_current_zone)
