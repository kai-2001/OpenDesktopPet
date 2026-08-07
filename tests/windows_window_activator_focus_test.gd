extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var executable_path := OS.get_environment(
		"OPEN_DESKTOP_PET_FOCUS_TEST_EXECUTABLE"
	).strip_edges()
	if executable_path.is_empty() or not FileAccess.file_exists(executable_path):
		_fail("Set OPEN_DESKTOP_PET_FOCUS_TEST_EXECUTABLE to an existing exe.")
		return
	if not ClassDB.class_exists("WindowsWindowActivator"):
		_fail("WindowsWindowActivator GDExtension class was not loaded.")
		return

	DisplayServer.window_set_title("OpenDesktopPet native focus test")
	DisplayServer.window_move_to_foreground()
	await create_timer(0.35).timeout

	var activator = ClassDB.instantiate("WindowsWindowActivator")
	if not bool(activator.call(
		"is_executable_foreground", OS.get_executable_path()
	)):
		_fail("The foreground Godot test window was not detected.")
		return
	if not bool(activator.call("focus_executable", executable_path, 1000)):
		_fail(String(activator.call("get_last_error")))
		return
	print("WINDOWS_WINDOW_ACTIVATOR_FOCUS_TEST_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
