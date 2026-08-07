class_name CodexIntegrationController
extends RefCounted

const CodexNotificationReceiverScript = preload("res://scripts/codex_notification_receiver.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_PORT := 38571
const MIN_PORT := 1024
const MAX_PORT := 65535
const PORT_FILE_NAME := "open_desktop_pet_notify_port.txt"
const ENABLED_FILE_NAME := "open_desktop_pet_notify_enabled.txt"
const CODEX_URI := "vscode://command/chatgpt.openSidebar"

signal notification_received(message: String, reaction_action: String)
signal state_changed

var enabled := false
var port := DEFAULT_PORT
var executable_path := ""
var _receiver
var _last_event_id := ""
var _window_activator


func _init() -> void:
	if ClassDB.class_exists("WindowsWindowActivator"):
		_window_activator = ClassDB.instantiate("WindowsWindowActivator")


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) == OK:
		enabled = bool(config.get_value("codex", "enabled", false))
		port = normalize_port(int(config.get_value("codex", "port", DEFAULT_PORT)))
		executable_path = _normalize_executable_path(String(
			config.get_value("codex", "executable_path", "")
		))
	if executable_path.is_empty():
		executable_path = detect_vscode_executable()
		if not executable_path.is_empty():
			_save_settings()
	_write_bridge_files(enabled)
	_start_receiver()


func poll() -> void:
	if _receiver != null:
		_receiver.poll()


func shutdown() -> void:
	_stop_receiver()
	_write_bridge_files(false)


func set_enabled(value: bool) -> void:
	enabled = value
	_save_settings()
	_write_bridge_files(enabled)
	_start_receiver()
	if enabled and DisplayServer.get_name() != "headless":
		_run_configuration_tool()
	state_changed.emit()


func set_port(value: int) -> void:
	port = normalize_port(value)
	_save_settings()
	_write_bridge_files(enabled)
	if enabled:
		_start_receiver()
	state_changed.emit()


func set_executable_path(value: String) -> void:
	executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func is_running() -> bool:
	return _receiver != null and _receiver.is_running()


func focus_codex_interface() -> bool:
	if not has_valid_executable_path():
		return false
	var process_id := OS.create_process(executable_path, [
		"--reuse-window",
		"--open-url",
		CODEX_URI,
	])
	if process_id == -1 or _window_activator == null:
		return false
	return bool(_window_activator.call(
		"focus_executable", executable_path, 1000
	))


func has_native_window_focus_support() -> bool:
	return _window_activator != null


func is_codex_interface_foreground() -> bool:
	if not has_valid_executable_path() or _window_activator == null:
		return false
	return bool(_window_activator.call(
		"is_executable_foreground", executable_path
	))


func has_valid_executable_path() -> bool:
	return not executable_path.is_empty() \
		and executable_path.get_extension().to_lower() == "exe" \
		and FileAccess.file_exists(executable_path)


func detect_vscode_executable() -> String:
	var candidates: Array[String] = []
	_append_install_candidates(
		candidates, OS.get_environment("LOCALAPPDATA"), "Programs"
	)
	_append_install_candidates(candidates, OS.get_environment("ProgramFiles"))
	_append_install_candidates(candidates, OS.get_environment("ProgramFiles(x86)"))
	for path_entry: String in OS.get_environment("PATH").split(";", false):
		var directory := path_entry.strip_edges().trim_prefix('"').trim_suffix('"')
		if directory.is_empty():
			continue
		candidates.append(directory.path_join("Code.exe"))
		candidates.append(directory.path_join("Code - Insiders.exe"))
		if directory.get_file().to_lower() == "bin":
			candidates.append(directory.get_base_dir().path_join("Code.exe"))
			candidates.append(
				directory.get_base_dir().path_join("Code - Insiders.exe")
			)
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	return ""


func normalize_port(value: int) -> int:
	return clampi(value, MIN_PORT, MAX_PORT)


func _start_receiver() -> void:
	_stop_receiver()
	if not enabled:
		return
	_receiver = CodexNotificationReceiverScript.new()
	_receiver.notification_received.connect(_handle_notification)
	if not _receiver.start(port):
		push_warning("無法啟用 Codex 通知接收器；連接埠可能已被使用。")
		_receiver = null


func _stop_receiver() -> void:
	if _receiver != null:
		_receiver.stop()
		_receiver = null


func _handle_notification(notification: Dictionary) -> void:
	var event_type := String(notification.get("type", "")).to_lower()
	var event_id := "%s:%s" % [
		String(notification.get("thread-id", notification.get("thread_id", ""))),
		String(notification.get("turn-id", notification.get("turn_id", ""))),
	]
	if not event_id.ends_with(":") and event_id == _last_event_id:
		return
	if not event_id.ends_with(":"):
		_last_event_id = event_id

	match event_type:
		"agent-turn-complete", "codex_done", "completed", "done":
			notification_received.emit(
				"Codex 完成了這一輪，可以切回 VS Code 看結果。", "pet"
			)
		"codex_waiting", "waiting", "approval-requested":
			notification_received.emit(
				"Codex 正在等你回到 VS Code 處理一個請求。", "idle"
			)
		"codex_error", "failed", "error":
			notification_received.emit(
				"Codex 這一輪遇到問題，請回 VS Code 檢查。", "idle"
			)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("codex", "enabled", enabled)
	config.set_value("codex", "port", port)
	config.set_value("codex", "executable_path", executable_path)
	config.save(UI_SETTINGS_PATH)


func _append_install_candidates(
	candidates: Array[String], base_path: String, programs_subdir := ""
) -> void:
	var root := base_path.strip_edges()
	if root.is_empty():
		return
	if not programs_subdir.is_empty():
		root = root.path_join(programs_subdir)
	candidates.append(root.path_join("Microsoft VS Code/Code.exe"))
	candidates.append(
		root.path_join("Microsoft VS Code Insiders/Code - Insiders.exe")
	)
	candidates.append(root.path_join("VSCodium/VSCodium.exe"))


func _normalize_executable_path(value: String) -> String:
	var normalized := value.strip_edges().trim_prefix('"').trim_suffix('"')
	return normalized.simplify_path() if not normalized.is_empty() else ""


func _codex_home_path() -> String:
	var configured_home := OS.get_environment("CODEX_HOME").strip_edges()
	if not configured_home.is_empty():
		return configured_home
	var user_profile := OS.get_environment("USERPROFILE").strip_edges()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".codex")


func _write_bridge_files(sender_enabled: bool) -> void:
	var codex_home := _codex_home_path()
	if codex_home.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(codex_home) != OK:
		return
	var port_file := codex_home.path_join(PORT_FILE_NAME)
	var file := FileAccess.open(port_file, FileAccess.WRITE)
	if file != null:
		file.store_string(str(port))
		file.close()
	var enabled_file := codex_home.path_join(ENABLED_FILE_NAME)
	file = FileAccess.open(enabled_file, FileAccess.WRITE)
	if file != null:
		file.store_string("1" if sender_enabled else "0")
		file.close()


func _run_configuration_tool() -> bool:
	var installer_path := ""
	if OS.has_feature("editor"):
		installer_path = ProjectSettings.globalize_path(
			"res://tools/install_codex_integration.ps1"
		)
	else:
		installer_path = OS.get_executable_path().get_base_dir().path_join(
			"tools/install_codex_integration.ps1"
		)
	if not FileAccess.file_exists(installer_path):
		return false
	var process_id := OS.create_process("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-WindowStyle",
		"Hidden",
		"-File",
		installer_path,
	])
	return process_id != -1
