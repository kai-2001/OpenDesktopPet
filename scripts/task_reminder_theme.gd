class_name TaskReminderTheme
extends RefCounted

var _dark := false


func _init(theme_mode := "light") -> void:
	_dark = theme_mode == "dark"


func color(role: String) -> Color:
	var light := {
		"canvas": "#f7f8f9",
		"surface": "#ffffff",
		"surface_subtle": "#f1f4f5",
		"surface_selected": "#e8f5f6",
		"text": "#20282c",
		"text_muted": "#5f6d73",
		"text_faint": "#65747a",
		"border": "#d7e0e3",
		"border_strong": "#aab8bd",
		"accent": "#087f8b",
		"accent_hover": "#066a74",
		"accent_soft": "#d9f0f2",
		"danger": "#b23a48",
		"danger_soft": "#fbeaec",
		"success": "#24744c",
		"success_soft": "#e3f3e9",
	}
	var dark := {
		"canvas": "#181a1b",
		"surface": "#222526",
		"surface_subtle": "#2a2e30",
		"surface_selected": "#17383b",
		"text": "#f1f4f5",
		"text_muted": "#b6c0c4",
		"text_faint": "#909ca1",
		"border": "#3a4144",
		"border_strong": "#5b686d",
		"accent": "#57c7d1",
		"accent_hover": "#7ad9e1",
		"accent_soft": "#17383b",
		"danger": "#ff8f9c",
		"danger_soft": "#40272b",
		"success": "#79d6a1",
		"success_soft": "#20372a",
	}
	return Color(String((dark if _dark else light).get(role, "#ff00ff")))


func panel(background_role := "surface", border_role := "border", radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color(background_role)
	style.border_color = color(border_role)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func chip(background_role: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color(background_role)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func style_button(button: Button, kind := "secondary") -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	var normal_background := "surface"
	var normal_border := "border"
	var hover_background := "surface_selected"
	var hover_border := "accent"
	var pressed_background := "accent_soft"
	var foreground := "text"
	if kind == "primary":
		normal_background = "accent"
		normal_border = "accent"
		hover_background = "accent_hover"
		hover_border = "accent_hover"
		pressed_background = "accent_hover"
		foreground = "surface"
	elif kind == "danger":
		normal_background = "danger_soft"
		normal_border = "danger"
		hover_background = "danger"
		hover_border = "danger"
		pressed_background = "danger"
		foreground = "danger"
	elif kind == "quiet":
		normal_background = "surface"
		normal_border = "surface"
		hover_background = "surface_subtle"
		hover_border = "surface_subtle"
		pressed_background = "accent_soft"
	button.add_theme_stylebox_override("normal", panel(normal_background, normal_border, 8))
	button.add_theme_stylebox_override("hover", panel(hover_background, hover_border, 8))
	button.add_theme_stylebox_override("pressed", panel(pressed_background, hover_border, 8))
	button.add_theme_stylebox_override("focus", panel(hover_background, "accent", 8))
	button.add_theme_color_override("font_color", color(foreground))
	button.add_theme_color_override(
		"font_hover_color", color("surface") if kind in ["primary", "danger"] else color("accent_hover")
	)
	button.add_theme_color_override(
		"font_pressed_color", color("surface") if kind in ["primary", "danger"] else color("accent")
	)
	button.add_theme_color_override("font_focus_color", color(foreground))


func style_input(control: Control) -> void:
	for state: String in ["normal", "read_only"]:
		control.add_theme_stylebox_override(state, panel("surface", "border", 8))
	control.add_theme_stylebox_override("focus", panel("surface", "accent", 8))
	control.add_theme_color_override("font_color", color("text"))
	control.add_theme_color_override("font_uneditable_color", color("text_faint"))
	control.add_theme_color_override("font_placeholder_color", color("text_faint"))
	control.add_theme_color_override("caret_color", color("accent"))


func style_disclosure_header(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	var transparent := panel("canvas", "canvas", 8)
	transparent.bg_color = Color(0, 0, 0, 0)
	transparent.border_color = Color(0, 0, 0, 0)
	var hover := panel("surface_subtle", "surface_subtle", 8)
	var pressed := panel("surface_selected", "surface_selected", 8)
	var focus := panel("surface_subtle", "accent", 8)
	for style: StyleBoxFlat in [transparent, hover, pressed, focus]:
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
	button.add_theme_stylebox_override("normal", transparent)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
