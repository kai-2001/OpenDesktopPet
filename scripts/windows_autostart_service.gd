class_name WindowsAutostartService
extends RefCounted

signal operation_completed(
	operation_id: int,
	operation: String,
	enabled: bool,
	result: Dictionary
)

const REGISTRY_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const VALUE_NAME := "Open Desktop Pet"

var _threads: Dictionary = {}
var _operation_serial := 0
var _latest_operation_id := 0


func is_supported() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


func query() -> void:
	_start_operation("query", false)


func set_enabled(enabled: bool) -> void:
	_start_operation("set", enabled)


func is_latest_operation(operation_id: int) -> bool:
	return operation_id == _latest_operation_id


func build_command(executable_path: String) -> String:
	return _autostart_command(executable_path)


func shutdown() -> void:
	for operation_id: int in _threads.keys():
		_finish_thread(operation_id)


func _start_operation(operation: String, enabled: bool) -> void:
	_operation_serial += 1
	var operation_id := _operation_serial
	_latest_operation_id = operation_id
	var operation_thread := Thread.new()
	_threads[operation_id] = operation_thread
	var start_error := operation_thread.start(
		Callable(self, "_run_operation").bind(operation_id, operation, enabled)
	)
	if start_error != OK:
		_threads.erase(operation_id)
		operation_completed.emit(
			operation_id,
			operation,
			enabled,
			{"exists": false, "matches": false, "success": false}
		)


func _run_operation(
	operation_id: int,
	operation: String,
	enabled: bool
) -> void:
	var result: Dictionary
	if operation == "query":
		result = _query_state_blocking()
	else:
		result = {"success": _write_state_blocking(enabled)}
	call_deferred(
		"_publish_operation_result",
		operation_id,
		operation,
		enabled,
		result
	)


func _publish_operation_result(
	operation_id: int,
	operation: String,
	enabled: bool,
	result: Dictionary
) -> void:
	_finish_thread(operation_id)
	operation_completed.emit(operation_id, operation, enabled, result)


func _finish_thread(operation_id: int) -> void:
	var operation_thread: Thread = _threads.get(operation_id)
	if is_instance_valid(operation_thread) and operation_thread.is_started():
		operation_thread.wait_to_finish()
	_threads.erase(operation_id)


func _query_state_blocking() -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(
		_registry_executable(),
		PackedStringArray(["query", REGISTRY_KEY, "/v", VALUE_NAME]),
		output,
		true,
		false
	)
	var exists := exit_code == 0
	var output_text := "\n".join(PackedStringArray(output)).strip_edges()
	var executable_path := OS.get_executable_path()
	var expected_command := _autostart_command(executable_path)
	var legacy_command := "\"%s\"" % executable_path.replace("\\", "/")
	return {
		"exists": exists,
		"matches": exists and output_text.to_lower().contains(expected_command.to_lower()),
		"legacy_matches": exists and output_text.to_lower().contains(legacy_command.to_lower()),
		"output": output_text,
	}


func _write_state_blocking(enabled: bool) -> bool:
	var arguments: PackedStringArray
	if enabled:
		arguments = PackedStringArray([
			"add", REGISTRY_KEY, "/v", VALUE_NAME, "/t", "REG_SZ", "/d",
			"\\\"%s\\\"" % _native_windows_path(OS.get_executable_path()),
			"/f",
		])
	else:
		arguments = PackedStringArray([
			"delete", REGISTRY_KEY, "/v", VALUE_NAME, "/f",
		])
	var output: Array = []
	var exit_code := OS.execute(_registry_executable(), arguments, output, true, false)
	if exit_code != 0:
		push_warning(
			"Windows autostart registry command failed (%d): %s" % [
				exit_code,
				"\n".join(PackedStringArray(output)).strip_edges(),
			]
		)
	return exit_code == 0


func _registry_executable() -> String:
	var windows_root := OS.get_environment("SystemRoot")
	if windows_root.is_empty():
		windows_root = "C:\\Windows"
	return windows_root.path_join("System32").path_join("reg.exe")


func _autostart_command(executable_path: String) -> String:
	return "\"%s\"" % _native_windows_path(executable_path)


func _native_windows_path(path: String) -> String:
	return path.replace("/", "\\")
