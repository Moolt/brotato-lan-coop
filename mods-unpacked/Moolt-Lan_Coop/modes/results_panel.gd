extends PanelContainer

# The end screen's results of a mode with scores (LanMode.on_end_screen), under the title: the
# winner line, then every player in the mode's ranking with the mode's columns, on one wrapping
# line ("1. Anna  Kills 120 · 2. Bob ...").

const FONT = preload("res://resources/fonts/actual/base/font_smallest_text.tres")
const FONT_SIZE: = 24

var _mode: Reference = null


func init(mode: Reference) -> void :
	_mode = mode


func _ready() -> void :
	var font: DynamicFont = FONT.duplicate()
	font.size = FONT_SIZE
	var column: = VBoxContainer.new()
	add_child(column)

	var result: String = _mode.get_result_text()
	if not result.empty():
		var winner: = Label.new()
		winner.set_message_translation(false)
		winner.text = result
		winner.add_font_override("font", font)
		winner.add_color_override("font_color", Color(1.0, 0.85, 0.3))
		column.add_child(winner)

	var parts: = []
	var rank: = 1
	for player_index in _mode.get_ranking():
		var values: = []
		for score_column in _mode.get_score_columns():
			values.append("%s %d" % [tr(score_column[1]), _mode.get_score(score_column[0], player_index)])
		var text: = "%d. %s" % [rank, _mode.get_player_name(player_index)]
		var note: String = _mode.get_player_note(player_index)
		if not note.empty():
			text += " (" + note + ")"
		parts.append(text + "  " + PoolStringArray(values).join(", "))
		rank += 1
	var ranking: = Label.new()
	ranking.set_message_translation(false)
	ranking.autowrap = true
	ranking.text = PoolStringArray(parts).join("   ·   ")
	ranking.add_font_override("font", font)
	column.add_child(ranking)
