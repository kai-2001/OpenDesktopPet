extends SceneTree

const StatsWindowCoordinatorScript = preload("res://scripts/stats_window_coordinator.gd")
const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderRepositoryScript = preload("res://scripts/task_reminder_repository.gd")

const TEST_PATH := "user://test_runs/windows_ime_char_repair_test.json"
const WM_KEYDOWN := 0x0100
const WM_KEYUP := 0x0101
const WM_CHAR := 0x0102
const WM_IME_STARTCOMPOSITION := 0x010D
const WM_IME_ENDCOMPOSITION := 0x010E
const VK_OEM_MINUS := 0xBD
const SCAN_MINUS := 0x0C
# Every character Godot drops from IME text, mixed with ones it keeps.
const IME_TEXT := "測試(A)!-.\"#$%&'"
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
	var host := Node.new()
	get_root().add_child(host)
	var coordinator = StatsWindowCoordinatorScript.new()
	coordinator.reminder_coordinator = reminders
	var refs: Dictionary = coordinator.build(host)
	var window := refs["window"] as Window
	(refs["tabs"] as TabContainer).current_tab = 1
	window.show()
	var panel = refs["reminder_refs"].get("reminder_panel")
	panel.show_new_form()
	for _frame: int in 5:
		await process_frame
	var title_edit := panel._title_edit as LineEdit
	_assert_true(title_edit.has_focus() and title_edit.is_editing(), "reminder title is being edited")
	var handle := DisplayServer.window_get_native_handle(
		DisplayServer.WINDOW_HANDLE, window.get_window_id()
	)

	var committed: Array[String] = [
		"%d,0,0" % WM_IME_STARTCOMPOSITION,
		"%d,0,0" % WM_IME_ENDCOMPOSITION,
	]
	for index: int in IME_TEXT.length():
		committed.append("%d,%d,1" % [WM_CHAR, IME_TEXT.unicode_at(index)])
	await _post(handle, committed)
	_assert_equal(title_edit.text, IME_TEXT, "IME-committed symbols reach the reminder title")

	title_edit.text = ""
	# Godot's message loop translates the key-down into its WM_CHAR, as it
	# does for real typing.
	var key_lparam := (SCAN_MINUS << 16) | 1
	await _post(handle, [
		"%d,%d,%d" % [WM_KEYDOWN, VK_OEM_MINUS, key_lparam],
		"%d,%d,%d" % [WM_KEYUP, VK_OEM_MINUS, key_lparam | (3 << 30)],
	])
	_assert_equal(title_edit.text, "-", "a typed symbol is inserted exactly once")

	window.hide()
	await process_frame
	window.show()
	panel.show_new_form()
	for _frame: int in 5:
		await process_frame
	handle = DisplayServer.window_get_native_handle(
		DisplayServer.WINDOW_HANDLE, window.get_window_id()
	)
	await _post(handle, ["%d,%d,1" % [WM_CHAR, "(".unicode_at(0)]])
	_assert_equal(title_edit.text, "(", "the repair survives hiding and showing the window")

	coordinator.destroy()
	host.queue_free()
	await process_frame
	_cleanup()
	if _failures > 0:
		push_error("WINDOWS_IME_CHAR_REPAIR_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("WINDOWS_IME_CHAR_REPAIR_TEST_OK")
		quit(0)


# The blocking call keeps Godot from pumping messages, so every posted
# message is processed in one batch, as with real keyboard input.
func _post(handle: int, messages: Array[String]) -> void:
	var arguments := PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", ProjectSettings.globalize_path("res://tests/post_window_messages.ps1"),
		"-WindowHandle", str(handle),
		"-Messages", ";".join(messages),
	])
	var output: Array = []
	var exit_code := OS.execute("powershell.exe", arguments, output, true)
	_assert_true(
		exit_code == 0 and "".join(output).contains("POST_WINDOW_MESSAGES_OK"),
		"window messages are posted: %s" % "".join(output)
	)
	for _frame: int in 3:
		await process_frame


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
