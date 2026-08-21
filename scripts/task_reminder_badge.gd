class_name TaskReminderBadge
extends Button

const PULSE_STEP_SECONDS := 0.18

var _state: TaskReminderBadgeState
var _attention_tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(28, 28)
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color.WHITE)
	visible = false
	_state = TaskReminderBadgeState.new()


func present(state: TaskReminderBadgeState, pulse_attention := false) -> void:
	_state = state if state != null else TaskReminderBadgeState.new()
	if is_instance_valid(_attention_tween):
		_attention_tween.kill()
		_attention_tween = null
	if not _state.visible:
		visible = false
	else:
		visible = true
		_render_steady()
	if pulse_attention and _state.has_attention():
		_show_attention()


func _show_attention() -> void:
	if not _state.has_attention():
		return
	visible = true
	text = _state.attention_label
	tooltip_text = _state.attention_tooltip
	_apply_style(Color("#b56a25"), Color("#c67b32"), Color("#95521b"))
	modulate = Color(1, 1, 1, 0.48)
	_attention_tween = create_tween()
	_attention_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for _pulse: int in 2:
		_attention_tween.tween_property(self, "modulate", Color.WHITE, PULSE_STEP_SECONDS)
		_attention_tween.tween_property(
			self, "modulate", Color(1, 1, 1, 0.48), PULSE_STEP_SECONDS
		)
	_attention_tween.tween_callback(Callable(self, "_finish_attention"))


func _finish_attention() -> void:
	_attention_tween = null
	if not _state.visible:
		visible = false
		return
	_render_steady()


func _render_steady() -> void:
	text = _state.label
	tooltip_text = _state.tooltip
	custom_minimum_size = Vector2(32 if text.length() > 1 else 28, 28)
	_apply_style(Color("#267487"), Color("#31879a"), Color("#1b5c6d"))
	modulate = Color.WHITE


func clear() -> void:
	_state = TaskReminderBadgeState.new()
	if is_instance_valid(_attention_tween):
		_attention_tween.kill()
		_attention_tween = null
	visible = false


func _apply_style(normal_color: Color, hover_color: Color, pressed_color: Color) -> void:
	add_theme_stylebox_override("normal", _stylebox(normal_color))
	add_theme_stylebox_override("hover", _stylebox(hover_color))
	add_theme_stylebox_override("pressed", _stylebox(pressed_color))
	add_theme_stylebox_override("focus", _stylebox(normal_color))


func _stylebox(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.shadow_color = Color(0, 0, 0, 0.26)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style
