extends "res://singletons/coop_service.gd"

# 12 players during a LAN session, and a colour for each of them. The first 4 colours are
# vanilla's (coop_service.tscn); the lobby uses the same palette (UiKit.get_player_color).

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

const EXTRA_PLAYER_COLORS: = [
	Color(0.72, 0.84, 0.99), Color(0.99, 0.72, 0.88), Color(0.84, 0.75, 0.99), Color(0.99, 0.75, 0.75), 
	Color(0.70, 0.96, 0.99), Color(0.86, 0.86, 0.86), Color(0.99, 0.86, 0.72), Color(0.78, 0.99, 0.80), 
]


# player_colors comes from coop_service.tscn, which is applied after _init.
func _ready() -> void :
	for color in EXTRA_PLAYER_COLORS:
		if player_colors.size() < LanGame.MAX_PLAYERS:
			player_colors.append(color)


func get_max_players():
	if LanGame.in_session():
		return LanGame.MAX_PLAYERS
	return .get_max_players()
