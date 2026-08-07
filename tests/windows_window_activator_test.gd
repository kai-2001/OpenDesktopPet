extends SceneTree


func _initialize() -> void:
	if OS.get_name() != "Windows":
		print("WINDOWS_WINDOW_ACTIVATOR_TEST_OK")
		quit(0)
		return
	if not ClassDB.class_exists("WindowsWindowActivator"):
		_fail("WindowsWindowActivator GDExtension class was not loaded.")
		return
	var activator = ClassDB.instantiate("WindowsWindowActivator")
	if activator == null:
		_fail("WindowsWindowActivator could not be instantiated.")
		return
	if bool(activator.call(
		"is_executable_foreground",
		"C:/OpenDesktopPet-Test/Executable-Does-Not-Exist.exe"
	)):
		_fail("A nonexistent executable must not be considered foreground.")
		return
	if bool(activator.call(
		"focus_executable",
		"C:/OpenDesktopPet-Test/Executable-Does-Not-Exist.exe",
		0
	)):
		_fail("A nonexistent executable must not report focus success.")
		return
	print("WINDOWS_WINDOW_ACTIVATOR_TEST_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
