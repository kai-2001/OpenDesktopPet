class_name DesktopWindowService
extends RefCounted

var _click_through: RefCounted
var _click_through_error_reported := false


## A window region larger than any pet window, so it never clips rendering.
static func unclipped_region() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0), Vector2(16384, 0), Vector2(16384, 16384), Vector2(0, 16384),
	])


func mouse_position() -> Vector2i:
	return DisplayServer.mouse_get_position()


func window_position() -> Vector2i:
	return DisplayServer.window_get_position()


func window_size() -> Vector2i:
	return DisplayServer.window_get_size()


func set_window_position(position: Vector2i) -> void:
	DisplayServer.window_set_position(position)


func set_always_on_top(enabled: bool) -> void:
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,
		enabled
	)


func has_status_indicator() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR)


func bring_to_front(window_id: int) -> void:
	DisplayServer.window_move_to_foreground(window_id)


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


func enable_native_click_through() -> bool:
	if _click_through != null:
		return true
	if not ClassDB.class_exists("WindowsClickThrough") \
			or DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) == 0:
		return false
	_click_through = ClassDB.instantiate("WindowsClickThrough")
	return _click_through != null


func uses_native_click_through() -> bool:
	return _click_through != null


func set_mouse_interactive(interactive: bool) -> void:
	if _click_through == null:
		return
	# Called every frame: Godot rebuilds the extended window style when some
	# window flags change, so the native call also restores dropped bits.
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if not bool(_click_through.set_click_through(handle, not interactive)) \
			and not _click_through_error_reported:
		_click_through_error_reported = true
		push_warning("Native click-through failed: %s" % _click_through.get_last_error())


func set_window_opacity(alpha: int) -> void:
	if _click_through == null:
		return
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if not bool(_click_through.set_opacity(handle, alpha)):
		push_warning("Native window opacity failed: %s" % _click_through.get_last_error())


func apply_interaction_polygon(
	window: Window,
	pet_polygon: PackedVector2Array,
	interactive_overlay_points: PackedVector2Array
) -> void:
	window.mouse_passthrough = false
	if _click_through != null:
		# On Windows the passthrough polygon becomes a window region, which also
		# clips rendering one frame ahead of the presented image. Native
		# click-through keeps the whole transparent window drawable instead.
		# Godot clears a region with SetWindowRgn(nullptr, TRUE); that forced
		# redraw shows a gray frame while the click-through style toggles, so
		# set an oversized region once (Godot applies polygons without redraw).
		var region := unclipped_region()
		if window.mouse_passthrough_polygon != region:
			window.mouse_passthrough_polygon = region
		return
	if interactive_overlay_points.is_empty():
		window.mouse_passthrough_polygon = pet_polygon
		return
	var combined_points := PackedVector2Array(pet_polygon)
	combined_points.append_array(interactive_overlay_points)
	window.mouse_passthrough_polygon = Geometry2D.convex_hull(combined_points)
