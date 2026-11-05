extends "res://entities/units/enemies/crash_zone/basic/evil_mob/evil_mob.gd"

# The evil mob (crash zone and jungle) eats materials and evolves: another texture, more HP, and
# its health bar shows. Only the host's copy eats (clients' areas are off), so the host reports
# each evolution and the client's copy evolves too (LanWaveSync, EVENT_EVOLVE_MOB). LanGame comes
# from the enemy.gd extension.


func evolve(newEvolution: int) -> void :
	.evolve(newEvolution)
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_evil_mob_evolved(self, newEvolution)
