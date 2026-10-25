extends SceneTree

# Driven by tests/run_native_click_through_test.ps1. The PowerShell side owns
# the real cursor and reads WindowFromPoint; this side reports where the pet,
# its speech bubble and empty transparent pixels are on screen.

var _signal_dir := ""
var _bubble_point := Vector2(-1, -1)


func _init() -> void:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	_signal_dir = String(options.get("signal-dir", ""))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	main._idle_behavior_timer.stop()
	main._set_target_fps(int(options.get("fps", "30")))
	main.state.set_visual_scale(float(options.get("scale", "1.0")))
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	DisplayServer.window_set_position(usable.get_center() - DisplayServer.window_get_size() / 2)
	main.say("點擊穿透測試", 120.0)
	await create_timer(0.8).timeout
	_write_report(main, "bubble")
	if not await _wait_for_signal("hide-bubble"):
		quit(1)
		return
	main.bubble.visible = false
	main.bubble_tail.visible = false
	main._refresh_interaction_polygon()
	await create_timer(0.5).timeout
	_write_report(main, "pet")
	if not await _wait_for_signal("after-drag"):
		quit(1)
		return
	_write_report(main, "after")
	await _wait_for_signal("done")
	quit(0)


func _write_report(main: Node, phase: String) -> void:
	var window_position := DisplayServer.window_get_position()
	var window_size := DisplayServer.window_get_size()
	var pet_points: Array[Vector2] = []
	var gap_points: Array[Vector2] = []
	var empty_point := Vector2(-1, -1)
	var outline: PackedVector2Array = main.pet.get_interaction_polygon()
	for y in range(2, window_size.y - 2, 3):
		for x in range(2, window_size.x - 2, 3):
			var point := Vector2(x, y)
			if main._is_interactive_overlay_at(point):
				continue
			if main.pet.contains_point(point):
				pet_points.append(point)
			elif Geometry2D.is_point_in_polygon(point, outline):
				# Transparent pixel inside the sprite outline: a soft edge or gap.
				gap_points.append(point)
			elif empty_point.x < 0 and not _over_pet(main, point):
				empty_point = point
	var gap_point := gap_points[gap_points.size() / 2] if not gap_points.is_empty() \
		else Vector2(-1, -1)
	var pet_point := _most_enclosed(main, pet_points)
	var bubble_point := Vector2(-1, -1)
	if main.bubble.visible:
		var bubble_rect: Rect2 = main.bubble.get_global_rect()
		for y in range(int(bubble_rect.position.y) + 8, int(bubble_rect.end.y) - 8, 6):
			for x in range(int(bubble_rect.position.x) + 8, int(bubble_rect.end.x) - 8, 6):
				if bubble_point.x < 0 and _clear_of_pet(main, Vector2(x, y)):
					bubble_point = Vector2(x, y)
		_bubble_point = bubble_point
		if bubble_point.x < 0:
			# Large pets cover the whole bubble with their outline; the centre
			# still proves the bubble receives input.
			bubble_point = bubble_rect.get_center()
	var former_bubble := []
	if not main.bubble.visible and _bubble_point.x >= 0 \
			and not _over_pet(main, _bubble_point):
		former_bubble = _screen(window_position, _bubble_point)
	var report := {
		"phase": phase,
		"native": main._window_service.uses_native_click_through(),
		"unclipped_region": main.get_window().mouse_passthrough_polygon == DesktopWindowService.unclipped_region(),
		"fps": Engine.max_fps,
		"scale": main.pet.scale.x,
		"window": [window_position.x, window_position.y, window_size.x, window_size.y],
		"pet": _screen(window_position, pet_point),
		"empty": _screen(window_position, empty_point),
		"bubble": _screen(window_position, bubble_point) if bubble_point.x >= 0 else [],
		"former_bubble": former_bubble,
		"outline_gap": _screen(window_position, gap_point) if gap_point.x >= 0 else [],
	}
	var file := FileAccess.open(_signal_dir.path_join("%s.json" % phase), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()


func _most_enclosed(main: Node, points: Array[Vector2]) -> Vector2:
	# Pick an opaque pixel whose neighbours are opaque too, so a one-frame
	# animation change cannot move the cursor onto a transparent edge.
	var best := points[points.size() / 2] if not points.is_empty() else Vector2(-1, -1)
	var best_score := -1
	for index in range(0, points.size(), 7):
		var point := points[index]
		var score := 0
		for offset in [Vector2(-12, 0), Vector2(12, 0), Vector2(0, -12), Vector2(0, 12),
				Vector2(-8, -8), Vector2(8, 8), Vector2(-8, 8), Vector2(8, -8)]:
			if main.pet.contains_point(point + offset):
				score += 1
		if score > best_score:
			best_score = score
			best = point
	return best


func _clear_of_pet(main: Node, point: Vector2) -> bool:
	# Idle animations move ears and tails a few pixels between frames.
	for y in range(-10, 11, 2):
		for x in range(-10, 11, 2):
			var probe: Vector2 = point + Vector2(x, y)
			if main.pet.contains_point(probe) \
					or Geometry2D.is_point_in_polygon(probe, main.pet.get_interaction_polygon()):
				return false
	return true


func _screen(window_position: Vector2i, point: Vector2) -> Array:
	return [window_position.x + roundi(point.x), window_position.y + roundi(point.y)]


func _wait_for_signal(name: String) -> bool:
	var deadline := Time.get_ticks_msec() + 60000
	var path := _signal_dir.path_join(name)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return true
		await create_timer(0.05).timeout
	return false


func _over_pet(main: Node, point: Vector2) -> bool:
	# The same decision the input controller makes each frame, outline included.
	return main._input_controller._is_over_pet(DisplayServer.window_get_position() + Vector2i(point))
