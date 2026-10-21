extends Control

# Shown over the shop after Go in a LAN session, until everyone is done: who is still shopping,
# and a button back to the shop (takes the Go back) with the choice time left. Blocks the shop
# underneath.

signal back_pressed()

const UiKit = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/ui_kit.gd")
const ChoiceCountdown = preload("res://mods-unpacked/Moolt-Lan_Coop/game/choice_countdown.gd")

const WIDTH: = 900.0

var _names_label: Label = null
var _back_button: Button = null


func _init() -> void :
	name = "LanShopWaitingOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: = UiKit.build_page(self, WIDTH, "LAN_SHOP_WAITING")
	# build_page's dim background lets clicks through; this overlay must not. Darker than a
	# page, so the text reads over the busy shop.
	var background: ColorRect = get_child(0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.color = Color(0, 0, 0, 0.8)

	_names_label = UiKit.new_status_label(WIDTH)
	column.add_child(_names_label)

	_back_button = UiKit.new_button("LAN_SHOP_BACK")
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Keyboard and gamepad focus stays on the button while the shop is blocked.
	for side in ["focus_neighbour_left", "focus_neighbour_top", "focus_neighbour_right", "focus_neighbour_bottom", "focus_next", "focus_previous"]:
		_back_button.set(side, NodePath("."))
	var _e = _back_button.connect("pressed", self, "emit_signal", ["back_pressed"])
	column.add_child(_back_button)
	visible = false


func open(names: Array) -> void :
	set_names(names)
	show()
	_back_button.grab_focus()


func set_names(names: Array) -> void :
	var joined: = PoolStringArray(names).join(", ")
	_names_label.text = tr("LAN_SHOP_STILL_SHOPPING").replace("{0}", joined) if not names.empty() else ""


# The choice time left on the back button (-1: no limit); at 0 Go can't be taken back.
func set_seconds_left(seconds: int) -> void :
	_back_button.text = tr("LAN_SHOP_BACK") if seconds < 0 else "%s (%d)" % [tr("LAN_SHOP_BACK"), seconds]
	_back_button.disabled = seconds == 0
	ChoiceCountdown.color_button(_back_button, seconds)


func focus() -> void :
	_back_button.grab_focus()
