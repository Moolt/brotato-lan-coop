extends Reference

# Shared building blocks for the mod's title screen pages (built in code, styled like vanilla pages).

const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const TITLE_FONT = preload("res://resources/fonts/actual/base/font_60_outline.tres")
const BACK_ICON = preload("res://ui/menus/global/arrow_left_border.png")

const STATUS_COLOR_ERROR: = Color(1, 0.45, 0.45)
const STATUS_COLOR_INFO: = Color(1, 1, 1)
const STATUS_COLOR_OK: = Color(0.55, 1, 0.55)
const STATUS_COLOR_MUTED: = Color(1, 1, 1, 0.6)

# Vanilla's 4 coop colours (coop_service.tscn) plus 8 more for 12 players.
# Temporary: Step 4 moves the palette into CoopService.
const PLAYER_COLORS: = [
	Color(0.7227, 0.99, 0.92763), Color(0.95, 0.7277, 0.608), Color(0.87451, 0.988235, 0.721569), Color(0.99, 0.94842, 0.6336),
	Color(0.72, 0.84, 0.99), Color(0.99, 0.72, 0.88), Color(0.84, 0.75, 0.99), Color(0.99, 0.75, 0.75),
	Color(0.70, 0.96, 0.99), Color(0.86, 0.86, 0.86), Color(0.99, 0.86, 0.72), Color(0.78, 0.99, 0.80),
]


# Same saturation boost as CoopService.get_player_color.
static func get_player_color(player_index: int) -> Color:
	var color: Color = PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
	color.s = min(color.s + 0.5, 1.0)
	return color


# Dims the background like vanilla pages and returns a centred column to fill.
static func build_page(page: Control, width: float, title_key: String) -> VBoxContainer:
	page.theme = BASE_THEME
	page.set_anchors_and_margins_preset(Control.PRESET_WIDE)

	var background: = ColorRect.new()
	background.color = Color(0, 0, 0, 0.57)
	background.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(background)

	var center: = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	page.add_child(center)

	var column: = VBoxContainer.new()
	column.rect_min_size = Vector2(width, 0)
	column.add_constant_override("separation", 20)
	center.add_child(column)

	var title: = Label.new()
	title.text = title_key
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", TITLE_FONT)
	column.add_child(title)
	return column


static func new_button(text_key: String, min_size: Vector2 = Vector2(320, 64)) -> Button:
	var button: Button = MyMenuButton.new()
	button.text = text_key
	button.rect_min_size = min_size
	return button


static func new_back_button(text_key: String = "MENU_BACK") -> Button:
	var button: = new_button(text_key, Vector2(250, 64))
	button.icon = BACK_ICON
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


static func new_status_label(width: float) -> Label:
	var label: = Label.new()
	label.align = Label.ALIGN_CENTER
	label.autowrap = true
	label.rect_min_size = Vector2(width, 40)
	return label


# text is translated by the Label itself (keys) or shown as is (already built strings).
static func set_status(label: Label, text: String, is_error: bool = false) -> void :
	label.text = text
	label.add_color_override("font_color", STATUS_COLOR_ERROR if is_error else STATUS_COLOR_INFO)
