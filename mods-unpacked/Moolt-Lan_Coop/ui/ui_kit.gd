extends Reference

# Shared building blocks for the mod's pages (built in code, styled like vanilla pages) and its
# player rows.

const BASE_THEME = preload("res://resources/themes/base_theme.tres")
const TITLE_FONT = preload("res://resources/fonts/actual/base/font_60_outline.tres")
const BACK_ICON = preload("res://ui/menus/global/arrow_left_border.png")
const TEAM_ICON = preload("res://items/all/00_base_game/white_flag/white_flag_icon.png")
const FitLabel = preload("res://mods-unpacked/Moolt-Lan_Coop/ui/fit_label.gd")

const PLAYER_BAR_WIDTH: = 5.0
const PLAYER_BAR_RADIUS: = 3
# Player rows' backgrounds: the shown / own row, and a row with the focus or the mouse.
const ROW_SELECTED_COLOR: = Color(1, 1, 1, 0.16)
const ROW_FOCUS_COLOR: = Color(1, 1, 1, 0.09)
const ROW_RADIUS: = 8

const STATUS_COLOR_ERROR: = Color(1, 0.45, 0.45)
const STATUS_COLOR_INFO: = Color(1, 1, 1)
const STATUS_COLOR_OK: = Color(0.55, 1, 0.55)
const STATUS_COLOR_MUTED: = Color(1, 1, 1, 0.6)

# The in-wave colour of a player (12 colours, see the CoopService extension).
static func get_player_color(player_index: int) -> Color:
	return CoopService.get_player_color(player_index % CoopService.player_colors.size())


# Player rows (lobby, scoreboard, the end screen's list) share these parts: a bar in the player's
# colour at the left, the character icon, the name in the player's colour shortened with "...",
# and icons instead of words for scores and status. Teams sit in a frame in the team's colour.

static func new_rounded_style(color: Color, radius: int, margin_x: float = 0.0, margin_y: float = 0.0) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_default_margin(MARGIN_LEFT, margin_x)
	style.set_default_margin(MARGIN_RIGHT, margin_x)
	style.set_default_margin(MARGIN_TOP, margin_y)
	style.set_default_margin(MARGIN_BOTTOM, margin_y)
	return style


# The bar fills the row's height unless height is given.
static func new_player_bar(player_index: int, height: float = 0.0, width: float = PLAYER_BAR_WIDTH) -> Panel:
	var bar: = Panel.new()
	bar.add_stylebox_override("panel", new_rounded_style(get_player_color(player_index), PLAYER_BAR_RADIUS))
	bar.rect_min_size = Vector2(width, height)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER if height > 0.0 else Control.SIZE_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


static func new_icon(texture: Texture, size: Vector2, color: Color = Color.white) -> TextureRect:
	var icon: = TextureRect.new()
	icon.texture = texture
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = size
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


# Takes the width its container leaves (SIZE_EXPAND_FILL).
static func new_name_label(text: String, color: Color, font: Font) -> Label:
	var label: Label = FitLabel.new()
	label.add_font_override("font", font)
	label.add_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.valign = Label.VALIGN_CENTER
	label.full_text = text
	return label


# A frame around a team's rows, in the team's colour (border and a light tint, like vanilla
# coop's player panels). Add the rows to its VBoxContainer child.
static func new_team_frame(color: Color, faded: bool = false) -> PanelContainer:
	var style: = new_rounded_style(Color(color.r, color.g, color.b, 0.09), 10, 4, 4)
	style.border_color = Color(color.r, color.g, color.b, 0.45 if faded else 1.0)
	style.set_border_width_all(2)
	var frame: = PanelContainer.new()
	frame.add_stylebox_override("panel", style)
	var rows: = VBoxContainer.new()
	rows.add_constant_override("separation", 4)
	frame.add_child(rows)
	return frame


# A player row's button (end screen's list): the shown row (not flat) has a light rounded
# background, a row with the focus or the mouse a fainter one.
static func style_row_button(button: Button) -> void :
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_stylebox_override(state, new_rounded_style(ROW_SELECTED_COLOR, ROW_RADIUS))
	button.add_stylebox_override("focus", new_rounded_style(ROW_FOCUS_COLOR, ROW_RADIUS))


# The flag that stands for a team, tinted in its colour.
static func new_team_icon(color: Color, size: float) -> TextureRect:
	return new_icon(TEAM_ICON, Vector2(size, size), color)


# An icon and a short text (a status such as the skull and "W7", or a score's icon and value).
static func new_icon_value(texture: Texture, text: String, font: Font, color: Color = Color.white, icon_size: float = 22.0) -> HBoxContainer:
	var box: = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_constant_override("separation", 3)
	if texture != null:
		box.add_child(new_icon(texture, Vector2(icon_size, icon_size)))
	if not text.empty():
		var label: = Label.new()
		label.set_message_translation(false)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.valign = Label.VALIGN_CENTER
		label.size_flags_vertical = Control.SIZE_FILL
		label.text = text
		label.add_font_override("font", font)
		label.add_color_override("font_color", color)
		box.add_child(label)
	return box


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
