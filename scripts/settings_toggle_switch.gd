class_name SettingsToggleSwitch
extends Button

const TRACK_SIZE := Vector2(46.0, 24.0)
const TRACK_MARGIN_RIGHT := 2.0
const KNOB_RADIUS := 8.0

var _dark_theme := false
var _held := false


func _init() -> void:
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(96, 40)
	for state_name: String in [
		"normal", "hover", "pressed", "hover_pressed", "focus", "disabled"
	]:
		add_theme_stylebox_override(state_name, _transparent_style())
	mouse_exited.connect(func() -> void:
		_held = false
		queue_redraw()
	)
	button_down.connect(func() -> void:
		_held = true
		queue_redraw()
	)
	button_up.connect(func() -> void:
		_held = false
		queue_redraw()
	)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_enabled: bool) -> void: _sync_visuals())


func configure(theme_mode: String, enabled: bool) -> void:
	_dark_theme = theme_mode == "dark"
	set_pressed_no_signal(enabled)
	_sync_visuals()


func set_enabled_state(enabled: bool) -> void:
	set_pressed_no_signal(enabled)
	_sync_visuals()


func _sync_visuals() -> void:
	text = "開" if button_pressed else "關"
	var normal_color := Color("#d4d4d4") if _dark_theme else Color("#30383c")
	var muted_color := Color("#777777") if _dark_theme else Color("#8c979b")
	var state_color := muted_color if disabled else normal_color
	add_theme_color_override("font_color", state_color)
	add_theme_color_override("font_hover_color", state_color)
	add_theme_color_override("font_pressed_color", state_color)
	add_theme_color_override("font_hover_pressed_color", state_color)
	add_theme_color_override("font_focus_color", state_color)
	add_theme_color_override("font_disabled_color", muted_color)
	add_theme_font_size_override("font_size", 16)
	queue_redraw()


func _draw() -> void:
	var track_position := Vector2(
		size.x - TRACK_SIZE.x - TRACK_MARGIN_RIGHT,
		(size.y - TRACK_SIZE.y) * 0.5
	)
	var track_rect := Rect2(track_position, TRACK_SIZE)
	var track_style := StyleBoxFlat.new()
	track_style.set_corner_radius_all(roundi(TRACK_SIZE.y * 0.5))
	track_style.set_border_width_all(2 if has_focus() else 1)

	var track_color: Color
	var border_color: Color
	var knob_color: Color
	if disabled:
		track_color = Color("#e8ecee")
		border_color = Color("#c4cdd1")
		knob_color = Color("#9aa5aa")
	elif button_pressed:
		track_color = Color("#087f8b") if _held else Color("#08a6b5")
		border_color = Color("#087f8b")
		knob_color = Color.WHITE
	else:
		track_color = Color.WHITE
		border_color = Color("#08a6b5") if has_focus() else Color("#8f9da2")
		knob_color = Color("#30383c")

	track_style.bg_color = track_color
	track_style.border_color = border_color
	draw_style_box(track_style, track_rect)
	var knob_x := (
		track_rect.end.x - TRACK_SIZE.y * 0.5
		if button_pressed
		else track_rect.position.x + TRACK_SIZE.y * 0.5
	)
	draw_circle(
		Vector2(knob_x, track_rect.get_center().y),
		KNOB_RADIUS,
		knob_color
	)


func _transparent_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 2
	style.content_margin_right = TRACK_SIZE.x + 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
