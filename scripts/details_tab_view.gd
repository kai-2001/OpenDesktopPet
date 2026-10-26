class_name DetailsTabView
extends RefCounted

# Shared look of the details window tabs. Each tab view builds its controls
# with these helpers and reports user actions through its own signals.

var theme_mode := "light"


func _new_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _details_color(light: String, dark: String) -> Color:
	return Color(dark if theme_mode == "dark" else light)


func _details_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _style_spin_box(spin_box: SpinBox) -> void:
	var line_edit := spin_box.get_line_edit()
	var normal := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#d6dee2", "#3c3c3c"), 6
	)
	var hover := _details_style(
		_details_color("#f7fcfd", "#2a2d2e"),
		_details_color("#78c8d5", "#4e94ce"), 6
	)
	var focus := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#35a9bd", "#3794ff"), 6
	)
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("hover", hover)
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_color_override("font_color", _details_color("#30383c", "#d4d4d4"))
	line_edit.add_theme_color_override("font_uneditable_color", _details_color("#68747a", "#9da1a6"))
	line_edit.add_theme_color_override("caret_color", _details_color("#176f7e", "#4fc1ff"))
	spin_box.add_theme_color_override("font_color", _details_color("#30383c", "#d4d4d4"))


func _style_checkbox(check_box: CheckBox) -> void:
	check_box.add_theme_constant_override("h_separation", 10)
	check_box.add_theme_color_override("font_color", _details_color("#30383c", "#cccccc"))
	check_box.add_theme_color_override("font_hover_color", _details_color("#176f7e", "#ffffff"))
	check_box.add_theme_color_override("font_pressed_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_hover_pressed_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_focus_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_disabled_color", _details_color("#99a3a8", "#6d6d6d"))


func _apply_primary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#35a9bd", "#0e639c"), _details_color("#35a9bd", "#1177bb"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#278fa1", "#1177bb"), _details_color("#278fa1", "#3794ff"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#1d7888", "#094771"), _details_color("#1d7888", "#3794ff"), 8
	))
	button.add_theme_color_override("font_color", Color("#ffffff"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("#ffffff"))


func _apply_secondary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#ffffff", "#252526"), _details_color("#c7d0d5", "#45484c"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#f1f4f5", "#303236"), _details_color("#8fa5ae", "#60666b"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#e4eaed", "#3a3d41"), _details_color("#7b919b", "#747a80"), 8
	))
	button.add_theme_color_override("font_color", _details_color("#445057", "#d4d4d4"))
	button.add_theme_color_override("font_hover_color", _details_color("#30383c", "#f0f0f0"))
	button.add_theme_color_override("font_pressed_color", _details_color("#30383c", "#f0f0f0"))


func _apply_danger_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#fffafa", "#2b2020"), _details_color("#e7b4b4", "#8b4545"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#fff0f0", "#3b2424"), _details_color("#d97b7b", "#d16969"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#f8dddd", "#512b2b"), _details_color("#c85f5f", "#f48771"), 8
	))
	button.add_theme_color_override("font_color", _details_color("#b34747", "#f48771"))
	button.add_theme_color_override("font_hover_color", _details_color("#a53636", "#ff9b8a"))
	button.add_theme_color_override("font_pressed_color", _details_color("#8f2d2d", "#ffffff"))
