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

	main._show_context_menu(Vector2i(140, 190))
	await process_frame
	main.context_menu.id_pressed.emit(6)
	main.context_menu.hide()
	await process_frame
	await process_frame
	await process_frame
	_assert_true(main._stats_window.visible, "details window opens on first request")
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
