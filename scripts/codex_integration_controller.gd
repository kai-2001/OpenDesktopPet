class_name CodexIntegrationController
extends RefCounted

const CodexNotificationReceiverScript = preload("res://scripts/codex_notification_receiver.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_PORT := 38571
const MIN_PORT := 1024
const MAX_PORT := 65535
const FOCUS_COMMAND := "$uri = 'vscode://command/chatgpt.openSidebar'; try { Start-Process $uri } catch {}; Start-Sleep -Milliseconds 250; $shell = New-Object -ComObject WScript.Shell; $process = Get-Process | Where-Object { $_.ProcessName -match '^Code' -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1; if ($process) { [void]$shell.AppActivate($process.Id) }"

signal notification_received(message: String, reaction_action: String)
signal state_changed

var enabled := false
var port := DEFAULT_PORT
var _receiver
var _last_event_id := ""


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) == OK:
		enabled = bool(config.get_value("codex", "enabled", false))
		port = normalize_port(int(config.get_value("codex", "port", DEFAULT_PORT)))
	if enabled:
		_write_port_file()
	_start_receiver()


func poll() -> void:
	if _receiver != null:
		_receiver.poll()


func shutdown() -> void:
	_stop_receiver()


func set_enabled(value: bool) -> void:
	enabled = value
	_save_settings()
	_start_receiver()
	state_changed.emit()


func set_pending_port(value: int) -> void:
	port = normalize_port(value)


func configure_port(value: int) -> bool:
	port = normalize_port(value)
	_save_settings()
	_write_port_file()
	return _run_configuration_tool()


func reconnect() -> bool:
	if not enabled:
		return false
	_start_receiver()
	return is_running()


func is_running() -> bool:
	return _receiver != null and _receiver.is_running()


func focus_codex_interface() -> void:
	if OS.get_name() != "Windows":
		return
	OS.create_process("powershell.exe", [
		"-NoProfile",
		"-WindowStyle",
		"Hidden",
		"-Command",
		FOCUS_COMMAND,
	])


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
	config.save(UI_SETTINGS_PATH)


func _codex_home_path() -> String:
	var configured_home := OS.get_environment("CODEX_HOME").strip_edges()
	if not configured_home.is_empty():
		return configured_home
	var user_profile := OS.get_environment("USERPROFILE").strip_edges()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".codex")


func _write_port_file() -> void:
	var codex_home := _codex_home_path()
	if codex_home.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(codex_home) != OK:
		return
	var port_file := codex_home.path_join("open_desktop_pet_notify_port.txt")
	var file := FileAccess.open(port_file, FileAccess.WRITE)
	if file != null:
		file.store_string(str(port))


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
