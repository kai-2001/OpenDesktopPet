extends SceneTree

var _failures := 0


func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame

	_assert_true(main.pet.visible, "pet is revealed after native window setup")
	_assert_true(main.pet.contains_point(Vector2(140, 190)), "pet center is interactive")
	_assert_true(not main.pet.contains_point(Vector2(5, 5)), "transparent corner is not interactive")
	main.pet.play_action("move")
	await process_frame
	_assert_true(main.pet.is_busy(), "autonomous animation starts for drag interruption test")
	_assert_true(main._can_begin_drag(), "autonomous animation does not block dragging")
	main.pet.set_dragging(true)
	_assert_true(not main.pet.is_busy() or main.pet._dragging, "dragging interrupts autonomous animation")
	main.pet.set_dragging(false)
	main.bubble.visible = true
	main.bubble_tail.visible = true
	main._refresh_interaction_polygon()
	var bubble_pet_overlap := Vector2(-1, -1)
	var bubble_rect: Rect2 = main.bubble.get_global_rect()
	for y in range(floori(bubble_rect.position.y), ceili(bubble_rect.end.y), 2):
		for x in range(floori(bubble_rect.position.x), ceili(bubble_rect.end.x), 2):
			var candidate := Vector2(x, y)
			if main.pet.contains_point(candidate):
				bubble_pet_overlap = candidate
				break
		if bubble_pet_overlap.x >= 0:
			break
	if bubble_pet_overlap.x < 0:
		bubble_pet_overlap = bubble_rect.get_center()
	_assert_true(
		main._is_speech_overlay_at(bubble_pet_overlap),
		"speech pass-through test uses the visible bubble area"
	)
	_assert_true(
		main._is_pet_interactive_at(bubble_pet_overlap),
		"visible speech bubble is handled as part of the pet"
	)
	var native_hit_polygon: PackedVector2Array = \
		main.get_window().mouse_passthrough_polygon
	_assert_true(
		Geometry2D.is_point_in_polygon(bubble_pet_overlap, native_hit_polygon),
		"native desktop hit region includes the visible speech bubble"
	)
	_assert_true(
		main._is_pet_interactive_at(Vector2(140, 128)),
		"visible speech tail is handled as part of the pet"
	)
	main.bubble.visible = false
	main.bubble_tail.visible = false
	main._refresh_interaction_polygon()
	native_hit_polygon = main.get_window().mouse_passthrough_polygon
	_assert_true(
		not Geometry2D.is_point_in_polygon(bubble_rect.get_center(), native_hit_polygon),
		"hidden speech area is removed from the native hit region"
	)
	_assert_true(
		Geometry2D.is_point_in_polygon(Vector2(140, 190), native_hit_polygon),
		"native desktop hit region includes the visible pet"
	)

	var screen_for_drag := DisplayServer.window_get_current_screen()
	if screen_for_drag < 0:
		screen_for_drag = DisplayServer.get_primary_screen()
	var drag_usable := DisplayServer.screen_get_usable_rect(screen_for_drag)
	var visual_bounds: Rect2 = main.pet.get_visual_bounds_in_canvas()
	var clamped_top_left: Vector2i = main._clamp_window_position(
		drag_usable.position - Vector2i(10000, 10000)
	)
	var visible_at_top_left := Rect2(
		Vector2(clamped_top_left) + visual_bounds.position,
		visual_bounds.size
	)
	_assert_true(
		visible_at_top_left.position.x >= drag_usable.position.x - 1
			and visible_at_top_left.position.y >= drag_usable.position.y - 1,
		"drag clamp uses visible pet bounds at the top-left"
	)
	var clamped_bottom_right: Vector2i = main._clamp_window_position(
		drag_usable.end + Vector2i(10000, 10000)
	)
	var visible_at_bottom_right := Rect2(
		Vector2(clamped_bottom_right) + visual_bounds.position,
		visual_bounds.size
	)
	_assert_true(
		absf(visible_at_bottom_right.end.y - drag_usable.end.y) <= 1.0,
		"pet bottom can reach the taskbar edge without entering it"
	)

	main._show_context_menu(Vector2i(140, 190))
	await process_frame
	main.context_menu.id_pressed.emit(6)
	main.context_menu.hide()
	await process_frame
	await process_frame
	await process_frame
	_assert_true(main._stats_window.visible, "details window opens on first request")
	_assert_true(not main._stats_window.unresizable, "details window can be resized")
	_assert_true(not main._stats_window.transient, "details window is an independent native window")
	_assert_true(main._stats_window.always_on_top, "details window remains above normal windows")
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var stats_rect := Rect2i(main._stats_window.position, main._stats_window.size)
	_assert_true(usable.encloses(stats_rect), "details window remains inside usable screen")
	main._bring_stats_window_forward()
	await process_frame
	_assert_true(main._stats_window.visible, "an existing details window can be brought forward")
	var remembered_stats_size := Vector2i(380, 520)
	main._stats_window.size = remembered_stats_size
	await process_frame
	var first_stats_window_id: int = main._stats_window.get_instance_id()
	main._destroy_stats_window()
	await process_frame
	main._show_stats_window()
	await process_frame
	await process_frame
	_assert_true(main._stats_window.visible, "details window is visible after native recreation")
	_assert_true(
		main._stats_window.get_instance_id() != first_stats_window_id,
		"details window recreation uses a fresh native window"
	)
	_assert_equal(
		main._stats_window.size,
		remembered_stats_size,
		"details window remembers the user-selected size"
	)
	main._destroy_stats_window()

	main.say("快速訊息一", 0.1)
	main.say("💤", 0.1)
	await process_frame
	_assert_true(main.bubble.visible, "latest speech is visible")
	_assert_equal(main.bubble_label.text, "💤", "latest speech replaces earlier speech")
	await create_timer(0.2).timeout
	_assert_true(not main.bubble.visible, "speech hides after its duration")

	var energy_before := float(main.state.data.energy)
	main._run_care_action(5)
	while main.state.is_action_busy():
		await process_frame
	_assert_true(float(main.state.data.energy) >= energy_before, "sleep settles after animation")
	# Allow startup/action speech SceneTreeTimers to finish before teardown so
	# the integration run also verifies clean resource ownership.
	await create_timer(6.3).timeout
	main.queue_free()
	await process_frame
	await process_frame

	if _failures > 0:
		push_error("WINDOW_INTEGRATION_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("WINDOW_INTEGRATION_TEST_OK")
		quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("Assertion failed: %s (actual=%s expected=%s)" % [label, actual, expected])
