extends SceneTree

const ControllerScript = preload("res://scripts/agent_integration_controller.gd")

var _test_root := ""
var _previous_user_profile := ""
var _previous_codex_home := ""


func _init() -> void:
	_previous_user_profile = OS.get_environment("USERPROFILE")
	_previous_codex_home = OS.get_environment("CODEX_HOME")
	_test_root = ProjectSettings.globalize_path(
		"user://agent-runtime-state-test-" + str(Time.get_ticks_msec())
	)
	OS.set_environment("USERPROFILE", _test_root)
	OS.set_environment("CODEX_HOME", _test_root.path_join(".codex"))
	call_deferred("_run")


func _run() -> void:
	var integration_home := _test_root.path_join(".open-desktop-pet")
	var codex_home := _test_root.path_join(".codex")
	DirAccess.make_dir_recursive_absolute(integration_home)
	DirAccess.make_dir_recursive_absolute(codex_home)
	var legacy_codex_flag := codex_home.path_join(
		"open_desktop_pet_codex_app_enabled.txt"
	)
	_write(legacy_codex_flag, "1")

	var controller = ControllerScript.new()
	controller.codex_app_enabled = true
	controller.port = 49381
	_assert_true(controller._start_receiver(), "runtime owner starts its UDP receiver")
	_assert_true(controller._write_runtime_state(), "runtime registration is written")

	var runtime_path := integration_home.path_join("open_desktop_pet_runtime.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(runtime_path))
	_assert_true(parsed is Dictionary, "runtime registration is valid JSON")
	var runtime: Dictionary = parsed
	_assert_true(int(runtime.get("schema_version", 0)) == 1, "runtime schema version is recorded")
	_assert_true(
		String(runtime.get("instance_id", "")) == controller._runtime_instance_id,
		"runtime registration belongs to its owning instance"
	)
	_assert_true(int(runtime.get("port", 0)) == 49381, "runtime registration exposes the bound port")
	var enabled_targets: Dictionary = runtime.get("enabled_targets", {})
	_assert_true(
		bool(enabled_targets.get("codex_app", false)),
		"runtime registration records the active Codex App target"
	)
	_assert_true(
		not FileAccess.file_exists(legacy_codex_flag),
		"runtime migration removes obsolete Codex enable flags"
	)

	controller._remove_runtime_if_owned()
	_assert_true(not FileAccess.file_exists(runtime_path), "owner removes its own runtime registration")
	_write(runtime_path, JSON.stringify({"instance_id": "other-instance"}))
	controller._remove_runtime_if_owned()
	_assert_true(FileAccess.file_exists(runtime_path), "owner never removes another instance registration")

	controller._stop_receiver()
	_cleanup()
	print("AGENT_RUNTIME_STATE_TEST_OK")
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write " + path)
		return
	file.store_string(text)
	file.close()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _fail(message: String) -> void:
	printerr("AGENT_RUNTIME_STATE_TEST_FAILED: " + message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	OS.set_environment("USERPROFILE", _previous_user_profile)
	OS.set_environment("CODEX_HOME", _previous_codex_home)
	_remove_tree(_test_root)


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path := path.path_join(name)
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
