extends SceneTree

const StatsWindowCoordinatorScript = preload("res://scripts/stats_window_coordinator.gd")
const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderRepositoryScript = preload("res://scripts/task_reminder_repository.gd")

const TEST_PATH := "user://test_runs/task_reminder_visual_test.json"
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var repository = TaskReminderRepositoryScript.new()
	repository.save_path = TEST_PATH
	var reminders = TaskReminderCoordinatorScript.new()
	reminders.repository = repository
	reminders.initialize()
	_seed(reminders)

	for theme_mode: String in ["light", "dark"]:
		var host := Node.new()
		get_root().add_child(host)
		var coordinator = StatsWindowCoordinatorScript.new()
		coordinator.theme_mode = theme_mode
		coordinator.reminder_coordinator = reminders
		var refs: Dictionary = coordinator.build(host)
		var window := refs["window"] as Window
		var tabs := refs["tabs"] as TabContainer
		window.size = Vector2i(640, 620)
		tabs.current_tab = 1
		window.show()
		for _frame: int in 5:
			await process_frame
		var panel = refs["reminder_refs"].get("reminder_panel")
		_assert_true(panel != null, "%s reminder panel is built" % theme_mode)
		_assert_equal(panel._today_section._list.get_child_count(), 6, "%s today list is paged" % theme_mode)
		_assert_true(panel._today_section._more_button.visible, "%s show-more is visible" % theme_mode)
		_assert_true(
			panel._date_picker.transient and not panel._date_picker.exclusive,
			"%s date picker is a dismissible transient popup" % theme_mode
		)
		var capture_root := OS.get_environment("OPEN_DESKTOP_PET_UI_CAPTURE_DIR")
		if not capture_root.is_empty():
			DirAccess.make_dir_recursive_absolute(capture_root)
			_assert_equal(
				_capture(window, capture_root.path_join("task-reminders-%s.png" % theme_mode)),
				OK,
				"%s screenshot is saved" % theme_mode
			)
			panel.show_new_form()
			for _editor_frame: int in 3:
				await process_frame
			_assert_equal(
				_capture(window, capture_root.path_join("task-reminders-%s-editor.png" % theme_mode)),
				OK,
				"%s editor screenshot is saved" % theme_mode
			)
			panel._date_picker.open_for(panel._date_button, panel._editing_date)
			for _calendar_frame: int in 2:
				await process_frame
			_assert_equal(
				_capture(
					panel._date_picker,
					capture_root.path_join("task-reminders-%s-date-picker.png" % theme_mode)
				),
				OK,
				"%s date picker screenshot is saved" % theme_mode
			)
			_assert_equal(
				panel._date_picker._month_title.mouse_default_cursor_shape,
				Control.CURSOR_MOVE,
				"%s date picker exposes a draggable header" % theme_mode
			)
			var drag_press := InputEventMouseButton.new()
			drag_press.button_index = MOUSE_BUTTON_LEFT
			drag_press.pressed = true
			panel._date_picker._on_drag_handle_input(drag_press)
			_assert_true(panel._date_picker._dragging, "%s date picker begins dragging" % theme_mode)
			drag_press.pressed = false
			panel._date_picker._on_drag_handle_input(drag_press)
			_assert_true(not panel._date_picker._dragging, "%s date picker ends dragging" % theme_mode)
			panel._date_picker.hide()
			panel._hide_form()
			panel._today_section._header_button.pressed.emit()
			await process_frame
			_assert_equal(panel._today_section._header_state.text, "展開", "%s collapsed state is explicit" % theme_mode)
			_assert_equal(panel._today_section._header_chevron.text, "▾", "%s collapsed chevron points down" % theme_mode)
			if theme_mode == "light":
				_assert_equal(
					_capture(window, capture_root.path_join("task-reminders-light-section-collapsed.png")),
					OK,
					"collapsed section screenshot is saved"
				)
			panel._today_section._header_button.pressed.emit()
			await process_frame
			var first_item = panel._today_section._list.get_child(0)
			_assert_true(
				first_item.find_child("ReminderCompletion", true, false) == null,
				"%s reminder row has no ambiguous completion checkbox" % theme_mode
			)
			first_item.expand()
			for _expanded_frame: int in 2:
				await process_frame
			_assert_true(
				first_item.find_child("ReminderCompletionAction", true, false) != null,
				"%s reminder actions expose explicit completion" % theme_mode
			)
			_assert_equal(
				_capture(window, capture_root.path_join("task-reminders-%s-expanded.png" % theme_mode)),
				OK,
				"%s expanded screenshot is saved" % theme_mode
			)
			if theme_mode == "light":
				first_item._delete_button.pressed.emit()
				await process_frame
				_assert_equal(
					_capture(window, capture_root.path_join("task-reminders-light-delete-armed.png")),
					OK,
					"delete confirmation screenshot is saved"
				)
				panel._set_scope("upcoming")
				await process_frame
				_assert_equal(
					_capture(window, capture_root.path_join("task-reminders-light-upcoming.png")),
					OK,
					"upcoming scope screenshot is saved"
				)
		coordinator.destroy()
		host.queue_free()
		await process_frame

	_cleanup()
	if _failures > 0:
		push_error("TASK_REMINDER_VISUAL_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("TASK_REMINDER_VISUAL_TEST_OK")
		quit(0)


func _capture(window: Window, output: String) -> Error:
	return window.get_texture().get_image().save_png(output)


func _seed(coordinator) -> void:
	for index: int in 8:
		coordinator.create_reminder("今天的工作項目 %02d" % (index + 1), _relative_date(0), "", true)
	coordinator.create_reminder("已經逾期的合約確認", _relative_date(-2), "09:30", false)
	for index: int in 10:
		coordinator.create_reminder(
			"未來安排 %02d" % (index + 1), _relative_date(index + 1), "14:00", false
		)
	var closed: Dictionary = coordinator.create_reminder("已完成的測試工作", _relative_date(0), "", true)
	coordinator.set_status(String(closed.get("id", "")), "done")


func _relative_date(days: int) -> String:
	var now := Time.get_datetime_dict_from_system(false)
	var timestamp := Time.get_unix_time_from_datetime_dict(now) + days * 86400
	var value := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [value.year, value.month, value.day]


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
