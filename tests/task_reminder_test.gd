extends SceneTree

const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderPresentationCoordinatorScript = preload(
	"res://scripts/task_reminder_presentation_coordinator.gd"
)
const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const TaskReminderRepositoryScript = preload("res://scripts/task_reminder_repository.gd")
const TaskReminderSectionScript = preload("res://scripts/task_reminder_section.gd")
const TaskReminderThemeScript = preload("res://scripts/task_reminder_theme.gd")

var _failures := 0
var _requested_status := ""
var _due_count := 0
const TEST_PATH := "user://test_runs/task_reminder_test.json"
const FUTURE_TEST_PATH := "user://test_runs/task_reminder_future.json"


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
		presentation.due_message(created),
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
	future_coordinator.reminder_due.connect(_capture_due)
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
	var due_message := future_presentation.due_message(future_timed)
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


func _cleanup() -> void:
	for test_path: String in [TEST_PATH, FUTURE_TEST_PATH]:
		for suffix: String in ["", ".tmp", ".backup"]:
			var path := test_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _capture_requested_status(_id: String, status: String) -> void:
	_requested_status = status


func _capture_due(_reminder: Dictionary) -> void:
	_due_count += 1


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
