extends "res://weapons/ranged/carbon_bow/carbon_bow.gd"

# Primal Dread's carbon bow picks its next arrow (melee, ranged, elemental, engineering) at random
# and shows it on the bow. In a LAN session the host's pick reaches the clients (LanWaveSync,
# EVENT_CARBON_ARROW); the arrow's look goes with its projectile. LanGame comes from the
# weapon.gd extension.


func take_next_projectile_stat() -> int:
	var stat_hash: int = .take_next_projectile_stat()
	var wave_sync = LanGame.get_wave_sync()
	if wave_sync != null and wave_sync.is_host:
		wave_sync.on_carbon_bow_arrow(self)
	return stat_hash
