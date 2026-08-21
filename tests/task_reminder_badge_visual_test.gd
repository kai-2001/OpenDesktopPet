extends SceneTree

const TaskReminderBadgeScript = preload("res://scripts/task_reminder_badge.gd")
const TaskReminderBadgeStateScript = preload("res://scripts/task_reminder_badge_state.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node.new()
	get_root().add_child(host)
	var window := Window.new()
	window.size = Vector2i(280, 320)
	window.transparent = true
	host.add_child(window)
	var background := ColorRect.new()
	background.color = Color("#273237")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(background)
	var badge = TaskReminderBadgeScript.new()
	badge.position = Vector2(218, 92)
	window.add_child(badge)
	badge.present(TaskReminderBadgeStateScript.new(
		true, "3", "今日待辦 3 件\n點擊開啟待辦頁"
	))
	window.show()
	for _frame: int in 5:
		await process_frame
	var capture_root := OS.get_environment("OPEN_DESKTOP_PET_UI_CAPTURE_DIR")
	if not capture_root.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_root)
		_assert_equal(
			window.get_texture().get_image().save_png(
				capture_root.path_join("task-reminder-badge.png")
			),
			OK,
			"badge screenshot is saved"
		)
	_assert_true(badge.visible, "badge is visible in the visual fixture")
	_assert_equal(badge.size, Vector2(28, 28), "single-digit badge retains its compact size")
	window.queue_free()
	host.queue_free()
	if _failures > 0:
		push_error("TASK_REMINDER_BADGE_VISUAL_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("TASK_REMINDER_BADGE_VISUAL_TEST_OK")
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
