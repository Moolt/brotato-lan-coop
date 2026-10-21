extends Node

# Between waves of a LAN session: counts down the choice time (LanNet.get_choice_time_left).
# changed(seconds) whenever the whole seconds left change (-1: no limit); overdue every frame
# once they reach 0. The owner shows the seconds and chooses for the player: the main.gd
# extension (random upgrade, crate item taken), the base_shop.gd extension (Go).

signal changed(seconds)
signal overdue()

const LanGame = preload("res://mods-unpacked/Moolt-Lan_Coop/game/lan_game.gd")

# The countdown is red from here on.
const WARNING_SECONDS: = 10
const BUTTON_FONT_COLORS: = ["font_color", "font_color_hover", "font_color_focus", "font_color_pressed"]

var _seconds: = - 2


func _init() -> void :
	name = "LanChoiceCountdown"
	pause_mode = PAUSE_MODE_PROCESS


func _process(_delta: float) -> void :
	var lan_net = LanGame.get_lan_net()
	var time_left: float = lan_net.get_choice_time_left() if lan_net != null else - 1.0
	var seconds: = int(ceil(time_left)) if time_left >= 0.0 else - 1
	if seconds != _seconds:
		_seconds = seconds
		emit_signal("changed", seconds)
	if seconds == 0:
		emit_signal("overdue")


static func get_color(seconds: int) -> Color:
	if seconds >= 0 and seconds <= WARNING_SECONDS:
		return Color(ProgressData.settings.color_negative)
	return Color.white


# Red text for the last seconds, the theme's colours otherwise.
static func color_button(button: Button, seconds: int) -> void :
	var warning: = seconds >= 0 and seconds <= WARNING_SECONDS
	for key in BUTTON_FONT_COLORS:
		button.set("custom_colors/" + key, get_color(seconds) if warning else null)
