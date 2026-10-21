extends "res://entities/units/pet/jellyshield/jellyshield.gd"

# Every machine spawns its own jellyshields (Player.init, before LanWaveSync exists), and
# vanilla's orbit angle counts from that moment. In a LAN session the angle follows the wave
# timer instead (synced from the host), so the shields stand at the same place on every machine
# and enemy bullets stop at them on clients where they do on the host.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")


# Runs before vanilla's _physics_process, which adds delta and places the shield.
func _physics_process(delta: float) -> void :
	if not LanGame.in_session():
		return
	var main = get_tree().current_scene
	var wave_timer = main.get("_wave_timer") if main != null else null
	if wave_timer == null:
		return
	_angle = (wave_timer.wait_time - wave_timer.time_left - delta) * rotation_speed
