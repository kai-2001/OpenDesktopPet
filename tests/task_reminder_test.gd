extends SceneTree

const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderPresentationCoordinatorScript = preload(
	"res://scripts/task_reminder_presentation_coordinator.gd"
)
const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const TaskReminderRepositoryScript = preload("res://scripts/task_reminder_repository.gd")
const TaskReminderSectionScript = preload("res://scripts/task_reminder_section.gd")
const TaskReminderThemeScript = preload("res://scripts/task_reminder_theme.gd")
const TaskReminderPanelScript = preload("res://scripts/task_reminder_panel.gd")
const TaskReminderDatePickerScript = preload("res://scripts/task_reminder_date_picker.gd")

var _failures := 0
var _requested_status := ""
var _due_count := 0
const TEST_PATH := "user://test_runs/task_reminder_test.json"
const FUTURE_TEST_PATH := "user://test_runs/task_reminder_future.json"
const PANEL_TEST_PATH := "user://test_runs/task_reminder_panel.json"
const REVIEW_TEST_PATH := "user://test_runs/task_reminder_review.json"


class FakeTimeCoordinator extends TaskReminderCoordinatorScript:
	var fake_date := ""
	var fake_time := ""

	func _today() -> String:
		return fake_date

	func _current_time() -> String:
		return fake_time


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	var repository = TaskReminderRepositoryScript.new()
	repository.save_path = TEST_PATH
	var coordinator = TaskReminderCoordinatorScript.new()
	coordinator.repository = repository
	coordinator.initialize()
	var presentation = TaskReminderPresentationCoordinatorScript.new()
	presentation.configure(coordinator)
	var migrated_progress := repository.create(
		"舊進行中資料", Time.get_date_string_from_system(false), "", true, "in_progress"
	)
	_assert_equal(
		String(migrated_progress.get("status", "")),
		"todo",
		"legacy in-progress status migrates to pending"
	)
	repository.remove(String(migrated_progress.get("id", "")))
	var migrated_cancelled := repository.create(
		"舊取消資料", Time.get_date_string_from_system(false), "", true, "cancelled"
	)
	_assert_equal(
		String(migrated_cancelled.get("status", "")),
		"done",
		"legacy cancelled status remains closed as completed"
	)
	repository.remove(String(migrated_cancelled.get("id", "")))

	var today := Time.get_date_string_from_system(false)
	var created: Dictionary = coordinator.create_reminder(
		"測試今天的待辦", today, "", true
	)
	_assert_true(not created.is_empty(), "today reminder can be created")
	_assert_equal(coordinator.get_open_today_reminders().size(), 1, "today open reminder is listed")
	_assert_true(
		not presentation.startup_message().is_empty(),
		"today reminder requests a startup presentation"
	)
	_assert_true(
		presentation.startup_message().contains("測試今天的待辦"),
		"startup presentation contains the reminder title"
	)
	_assert_equal(
		presentation.due_message([created] as Array[Dictionary]),
		"",
		"all-day reminder does not gain a timed due message"
	)

	var future_repository = TaskReminderRepositoryScript.new()
	future_repository.save_path = FUTURE_TEST_PATH
	var future_coordinator = FakeTimeCoordinator.new()
	future_coordinator.repository = future_repository
	future_coordinator.fake_date = today
	future_coordinator.fake_time = "10:00"
	future_coordinator.initialize()
	var future_timed := future_coordinator.create_reminder(
		"尚未到時間的待辦", today, "11:00", false
	)
	_assert_true(not future_timed.is_empty(), "future timed reminder can be created")
	_assert_equal(
		future_coordinator.get_open_today_reminders().size(),
		1,
		"future timed reminder remains visible in today's list"
	)
	_assert_true(
		future_coordinator.get_due_open_today_reminders().is_empty(),
		"future timed reminder is not due before its time"
	)
	var future_presentation := TaskReminderPresentationCoordinatorScript.new()
	future_presentation.configure(future_coordinator)
	future_coordinator.reminders_due.connect(_capture_due)
	_assert_equal(
		future_presentation.startup_message(),
		"",
		"future timed reminder does not show a startup notification"
	)
	_assert_true(
		not future_presentation.badge_state().visible,
		"future timed reminder does not show the reminder badge"
	)
	future_coordinator.fake_time = "11:00"
	_assert_equal(
		future_coordinator.get_due_open_today_reminders().size(),
		1,
		"timed reminder becomes due at its configured time"
	)
	_assert_true(
		not future_presentation.startup_message().is_empty(),
		"due timed reminder can show a startup notification"
	)
	future_coordinator.process(15.0)
	_assert_equal(_due_count, 1, "timed reminder emits its due notification")
	var due_message: String = future_presentation.due_message([future_timed] as Array[Dictionary])
	_assert_equal(
		due_message,
		"・11:00 尚未到時間的待辦",
		"timed reminder provides a concise speech-bubble message"
	)

	var reopened = TaskReminderCoordinatorScript.new()
	var reopened_repository = TaskReminderRepositoryScript.new()
	reopened_repository.save_path = TEST_PATH
	reopened.repository = reopened_repository
	reopened.initialize()
	var reopened_presentation = TaskReminderPresentationCoordinatorScript.new()
	reopened_presentation.configure(reopened)
	_assert_true(not reopened_presentation.startup_message().is_empty(), "reopening retains the startup presentation")

	var updated := coordinator.set_status(
		String(created.get("id", "")), "done"
	)
	_assert_equal(String(updated.get("status", "")), "done", "status can be completed")
	_assert_true(
		coordinator.get_open_today_reminders().is_empty(),
		"completed reminder is no longer open today"
	)
	_assert_true(
		coordinator.get_open_today_reminders().is_empty(),
		"completed reminder clears the today reminder query"
	)
	_assert_equal(presentation.startup_message(), "", "completed reminder clears the startup presentation")
	_assert_context_menu_today_section_visibility()

	for index: int in 9:
		coordinator.create_reminder(
			"未來待辦 %02d" % index, _relative_date(index + 1), "", true
		)
	coordinator.create_reminder("逾期待辦", _relative_date(-1), "", true)
	_assert_equal(
		coordinator.get_upcoming_reminders().size(),
		9,
		"upcoming query returns the complete collection for paged UI"
	)
	_assert_equal(
		coordinator.get_upcoming_reminders(4).size(),
		4,
		"upcoming query still supports an explicit limit"
	)
	_assert_equal(coordinator.get_overdue_reminders().size(), 1, "overdue items are separated")
	_assert_equal(coordinator.get_completed_reminders().size(), 1, "completed items are separated")

	var section := TaskReminderSectionScript.new()
	section.configure(
		"接下來", "未來事項", "沒有未來待辦", TaskReminderThemeScript.new("light"), 3, false
	)
	get_root().add_child(section)
	section.set_items(coordinator.get_upcoming_reminders())
	await process_frame
	_assert_equal(section._list.get_child_count(), 3, "large sections render only the first page")
	_assert_true(section._more_button.visible, "large sections expose a show-more action")
	_requested_status = ""
	section.status_requested.connect(_capture_requested_status)
	var first_completion_action := section._list.get_child(0).find_child(
		"ReminderCompletionAction", true, false
	) as Button
	_assert_true(first_completion_action != null, "pending reminder exposes completion action")
	first_completion_action.pressed.emit()
	_assert_equal(_requested_status, "done", "completion action requests the completed state")
	section._more_button.pressed.emit()
	await process_frame
	_assert_equal(section._list.get_child_count(), 6, "show-more renders one additional page")
	var last_id := String(coordinator.get_upcoming_reminders()[-1].get("id", ""))
	_assert_true(section.focus_reminder(last_id), "focusing a hidden reminder expands its page")
	await process_frame
	_assert_equal(section._list.get_child_count(), 9, "focused hidden reminder becomes visible")
	section.queue_free()
	await process_frame

	reopened_repository.load_data()
	_assert_equal(reopened_repository.all().size(), 11, "saved reminders survive reload")
	_assert_equal(
		String(reopened_repository.all()[0].get("title", "")),
		"測試今天的待辦",
		"reloaded reminder keeps UTF-8 title"
	)

	_assert_date_time_parsing()
	await _assert_schedule_is_typed_or_picked()
	await _assert_calendar_grid()
	_assert_date_change_refreshes()
	_assert_restart_does_not_repeat_overdue()
	_assert_due_reminders_share_one_message()
	_assert_only_schedule_changes_remind_again()
	_assert_failed_saves_leave_no_trace()
	_assert_deferred_reminders_skip_finished_items()

	_cleanup()
	if _failures > 0:
		push_error("TASK_REMINDER_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("TASK_REMINDER_TEST_OK")
		quit(0)


func _relative_date(days: int) -> String:
	var now := Time.get_datetime_dict_from_system(false)
	var timestamp := Time.get_unix_time_from_datetime_dict(now) + days * 86400
	var value := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [value.year, value.month, value.day]


func _assert_context_menu_today_section_visibility() -> void:
	var menu := PopupMenu.new()
	PetMenuBuilderScript.populate_today_reminders(menu, [])
	_assert_equal(menu.item_count, 0, "empty today reminders do not add a menu section")
	PetMenuBuilderScript.populate_today_reminders(menu, [{
		"id": "menu-test",
		"title": "選單待辦",
		"all_day": true,
	}])
	_assert_equal(menu.item_count, 3, "today section contains only its separator, heading, and reminder")
	_assert_equal(menu.get_item_text(1), "今日待辦", "today section heading is displayed")
	_assert_true(
		menu.get_item_index(PetMenuBuilderScript.REMINDER_VIEW_ALL_ITEM_ID) == 1,
		"today section keeps the details shortcut"
	)
	_assert_true(
		not menu.is_item_disabled(menu.get_item_index(PetMenuBuilderScript.REMINDER_VIEW_ALL_ITEM_ID)),
		"today section shortcut is clickable"
	)
	menu.queue_free()


func _assert_date_time_parsing() -> void:
	for case: Array in [
		["9:30", "09:30"], ["930", "09:30"], ["0930", "09:30"], ["14", "14:00"],
		["9:5", "09:05"], ["１４：０５", "14:05"], ["23.59", "23:59"],
		["24:00", ""], ["9:60", ""], ["abc", ""], ["", ""],
	]:
		_assert_equal(TaskReminderDateTime.parse_time(case[0]), case[1], "time '%s' is read" % case[0])
	for case: Array in [
		["2026-10-26", "2026-10-26"], ["2026/1/5", "2026-01-05"], ["20261026", "2026-10-26"],
		["10/30", "2026-10-30"], ["1030", "2026-10-30"], ["１０／３０", "2026-10-30"],
		["2028年2月29日", "2028-02-29"], ["10月30日", "2026-10-30"],
		["2026-02-29", ""], ["13/01", ""], ["明天", ""], ["", ""],
	]:
		_assert_equal(
			TaskReminderDateTime.parse_date(case[0], "2026-10-26"), case[1], "date '%s' is read" % case[0]
		)
	_assert_equal(TaskReminderDateTime.step_time("23:59", 0, 1), "00:59", "hours wrap alone")
	_assert_equal(TaskReminderDateTime.step_time("23:59", 1, 1), "23:00", "minutes wrap alone")
	_assert_equal(TaskReminderDateTime.step_date("2026-10-31", 2, 1), "2026-11-01", "days move through months")
	_assert_equal(TaskReminderDateTime.step_date("2026-01-31", 1, 1), "2026-02-28", "months keep the day inside")
	_assert_equal(TaskReminderDateTime.step_date("2026-01-15", 1, -1), "2025-12-15", "months cross years")
	_assert_equal(TaskReminderDateTime.step_date("2028-02-29", 0, 1), "2029-02-28", "years keep the day inside")


func _assert_schedule_is_typed_or_picked() -> void:
	var repository = TaskReminderRepositoryScript.new()
	repository.save_path = PANEL_TEST_PATH
	var coordinator = TaskReminderCoordinatorScript.new()
	coordinator.repository = repository
	coordinator.initialize()
	var panel = TaskReminderPanelScript.new()
	panel.configure(coordinator, "light")
	get_root().add_child(panel)
	panel.show_new_form()
	await process_frame
	var time_edit := panel.find_child("ReminderTime", true, false) as LineEdit
	var date_edit := panel.find_child("ReminderDate", true, false) as LineEdit
	_assert_true(time_edit != null and date_edit != null, "date and time can be typed")
	_assert_true(not time_edit.editable, "all-day reminders need no time")
	_assert_true(
		time_edit.text.is_empty() and time_edit.placeholder_text.is_empty(),
		"an all-day reminder leaves the time field empty"
	)
	_assert_equal(
		(time_edit.get_theme_stylebox("read_only") as StyleBoxFlat).bg_color,
		TaskReminderThemeScript.new("light").color("surface_subtle"),
		"a time field that cannot be typed in looks disabled"
	)
	panel._title_edit.text = "選時間的待辦"
	panel._all_day_check_box.button_pressed = false
	_assert_true(time_edit.editable, "timed reminders can type a time")
	_assert_true(
		not TaskReminderDateTime.parse_time(time_edit.text).is_empty(),
		"a timed reminder starts from a valid time"
	)

	time_edit.text = "１４：０５"
	time_edit.text_submitted.emit(time_edit.text)
	_assert_equal(time_edit.text, "14:05", "a typed time is tidied when submitted")
	_assert_equal(panel._time_picker._minute_buttons.size(), 60, "the picker offers every minute")
	panel._time_picker.open_for(time_edit, panel._editing_time)
	panel._time_picker._hour_buttons[9].pressed.emit()
	_assert_equal(time_edit.text, "09:05", "picking an hour keeps the typed minute")
	panel._time_picker._minute_buttons[37].pressed.emit()
	_assert_equal(time_edit.text, "09:37", "picking a minute fills the field")
	panel._time_picker.hide()
	time_edit.caret_column = 1
	panel._on_schedule_edit_input(time_edit, _key(KEY_UP))
	_assert_equal(time_edit.text, "10:37", "Up on the hour adds an hour")
	time_edit.caret_column = 4
	panel._on_schedule_edit_input(time_edit, _key(KEY_DOWN))
	_assert_equal(time_edit.text, "10:36", "Down on the minute removes a minute")

	date_edit.text = "1030"
	date_edit.text_submitted.emit(date_edit.text)
	var year := Time.get_date_string_from_system(false).left(4)
	_assert_equal(date_edit.text, "%s-10-30" % year, "a typed month and day use this year")
	_assert_true(panel._date_hint.text.begins_with("星期"), "the weekday is shown beside the date")
	date_edit.caret_column = 6
	panel._on_schedule_edit_input(date_edit, _key(KEY_UP))
	_assert_equal(date_edit.text, "%s-11-30" % year, "Up on the month adds a month")

	time_edit.text = "25:00"
	panel._save_form()
	_assert_true(coordinator.get_all_reminders().is_empty(), "an unreadable time is not saved")
	_assert_true(panel._form_feedback.text.contains("時間"), "an unreadable time is explained")
	time_edit.text = "10:36"
	panel._save_form()
	var saved: Array[Dictionary] = coordinator.get_all_reminders()
	_assert_equal(saved.size(), 1, "typed date and time save the reminder")
	_assert_equal(String(saved[0].get("due_date", "")), "%s-11-30" % year, "the date is saved")
	_assert_equal(String(saved[0].get("due_time", "")), "10:36", "the time is saved")
	_assert_true(not bool(saved[0].get("all_day", true)), "a timed reminder is saved")

	panel._all_day_check_box.button_pressed = true
	_assert_true(time_edit.text.is_empty(), "choosing all-day clears the time")
	panel._all_day_check_box.button_pressed = false
	panel._show_edit_form(saved[0])
	_assert_equal(time_edit.text, "10:36", "editing shows the saved time")
	panel.queue_free()
	await process_frame


func _assert_calendar_grid() -> void:
	var picker = TaskReminderDatePickerScript.new()
	picker.configure(TaskReminderThemeScript.new("dark"))
	get_root().add_child(picker)
	picker._selected_date = "2026-02-10"
	picker._set_display_month("2026-02-10")
	var cells: Array = picker._dates_grid.get_children().filter(
		func(child: Node) -> bool: return child is Button
	)
	_assert_equal(cells.size(), 42, "the calendar always shows six weeks")
	_assert_equal(String(cells[0].get_meta("date")), "2026-02-01", "weeks start on Sunday")
	_assert_equal(String(cells[-1].get_meta("date")), "2026-03-14", "next month's days fill the grid")
	var selected := cells[9] as Button
	_assert_equal(String(selected.get_meta("date")), "2026-02-10", "cells follow the calendar")
	_assert_equal(
		(selected.get_theme_stylebox("normal") as StyleBoxFlat).bg_color,
		TaskReminderThemeScript.new("dark").color("accent"),
		"the chosen date is highlighted"
	)
	picker._shift_month(1)
	_assert_equal(picker._month_title.text, "2026 年 03 月", "the next month can be shown")
	picker.queue_free()
	await process_frame


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _fake_coordinator(path: String, date: String, time: String) -> FakeTimeCoordinator:
	var repository = TaskReminderRepositoryScript.new()
	repository.save_path = path
	var coordinator := FakeTimeCoordinator.new()
	coordinator.repository = repository
	coordinator.fake_date = date
	coordinator.fake_time = time
	coordinator.initialize()
	return coordinator


func _assert_date_change_refreshes() -> void:
	var coordinator := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-26", "23:59")
	coordinator.create_reminder("今天整日", "2026-10-26", "", true)
	coordinator.process(15.0)
	var changes := [0]
	coordinator.reminders_changed.connect(func() -> void: changes[0] += 1)
	coordinator.fake_date = "2026-10-27"
	coordinator.fake_time = "00:00"
	coordinator.process(15.0)
	_assert_equal(changes[0], 1, "a new day refreshes the today lists, badge and menu")
	coordinator.process(15.0)
	_assert_equal(changes[0], 1, "the same day does not refresh again")
	_cleanup()


func _assert_restart_does_not_repeat_overdue() -> void:
	var first := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-25", "08:00")
	first.create_reminder("昨天的定時待辦", "2026-10-25", "09:00", false)
	first.create_reminder("昨天的整日待辦", "2026-10-25", "", true)
	var restarted := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-26", "08:00")
	var due: Array[Dictionary] = []
	restarted.reminders_due.connect(func(items: Array[Dictionary]) -> void: due.append_array(items))
	restarted.process(15.0)
	_assert_true(due.is_empty(), "overdue reminders are not reminded again after a restart")
	var presentation = TaskReminderPresentationCoordinatorScript.new()
	presentation.configure(restarted)
	_assert_equal(presentation.startup_message(), "有 2 件逾期待辦", "the startup message names overdue reminders")
	var overdue_timed: Dictionary = restarted.get_overdue_reminders().filter(
		func(item: Dictionary) -> bool: return not bool(item.get("all_day", true))
	)[0]
	var batch: Array[Dictionary] = [overdue_timed]
	_assert_equal(
		presentation.due_message(batch), "・10/25 09:00 昨天的定時待辦",
		"a reminder from another day shows its date"
	)
	_cleanup()


func _assert_due_reminders_share_one_message() -> void:
	var coordinator := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-26", "08:00")
	for title: String in ["第一件", "第二件", "第三件", "第四件"]:
		coordinator.create_reminder(title, "2026-10-26", "09:00", false)
	var batches: Array = []
	coordinator.reminders_due.connect(func(items: Array[Dictionary]) -> void: batches.append(items))
	coordinator.fake_time = "09:00"
	coordinator.process(15.0)
	_assert_equal(batches.size(), 1, "reminders due together arrive together")
	var presentation = TaskReminderPresentationCoordinatorScript.new()
	presentation.configure(coordinator)
	var batch: Array[Dictionary] = batches[0]
	_assert_equal(
		presentation.due_message(batch),
		"・09:00 第一件\n・09:00 第三件\n・09:00 第二件\n・另外 1 件",
		"reminders due together share one bubble"
	)
	_cleanup()


func _assert_only_schedule_changes_remind_again() -> void:
	var coordinator := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-26", "10:00")
	var reminder: Dictionary = coordinator.create_reminder("已經到時間", "2026-10-26", "09:00", false)
	var due: Array[Dictionary] = []
	coordinator.reminders_due.connect(func(items: Array[Dictionary]) -> void: due.append_array(items))
	coordinator.process(15.0)
	due.clear()
	var id := String(reminder.get("id", ""))
	coordinator.update_reminder(id, {"title": "已經到時間（改標題）"})
	_assert_true(due.is_empty(), "editing only the title does not remind again")
	coordinator.set_status(id, "done")
	coordinator.set_status(id, "todo")
	_assert_true(due.is_empty(), "reopening a completed reminder does not remind again")
	coordinator.update_reminder(id, {"due_time": "09:30"})
	_assert_equal(due.size(), 1, "a new time is reminded again")
	_cleanup()


func _assert_failed_saves_leave_no_trace() -> void:
	var repository = TaskReminderRepositoryScript.new()
	repository.save_path = REVIEW_TEST_PATH
	var coordinator = TaskReminderCoordinatorScript.new()
	coordinator.repository = repository
	coordinator.initialize()
	var kept: Dictionary = coordinator.create_reminder("已保存", "2026-10-26", "", true)
	# A directory where the temporary save file goes makes every save fail.
	var blocker := ProjectSettings.globalize_path(REVIEW_TEST_PATH + ".tmp")
	DirAccess.make_dir_recursive_absolute(blocker)
	_assert_true(
		coordinator.create_reminder("寫不進去", "2026-10-26", "", true).is_empty(),
		"a reminder that cannot be saved is reported"
	)
	coordinator.create_reminder("寫不進去", "2026-10-26", "", true)
	_assert_equal(coordinator.get_all_reminders().size(), 1, "retrying a failed save leaves no duplicates")
	var id := String(kept.get("id", ""))
	coordinator.update_reminder(id, {"title": "改不了"})
	_assert_equal(String(coordinator.get_reminder(id).get("title", "")), "已保存", "a failed edit is undone")
	coordinator.delete_reminder(id)
	_assert_true(not coordinator.get_reminder(id).is_empty(), "a failed delete keeps the reminder")
	DirAccess.remove_absolute(blocker)
	_cleanup()


func _assert_deferred_reminders_skip_finished_items() -> void:
	var coordinator := _fake_coordinator(REVIEW_TEST_PATH, "2026-10-26", "10:00")
	var waiting: Dictionary = coordinator.create_reminder("還沒做", "2026-10-26", "09:00", false)
	var finished: Dictionary = coordinator.create_reminder("已經做完", "2026-10-26", "09:00", false)
	var presentation = TaskReminderPresentationCoordinatorScript.new()
	presentation.configure(coordinator)
	var batch: Array[Dictionary] = [waiting, finished]
	presentation.defer_due(batch)
	coordinator.set_status(String(finished.get("id", "")), "done")
	var deferred: Array[Dictionary] = presentation.take_deferred_due()
	_assert_equal(deferred.size(), 1, "a reminder completed while deferred is not said")
	_assert_equal(String(deferred[0].get("title", "")), "還沒做", "the open reminder is said later")
	_assert_true(presentation.take_deferred_due().is_empty(), "deferred reminders are said once")
	_cleanup()


func _cleanup() -> void:
	for test_path: String in [TEST_PATH, FUTURE_TEST_PATH, PANEL_TEST_PATH, REVIEW_TEST_PATH]:
		for suffix: String in ["", ".tmp", ".backup"]:
			var path := test_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _capture_requested_status(_id: String, status: String) -> void:
	_requested_status = status


func _capture_due(reminders: Array[Dictionary]) -> void:
	_due_count += reminders.size()


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
