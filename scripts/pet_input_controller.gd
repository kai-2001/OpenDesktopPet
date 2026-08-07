class_name PetInputController
extends RefCounted

const DRAG_DISTANCE_THRESHOLD_PX := 1.0

signal user_activity(timestamp: int)
signal single_click_requested
signal care_double_click_requested
signal context_menu_requested(position: Vector2i)
signal codex_focus_requested
signal interaction_region_refresh_requested

var _owner: Node
var _state: Node
var _pet: Node2D
var _window_service
var _speech_overlay_at: Callable
var _codex_active: Callable
var _interrupt_autonomous_action: Callable
var _dragging := false
var _left_press_pending := false
var _drag_offset := Vector2i.ZERO
var _drag_origin := Vector2i.ZERO
var _last_drag_mouse := Vector2i.ZERO
var _codex_bubble_press := false
var _last_mouse := Vector2i.ZERO
var _cursor_shape := Input.CURSOR_ARROW


func configure(
	owner: Node,
	state: Node,
	pet: Node2D,
	window_service,
	speech_overlay_at: Callable,
	codex_active: Callable,
	interrupt_autonomous_action: Callable
) -> void:
	_owner = owner
	_state = state
	_pet = pet
	_window_service = window_service
	_speech_overlay_at = speech_overlay_at
	_codex_active = codex_active
	_interrupt_autonomous_action = interrupt_autonomous_action
	_last_mouse = _window_service.mouse_position()


func process() -> void:
	var mouse: Vector2i = _window_service.mouse_position()
	if mouse.distance_to(_last_mouse) > 1.0:
		user_activity.emit(Time.get_ticks_msec())
	_last_mouse = mouse
	if (_dragging or _left_press_pending) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_left_press()
	if _dragging and mouse != _last_drag_mouse:
		_update_drag_position(mouse)
	_update_cursor(mouse)


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_drag_mouse_motion(_window_service.mouse_position())
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_button(event)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_press()
		context_menu_requested.emit(Vector2i(event.position))


func handle_secondary_window_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_drag_mouse_motion(_window_service.mouse_position())
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_finish_left_press()


func is_dragging() -> bool:
	return _dragging


func has_pending_press() -> bool:
	return _left_press_pending


func cancel() -> void:
	_left_press_pending = false
	_dragging = false
	_codex_bubble_press = false
	_pet.set_dragging(false)
	interaction_region_refresh_requested.emit()


func last_activity_msec() -> int:
	return Time.get_ticks_msec()


func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.double_click and event.pressed:
		var local_position := Vector2(
			_window_service.mouse_position() - _window_service.window_position()
		)
		if bool(_codex_active.call()) and bool(_speech_overlay_at.call(local_position)):
			codex_focus_requested.emit()
			_codex_bubble_press = false
			return
		_cancel_press()
		if _state.wake_sleep("double_click"):
			user_activity.emit(Time.get_ticks_msec())
			return
		care_double_click_requested.emit()
		return
	if event.pressed:
		_left_press_pending = true
		_drag_origin = _window_service.mouse_position()
		_last_drag_mouse = _drag_origin
		_drag_offset = _drag_origin - _window_service.window_position()
		_codex_bubble_press = bool(_codex_active.call()) and bool(
			_speech_overlay_at.call(
				Vector2(_drag_origin - _window_service.window_position())
			)
		)
	else:
		_finish_left_press()


func _handle_drag_mouse_motion(mouse: Vector2i) -> void:
	if _left_press_pending \
			and not _dragging \
			and mouse.distance_to(_drag_origin) >= DRAG_DISTANCE_THRESHOLD_PX:
		if _state.is_sleeping():
			_state.wake_sleep("drag")
		if _can_begin_drag():
			_begin_drag(mouse)
	if _dragging:
		_update_drag_position(mouse)


func _can_begin_drag() -> bool:
	return not _state.is_action_busy()


func _begin_drag(mouse: Vector2i) -> void:
	if not bool(_interrupt_autonomous_action.call()):
		return
	_left_press_pending = false
	_dragging = true
	_last_drag_mouse = mouse
	_pet.set_dragging(true)
	_pet.set_drag_motion(true)
	var configured_anchor: Variant = _pet.get_drag_anchor()
	if configured_anchor is Vector2:
		_drag_offset = Vector2i(roundi(configured_anchor.x), roundi(configured_anchor.y))
		_window_service.set_window_position(mouse - _drag_offset)
	_set_cursor_shape(Input.CURSOR_DRAG)
	interaction_region_refresh_requested.emit()


func _update_drag_position(mouse: Vector2i) -> void:
	if mouse.distance_to(_last_drag_mouse) > 1.0:
		_pet.set_facing_direction(1 if mouse.x > _last_drag_mouse.x else -1)
		_pet.set_drag_motion(true)
	else:
		_pet.set_drag_motion(false)
	_last_drag_mouse = mouse
	_window_service.set_window_position(mouse - _drag_offset)


func _finish_left_press() -> void:
	if not _left_press_pending and not _dragging:
		return
	var was_dragging := _dragging
	_left_press_pending = false
	_dragging = false
	if was_dragging:
		var window_position: Vector2i = _window_service.window_position()
		var window_size: Vector2i = _window_service.window_size()
		var screen: int = _window_service.screen_for_rect(window_position, window_size)
		var usable: Rect2i = _window_service.usable_rect(screen)
		var drag_bounds: Rect2 = _pet.get_visual_bounds_in_canvas()
		var was_at_bottom := absf(
			float(window_position.y) + drag_bounds.end.y - float(usable.end.y)
		) <= 2.0
		_pet.set_dragging(false)
		call_deferred("settle_drag_release", screen, was_at_bottom)
		_set_cursor_shape(Input.CURSOR_POINTING_HAND)
		_codex_bubble_press = false
	else:
		if _codex_bubble_press:
			_codex_bubble_press = false
			codex_focus_requested.emit()
		else:
			single_click_requested.emit()
	interaction_region_refresh_requested.emit()


func settle_drag_release(screen: int, preserve_bottom_contact: bool) -> void:
	await _owner.get_tree().process_frame
	if _dragging or _left_press_pending:
		return
	var requested: Vector2i = _window_service.window_position()
	if preserve_bottom_contact:
		var usable: Rect2i = _window_service.usable_rect(screen)
		var idle_bounds: Rect2 = _pet.get_visual_bounds_in_canvas()
		requested.y = usable.end.y - ceili(idle_bounds.end.y)
	_window_service.set_window_position(
		_window_service.clamp_window_position(
			requested,
			_window_service.window_size(),
			_pet.get_visual_bounds_in_canvas()
		)
	)


func _cancel_press() -> void:
	_left_press_pending = false
	_dragging = false
	_codex_bubble_press = false
	_pet.set_dragging(false)


func _update_cursor(global_mouse: Vector2i) -> void:
	if _dragging:
		_set_cursor_shape(Input.CURSOR_DRAG)
		return
	var local_mouse := Vector2(global_mouse - _window_service.window_position())
	var over_pet: bool = bool(_speech_overlay_at.call(local_mouse)) or _pet.contains_point(local_mouse)
	_set_cursor_shape(
		Input.CURSOR_POINTING_HAND if over_pet else Input.CURSOR_ARROW
	)


func _set_cursor_shape(shape: Input.CursorShape) -> void:
	if shape == _cursor_shape:
		return
	_cursor_shape = shape
	_window_service.set_cursor_shape(shape)
