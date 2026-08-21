extends SceneTree

const TaskReminderBadgeScript = preload("res://scripts/task_reminder_badge.gd")
const TaskReminderBadgeStateScript = preload("res://scripts/task_reminder_badge_state.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var badge = TaskReminderBadgeScript.new()
	get_root().add_child(badge)
	await process_frame
	badge.present(TaskReminderBadgeStateScript.new())
	_assert_true(not badge.visible, "badge stays hidden without today reminders")

	badge.present(TaskReminderBadgeStateScript.new(
		true, "2", "今日待辦 2 件\n點擊開啟待辦頁"
	))
	_assert_true(badge.visible, "badge is visible with today reminders")
	_assert_equal(badge.text, "2", "badge displays the today reminder count")
	_assert_true(
		badge.tooltip_text.contains("今日待辦 2 件"),
		"today badge identifies its count in the tooltip"
	)

	badge.present(TaskReminderBadgeStateScript.new(
		false, "", "", "!", "逾期待辦 3 件\n點擊開啟待辦頁"
	))
	_assert_true(not badge.visible, "overdue reminders do not create a persistent badge")
	badge.present(TaskReminderBadgeStateScript.new(
		false, "", "", "!", "逾期待辦 3 件\n點擊開啟待辦頁"
	), true)
	_assert_true(badge.visible and badge.text == "!", "overdue reminders use a temporary attention badge")
	await create_timer(1.0).timeout
	_assert_true(not badge.visible, "overdue attention badge disappears after two pulses")

	badge.present(TaskReminderBadgeStateScript.new(
		true, "1", "今日待辦 1 件，逾期 2 件\n點擊開啟待辦頁", "1",
		"今日待辦 1 件，逾期 2 件\n點擊開啟待辦頁"
	), true)
	await create_timer(1.0).timeout
	_assert_true(badge.visible and badge.text == "1", "today badge remains after overdue attention")
	badge.queue_free()
	if _failures > 0:
		push_error("TASK_REMINDER_BADGE_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("TASK_REMINDER_BADGE_TEST_OK")
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
