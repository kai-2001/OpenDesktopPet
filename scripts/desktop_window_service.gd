class_name DesktopWindowService
extends RefCounted


func mouse_position() -> Vector2i:
	return DisplayServer.mouse_get_position()


func window_position() -> Vector2i:
	return DisplayServer.window_get_position()


func window_size() -> Vector2i:
	return DisplayServer.window_get_size()


func set_window_position(position: Vector2i) -> void:
	DisplayServer.window_set_position(position)


func restore_if_minimized() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func current_screen() -> int:
	var screen := DisplayServer.window_get_current_screen()
	return DisplayServer.get_primary_screen() if screen < 0 else screen


func usable_rect(screen := -1) -> Rect2i:
	var target_screen := current_screen() if screen < 0 else screen
	return DisplayServer.screen_get_usable_rect(target_screen)


func screen_for_rect(position: Vector2i, size: Vector2i) -> int:
	var screen := DisplayServer.get_screen_from_rect(Rect2i(position, size))
	return DisplayServer.get_primary_screen() if screen < 0 else screen


func clamp_window_position(
	requested: Vector2i,
	window_size: Vector2i,
	visible_bounds: Rect2
) -> Vector2i:
	var screen := screen_for_rect(requested, window_size)
	var usable := usable_rect(screen)
	var min_position := Vector2(
		usable.position.x - floor(visible_bounds.position.x),
		usable.position.y - floor(visible_bounds.position.y)
	)
	var max_position := Vector2(
		usable.end.x - ceil(visible_bounds.end.x),
		usable.end.y - ceil(visible_bounds.end.y)
	)
	return Vector2i(Vector2(requested).clamp(min_position, max_position))


func set_cursor_shape(shape: Input.CursorShape) -> void:
	Input.set_default_cursor_shape(shape)


func apply_interaction_polygon(
	window: Window,
	pet_polygon: PackedVector2Array,
	bubble_visible: bool,
	bubble_rect: Rect2,
	tail_points: PackedVector2Array
) -> void:
	window.mouse_passthrough = false
	if not bubble_visible:
		window.mouse_passthrough_polygon = pet_polygon
		return
	var combined_points := PackedVector2Array(pet_polygon)
	combined_points.append_array(PackedVector2Array([
		bubble_rect.position,
		Vector2(bubble_rect.end.x, bubble_rect.position.y),
		bubble_rect.end,
		Vector2(bubble_rect.position.x, bubble_rect.end.y),
	]))
	combined_points.append_array(tail_points)
	window.mouse_passthrough_polygon = Geometry2D.convex_hull(combined_points)
