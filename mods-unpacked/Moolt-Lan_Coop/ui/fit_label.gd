extends Label

# A label that shortens its text with "..." to the width it gets, like vanilla's TrimmedButton,
# instead of cutting it off mid-letter (Godot 3 labels can only clip). Set full_text, not text;
# it is shown as is (player names aren't translation keys). Its minimum width is 0, so a container
# decides the width (SIZE_EXPAND_FILL).

var full_text: = "" setget set_full_text


func _init() -> void :
	clip_text = true
	set_message_translation(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void :
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_fit()


func set_full_text(value: String) -> void :
	full_text = value
	_fit()


func _fit() -> void :
	var font: Font = get_font("font")
	var width: = rect_size.x
	if font == null or width <= 0.0 or font.get_string_size(full_text).x <= width:
		text = full_text
		return
	var shown: = full_text
	var ellipsis_width: = font.get_string_size("...").x
	while not shown.empty() and font.get_string_size(shown).x + ellipsis_width > width:
		shown = shown.left(shown.length() - 1)
	text = shown.strip_edges() + "..."
