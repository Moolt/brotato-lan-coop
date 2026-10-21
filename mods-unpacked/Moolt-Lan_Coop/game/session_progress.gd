extends Reference

# What a LAN session counts for on this machine's save (decided 2026-10-21):
# - A won run credits only the own character (run_data.gd extension: apply_run_won in the solo
#   view): its challenge, difficulty record and the next danger.
# - Between waves (solo view) everything is the own player's, as in solo play.
# - During a wave challenges and lifetime counters count for the team: the host forwards its
#   challenges (challenge_service.gd extension) and sends the wave's counter changes with the
#   wave-end state (get_wave_delta); clients replace their own counts with them.
# - Rewards (unlocked characters, items, ...) of challenges completed during the session are
#   added to the own unlock lists (apply_rewards), which the session swaps for "everything".
# LanNet saves the own progress when a run ends and when the session ends.

# The challenges completed when the session started.
var _start_challenges: = {}
# Counters at the start of the current wave (counters()).
var _wave_start: = {}


func start() -> void :
	_start_challenges = {}
	for chal_id in ProgressData.challenges_completed:
		_start_challenges[chal_id] = true
	_wave_start = {}


# Adds the rewards of the challenges completed during the session to the current unlock lists
# (the own ones; during a session the lists hold everything and the rewards would be lost).
func apply_rewards() -> void :
	for chal_id in ProgressData.challenges_completed:
		if _start_challenges.has(chal_id):
			continue
		var chal_data = ChallengeService.get_chal(chal_id)
		if chal_data != null:
			var _unlocked = ChallengeService.unlock_reward(chal_data)


func wave_started() -> void :
	_wave_start = counters()


# Host: what the wave added to each counter (only changed ones).
func get_wave_delta() -> Dictionary:
	var delta: = {}
	if _wave_start.empty():
		return delta
	var now: = counters()
	for group in now:
		var changes: = {}
		for key in now[group]:
			var change = now[group][key] - _wave_start[group].get(key, 0)
			if change != 0:
				changes[key] = change
		delta[group] = changes
	return delta


# Client: the counters become the ones from the wave's start plus the host's changes, which
# drops the counts of the client's own copy of the wave.
func apply_wave_delta(delta: Dictionary) -> void :
	if _wave_start.empty():
		return
	var targets: = _get_targets()
	for group in targets:
		var target: Dictionary = targets[group]
		var start: Dictionary = _wave_start.get(group, {})
		var changes = delta.get(group, {})
		if typeof(changes) != TYPE_DICTIONARY:
			changes = {}
		for key in _numeric_keys(target):
			if start.has(key):
				target[key] = start[key]
			else:
				var _erased = target.erase(key)
		for key in start:
			if not target.has(key):
				target[key] = start[key]
		for key in changes:
			if typeof(changes[key]) == TYPE_INT or typeof(changes[key]) == TYPE_REAL:
				target[key] = start.get(key, target.get(key, 0)) + changes[key]
	_wave_start = {}


# The lifetime counters (ProgressData.data's numbers, the encyclopedia's kill counts).
static func counters() -> Dictionary:
	var result: = {}
	var targets: = _get_targets()
	for group in targets:
		var values: = {}
		for key in _numeric_keys(targets[group]):
			values[key] = targets[group][key]
		result[group] = values
	return result


static func _get_targets() -> Dictionary:
	return {"data": ProgressData.data, "killed_enemies": ProgressData.killed_enemies, "killed_by_enemies": ProgressData.killed_by_enemies}


static func _numeric_keys(values: Dictionary) -> Array:
	var keys: = []
	for key in values:
		if typeof(values[key]) == TYPE_INT or typeof(values[key]) == TYPE_REAL:
			keys.append(key)
	return keys
