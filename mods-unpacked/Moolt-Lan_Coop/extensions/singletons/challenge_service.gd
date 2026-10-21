extends "res://singletons/challenge_service.gd"

# What a LAN session counts for (game/session_progress.gd): during a wave, challenges count for
# the whole team. The host, which runs the real wave, completes them and forwards each one to
# the clients (LanNet.forward_challenge); clients ignore their own in-wave completions, since
# their wave is a copy. Lifetime-count challenges (check_counted_challenges) stay each machine's
# own; clients check them once the wave's counters arrived. Outside a wave (the solo view
# between waves, the own character's run win) everything is vanilla.

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

# Completes locally, not forwarded (counted challenges, forwarded ones on clients).
var _lan_local_only: = false


func complete_challenge(chal_id: int, also_complete_platform_challenge: bool = true) -> void :
	var lan_net = LanGame.get_lan_net()
	if _lan_local_only or not _lan_in_team_wave(lan_net):
		.complete_challenge(chal_id, also_complete_platform_challenge)
		return
	if lan_net.is_host:
		.complete_challenge(chal_id, also_complete_platform_challenge)
		lan_net.forward_challenge(chal_id)


# Vanilla returns at once when this machine completed the challenge before; on the host the
# clients may not have it yet.
func try_complete_challenge(chal_id: int, value: int, check_below: bool = false):
	if _lan_local_only or not _lan_in_team_wave(LanGame.get_lan_net()):
		.try_complete_challenge(chal_id, value, check_below)
		return
	var chal_data: = get_chal(chal_id)
	if chal_data == null:
		return
	if ( not check_below and value >= chal_data.value) or (check_below and value <= chal_data.value):
		complete_challenge(chal_id)


# Lifetime counters differ per machine: each one checks its own. Clients skip the wave's own
# check (their counters are a copy) and run it after LanNet applied the host's counts.
func check_counted_challenges() -> void :
	var lan_net = LanGame.get_lan_net()
	if _lan_in_team_wave(lan_net) and lan_net.is_client:
		return
	_lan_local_only = true
	.check_counted_challenges()
	_lan_local_only = false


# Client: the counted challenges once the host's counts for the wave are in.
func lan_check_counted_challenges() -> void :
	_lan_local_only = true
	.check_counted_challenges()
	_lan_local_only = false


# A challenge the host completed in a wave.
func lan_complete_forwarded(chal_id: int) -> void :
	if get_chal(chal_id) == null:
		return
	_lan_local_only = true
	complete_challenge(chal_id)
	_lan_local_only = false


func _lan_in_team_wave(lan_net) -> bool:
	return lan_net != null and lan_net.active and lan_net.wave_sync != null and not lan_net.solo_view.active
