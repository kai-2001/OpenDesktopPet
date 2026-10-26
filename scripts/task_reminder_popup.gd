class_name TaskReminderPopup
extends PopupPanel

var _theme: TaskReminderTheme
var _drag_handle: Control
var _dragging := false
var _drag_offset := Vector2i.ZERO


func _init() -> void:
	unresizable = true
	borderless = true
	transient = true
	exclusive = false
	popup_hide.connect(func() -> void: _dragging = false)


func configure(theme: TaskReminderTheme) -> void:
	_theme = theme
	add_theme_stylebox_override("panel", _theme.panel("surface", "border_strong", 12))
	_build()


func _build() -> void:
	pass


func _popup_below(anchor: Control) -> void:
	var anchor_position := anchor.get_screen_position()
	position = Vector2i(anchor_position + Vector2(0, anchor.size.y + 4))
	_clamp_to_usable_screen()
	popup()


func _content_container() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return content


func _make_drag_handle(label: Label, tooltip: String) -> void:
	_drag_handle = label
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_MOVE
	label.tooltip_text = tooltip
	label.gui_input.connect(_on_drag_handle_input)


func _on_drag_handle_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = DisplayServer.mouse_get_position() - position
		_drag_handle.accept_event()
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion == null or not _dragging:
		return
	position = DisplayServer.mouse_get_position() - _drag_offset
	_clamp_to_usable_screen()
	_drag_handle.accept_event()


func _clamp_to_usable_screen() -> void:
	var screen := DisplayServer.window_get_current_screen(get_window_id())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var maximum := usable.end - size
	position = Vector2i(
		clampi(position.x, usable.position.x, maxi(usable.position.x, maximum.x)),
		clampi(position.y, usable.position.y, maxi(usable.position.y, maximum.y))
	)
