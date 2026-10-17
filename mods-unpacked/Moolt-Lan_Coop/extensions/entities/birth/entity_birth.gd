extends "res://entities/birth/entity_birth.gd"

# On LAN clients a spawn marker only shows where the host spawns something. Vanilla moves an
# enemy's marker elsewhere when a player stands on it; the host does that for its own marker and
# sends the new position (net/wave_sync.gd), so the client copy ignores its players.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


func _on_EntityBirth_body_entered(body: Node) -> void :
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and not wave_sync.is_host:
		return
	._on_EntityBirth_body_entered(body)
