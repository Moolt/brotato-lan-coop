extends "res://singletons/coop_service.gd"

# 12 players during a LAN session, and a colour for each of them. The first 4 colours are
# vanilla's (coop_service.tscn); the lobby uses the same palette (UiKit.get_player_color).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

# [hue, value] of the 8 extra colours. get_player_color adds 0.5 saturation; with EXTRA_SATURATION
# they end up at about 0.8 like vanilla's, so only hue (and value, for brown) tells them apart.
# The hues sit between vanilla's cyan (0.47), orange (0.06), green (0.27) and yellow (0.15).
const EXTRA_SATURATION: = 0.3
const EXTRA_PLAYER_HUES: = [
	[0.60, 0.99], [0.90, 0.99], [0.74, 0.99], [0.0, 0.99], 
	[0.38, 0.99], [0.82, 0.99], [0.54, 0.99], [0.07, 0.62], 
]


# player_colors comes from coop_service.tscn, which is applied after _init.
func _ready() -> void :
	for hue_value in EXTRA_PLAYER_HUES:
		if player_colors.size() < LanGame.MAX_PLAYERS:
			player_colors.append(Color.from_hsv(hue_value[0], EXTRA_SATURATION, hue_value[1]))


func get_max_players():
	if LanGame.in_session():
		return LanGame.MAX_PLAYERS
	return .get_max_players()
