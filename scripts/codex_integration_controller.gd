class_name CodexIntegrationController
extends RefCounted

const CodexNotificationReceiverScript = preload("res://scripts/codex_notification_receiver.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_PORT := 38571
const MIN_PORT := 1024
const MAX_PORT := 65535
const PORT_FILE_NAME := "open_desktop_pet_notify_port.txt"
const CODEX_ENABLED_FILE_NAME := "open_desktop_pet_codex_enabled.txt"
const VSCODE_CODEX_ENABLED_FILE_NAME := "open_desktop_pet_vscode_codex_enabled.txt"
const CODEX_APP_ENABLED_FILE_NAME := "open_desktop_pet_codex_app_enabled.txt"
const TERMINAL_CODEX_ENABLED_FILE_NAME := "open_desktop_pet_terminal_codex_enabled.txt"
const COPILOT_ENABLED_FILE_NAME := "open_desktop_pet_copilot_enabled.txt"
const LEGACY_ENABLED_FILE_NAME := "open_desktop_pet_notify_enabled.txt"
const CODEX_INSTALL_MARKER := "open_desktop_pet_codex_installed.txt"
const COPILOT_INSTALL_MARKER := "open_desktop_pet_copilot_installed.txt"
const CODEX_URI := "vscode://command/chatgpt.openSidebar"
const TARGET_VSCODE := "vscode"
const TARGET_CODEX_APP := "codex_app"
const TARGET_TERMINAL := "terminal"

signal notification_received(message: String, reaction_action: String, target_app: String)
signal state_changed
signal configuration_failed(target_name: String)
signal executable_path_detection_started
signal executable_path_detection_finished

# `enabled` and `executable_path` remain compatibility aliases for older saves.
var enabled := false
var codex_enabled := false
var codex_app_enabled := false
var terminal_codex_enabled := false
var copilot_enabled := false
var port := DEFAULT_PORT
var executable_path := ""
var codex_app_executable_path := ""
var terminal_executable_path := ""
var _receiver
var _last_event_id := ""
var _active_target_app := TARGET_VSCODE
var _window_activator
var _executable_path_detection_thread: Thread


func _init() -> void:
	if ClassDB.class_exists("WindowsWindowActivator"):
		_window_activator = ClassDB.instantiate("WindowsWindowActivator")


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) == OK:
		codex_enabled = bool(config.get_value(
			"codex", "vscode_enabled", config.get_value("codex", "enabled", false)
		))
		codex_app_enabled = bool(config.get_value("codex_app", "enabled", false))
		terminal_codex_enabled = bool(
			config.get_value("codex_terminal", "enabled", false)
		)
		copilot_enabled = bool(config.get_value("copilot", "enabled", false))
		port = normalize_port(int(config.get_value("codex", "port", DEFAULT_PORT)))
		executable_path = _normalize_executable_path(String(config.get_value(
			"codex", "vscode_executable_path", config.get_value("codex", "executable_path", "")
		)))
		codex_app_executable_path = _normalize_executable_path(String(
			config.get_value("codex_app", "executable_path", "")
		))
		terminal_executable_path = _normalize_executable_path(String(
			config.get_value("codex_terminal", "executable_path", "")
		))
	# Older builds stored the internal Codex.exe path for the desktop app.
	# The visible ChatGPT/Codex desktop window is ChatGPT.exe, so migrate it
	# when both executables are in the same Windows App package.
	codex_app_executable_path = _migrate_codex_app_executable_path(
		codex_app_executable_path
	)
	enabled = codex_enabled
	_save_settings()
	_write_bridge_files()
	_start_receiver()


func poll() -> void:
	_poll_executable_path_detection()
	if _receiver != null:
		_receiver.poll()


func shutdown() -> void:
	_stop_executable_path_detection()
	_stop_receiver()
	_write_bridge_files(true)


func set_enabled(value: bool) -> void:
	set_codex_enabled(value)


func set_codex_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_codex_configuration("VS Code"):
		codex_enabled = false
		enabled = false
		_persist_agent_state()
		return
	codex_enabled = value
	enabled = value
	_persist_agent_state()


func set_codex_app_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_codex_configuration("ChatGPT"):
		codex_app_enabled = false
		_persist_agent_state()
		return
	codex_app_enabled = value
	_persist_agent_state()


func set_terminal_codex_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_codex_configuration("終端機"):
		terminal_codex_enabled = false
		_persist_agent_state()
		return
	terminal_codex_enabled = value
	_persist_agent_state()


func set_copilot_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_copilot_configuration():
		copilot_enabled = false
		_persist_agent_state()
		return
	copilot_enabled = value
	_persist_agent_state()


func set_port(value: int) -> void:
	port = normalize_port(value)
	_persist_agent_state()


func set_executable_path(value: String) -> void:
	executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func set_codex_app_executable_path(value: String) -> void:
	codex_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func set_terminal_executable_path(value: String) -> void:
	terminal_executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func refresh_agent_executable_paths_if_invalid() -> void:
	if _executable_path_detection_thread != null:
		return
	if _has_valid_executable_path(executable_path) \
			and _has_valid_executable_path(codex_app_executable_path) \
			and _has_valid_executable_path(terminal_executable_path):
		return

	var path_snapshot := {
		"vscode": executable_path,
		"codex_app": codex_app_executable_path,
		"terminal": terminal_executable_path,
	}
	_executable_path_detection_thread = Thread.new()
	var start_error := _executable_path_detection_thread.start(
		Callable(self, "_detect_invalid_executable_paths").bind(path_snapshot)
	)
	if start_error != OK:
		_executable_path_detection_thread = null
		return
	executable_path_detection_started.emit()


func _detect_invalid_executable_paths(path_snapshot: Dictionary) -> Dictionary:
	var detected_paths := {}
	if not _has_valid_executable_path(String(path_snapshot.get("vscode", ""))):
		detected_paths["vscode"] = detect_vscode_executable()
	if not _has_valid_executable_path(String(path_snapshot.get("codex_app", ""))):
		detected_paths["codex_app"] = detect_codex_app_executable()
	if not _has_valid_executable_path(String(path_snapshot.get("terminal", ""))):
		detected_paths["terminal"] = detect_terminal_executable()
	return detected_paths


func _poll_executable_path_detection() -> void:
	if _executable_path_detection_thread == null \
			or _executable_path_detection_thread.is_alive():
		return
	var detected_paths: Dictionary = _executable_path_detection_thread.wait_to_finish()
	_executable_path_detection_thread = null
	_apply_detected_executable_paths(detected_paths)
	executable_path_detection_finished.emit()


func _apply_detected_executable_paths(detected_paths: Dictionary) -> void:
	var changed := false
	if not _has_valid_executable_path(executable_path):
		var detected_vscode := _normalize_executable_path(
			String(detected_paths.get("vscode", ""))
		)
		if _has_valid_executable_path(detected_vscode):
			executable_path = detected_vscode
			changed = true
	if not _has_valid_executable_path(codex_app_executable_path):
		var detected_codex_app := _normalize_executable_path(
			String(detected_paths.get("codex_app", ""))
		)
		if _has_valid_executable_path(detected_codex_app):
			codex_app_executable_path = detected_codex_app
			changed = true
	if not _has_valid_executable_path(terminal_executable_path):
		var detected_terminal := _normalize_executable_path(
			String(detected_paths.get("terminal", ""))
		)
		if _has_valid_executable_path(detected_terminal):
			terminal_executable_path = detected_terminal
			changed = true
	if changed:
		_save_settings()
		state_changed.emit()


func _stop_executable_path_detection() -> void:
	if _executable_path_detection_thread == null:
		return
	_executable_path_detection_thread.wait_to_finish()
	_executable_path_detection_thread = null


func is_any_enabled() -> bool:
	return codex_enabled or codex_app_enabled or terminal_codex_enabled or copilot_enabled


func is_running() -> bool:
	return _receiver != null and _receiver.is_running()


func is_codex_configured() -> bool:
	return FileAccess.file_exists(_codex_home_path().path_join(CODEX_INSTALL_MARKER))


func is_copilot_configured() -> bool:
	return FileAccess.file_exists(_integration_home_path().path_join(
		COPILOT_INSTALL_MARKER
	))


func _ensure_codex_configuration(target_name: String) -> bool:
	if is_codex_configured():
		return true
	if _run_codex_configuration_tool() and is_codex_configured():
		return true
	configuration_failed.emit(target_name)
	return false


func _ensure_copilot_configuration() -> bool:
	if is_copilot_configured():
		return true
	if _run_copilot_configuration_tool() and is_copilot_configured():
		return true
	configuration_failed.emit("VS Code Copilot")
	return false


func _persist_agent_state() -> void:
	_save_settings()
	_write_bridge_files()
	if is_any_enabled():
		_start_receiver()
	else:
		_stop_receiver()
	state_changed.emit()


func focus_vscode_interface() -> bool:
	return _focus_target(TARGET_VSCODE)


func focus_codex_interface() -> bool:
	return _focus_target(_active_target_app)


func focus_current_target() -> bool:
	return _focus_target(_active_target_app)


func has_native_window_focus_support() -> bool:
	return _window_activator != null


func is_vscode_interface_foreground() -> bool:
	return _is_target_foreground(TARGET_VSCODE)


func is_codex_interface_foreground() -> bool:
	return is_current_target_foreground()


func is_current_target_foreground() -> bool:
	return _is_target_foreground(_active_target_app)


func get_active_target_app() -> String:
	return _active_target_app


func has_valid_executable_path() -> bool:
	return _has_valid_executable_path(executable_path)


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


func detect_codex_app_executable() -> String:
	var chatgpt := _detect_appx_executable("OpenAI.Codex", "ChatGPT.exe")
	if not chatgpt.is_empty():
		return chatgpt
	# Keep compatibility with package versions whose GUI executable was named
	# Codex.exe, while preferring ChatGPT.exe for current versions.
	return _detect_appx_executable("OpenAI.Codex", "Codex.exe")


func _migrate_codex_app_executable_path(path: String) -> String:
	if path.is_empty() or path.get_file().to_lower() != "codex.exe":
		return path
	var chatgpt_path := path.get_base_dir().path_join("ChatGPT.exe")
	if FileAccess.file_exists(chatgpt_path):
		return chatgpt_path.simplify_path()
	return path


func detect_terminal_executable() -> String:
	var windows_terminal := _detect_appx_executable(
		"Microsoft.WindowsTerminal", "WindowsTerminal.exe"
	)
	if not windows_terminal.is_empty():
		return windows_terminal
	var system_root := OS.get_environment("SystemRoot")
	if not system_root.is_empty():
		var powershell := system_root.path_join(
			"System32/WindowsPowerShell/v1.0/powershell.exe"
		)
		if FileAccess.file_exists(powershell):
			return powershell
	return ""


func normalize_port(value: int) -> int:
	return clampi(value, MIN_PORT, MAX_PORT)


func _start_receiver() -> void:
	_stop_receiver()
	if not is_any_enabled():
		return
	_receiver = CodexNotificationReceiverScript.new()
	_receiver.notification_received.connect(_handle_notification)
	if not _receiver.start(port):
		push_warning("Agent 通知接收器無法監聽通訊埠 %d。" % port)
		_receiver = null


func _stop_receiver() -> void:
	if _receiver != null:
		_receiver.stop()
		_receiver = null


func _handle_notification(notification: Dictionary) -> void:
	var event_type := String(notification.get("type", "")).to_lower()
	var source := String(notification.get("source", "codex")).to_lower()
	var agent := String(notification.get("agent", source)).to_lower()
	var target_app := _normalize_target_app(
		String(notification.get("target_app", TARGET_VSCODE)).to_lower()
	)
	if not _is_notification_enabled(source, agent, target_app):
		return
	_active_target_app = target_app
	var event_id := "%s:%s:%s" % [
		source,
		String(notification.get("thread-id", notification.get("thread_id", ""))),
		String(notification.get("turn-id", notification.get("turn_id", ""))),
	]
	if not event_id.ends_with(":") and event_id == _last_event_id:
		return
	if not event_id.ends_with(":"):
		_last_event_id = event_id

	var display_name := _display_name(source, agent)
	var target_name := _target_display_name(target_app)
	match event_type:
		"agent-turn-complete", "codex_done", "completed", "done":
			notification_received.emit(
				"%s 已完成這一輪，可以切回 %s 查看結果。" % [display_name, target_name],
				"pet", target_app
			)
		"codex_waiting", "waiting", "approval-requested":
			notification_received.emit(
				"%s 正在等待你回到 %s 處理下一步。" % [display_name, target_name],
				"idle", target_app
			)
		"codex_error", "failed", "error":
			notification_received.emit(
				"%s 發生錯誤，請回到 %s 查看。" % [display_name, target_name],
				"idle", target_app
			)


func _display_name(source: String, agent: String) -> String:
	if source == "copilot" or agent == "copilot":
		return "Copilot"
	return "Codex"


func _normalize_target_app(value: String) -> String:
	match value:
		TARGET_CODEX_APP, "app":
			return TARGET_CODEX_APP
		TARGET_TERMINAL, "shell", "powershell", "cmd":
			return TARGET_TERMINAL
		_:
			return TARGET_VSCODE


func _target_display_name(target_app: String) -> String:
	match target_app:
		TARGET_CODEX_APP:
			return "ChatGPT"
		TARGET_TERMINAL:
			return "終端機"
		_:
			return "VS Code"


func _is_notification_enabled(source: String, agent: String, target_app: String) -> bool:
	if source == "copilot" or agent == "copilot":
		return copilot_enabled
	match target_app:
		TARGET_CODEX_APP:
			return codex_app_enabled
		TARGET_TERMINAL:
			return terminal_codex_enabled
		_:
			return codex_enabled


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("codex", "enabled", codex_enabled)
	config.set_value("codex", "vscode_enabled", codex_enabled)
	config.set_value("codex", "port", port)
	config.set_value("codex", "executable_path", executable_path)
	config.set_value("codex", "vscode_executable_path", executable_path)
	config.set_value("codex_app", "enabled", codex_app_enabled)
	config.set_value("codex_app", "executable_path", codex_app_executable_path)
	config.set_value("codex_terminal", "enabled", terminal_codex_enabled)
	config.set_value("codex_terminal", "executable_path", terminal_executable_path)
	config.set_value("copilot", "enabled", copilot_enabled)
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


func _has_valid_executable_path(path: String) -> bool:
	return not path.is_empty() \
		and path.get_extension().to_lower() == "exe" \
		and FileAccess.file_exists(path)


func _codex_home_path() -> String:
	var configured_home := OS.get_environment("CODEX_HOME").strip_edges()
	if not configured_home.is_empty():
		return configured_home
	var user_profile := OS.get_environment("USERPROFILE").strip_edges()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".codex")


func _integration_home_path() -> String:
	var user_profile := OS.get_environment("USERPROFILE").strip_edges()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".open-desktop-pet")


func _write_bridge_files(disable_all := false) -> void:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(integration_home) != OK:
		return
	_write_port_file(integration_home)
	_write_flag(
		integration_home.path_join(CODEX_ENABLED_FILE_NAME),
		(codex_enabled or codex_app_enabled or terminal_codex_enabled) and not disable_all
	)
	_write_flag(
		integration_home.path_join(COPILOT_ENABLED_FILE_NAME),
		copilot_enabled and not disable_all
	)
	_write_codex_target_flags(integration_home, disable_all)

	# Keep legacy Codex-home bridge files in sync for existing installations.
	var codex_home := _codex_home_path()
	if codex_home.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(codex_home) != OK:
		return
	_write_port_file(codex_home)
	_write_flag(
		codex_home.path_join(LEGACY_ENABLED_FILE_NAME),
		(codex_enabled or codex_app_enabled or terminal_codex_enabled) and not disable_all
	)
	_write_flag(
		codex_home.path_join(CODEX_ENABLED_FILE_NAME),
		(codex_enabled or codex_app_enabled or terminal_codex_enabled) and not disable_all
	)
	_write_flag(
		codex_home.path_join(COPILOT_ENABLED_FILE_NAME),
		copilot_enabled and not disable_all
	)
	_write_codex_target_flags(codex_home, disable_all)


func _write_port_file(directory: String) -> void:
	var file := FileAccess.open(directory.path_join(PORT_FILE_NAME), FileAccess.WRITE)
	if file != null:
		file.store_string(str(port))
		file.close()


func _write_codex_target_flags(directory: String, disable_all: bool) -> void:
	_write_flag(
		directory.path_join(VSCODE_CODEX_ENABLED_FILE_NAME),
		codex_enabled and not disable_all
	)
	_write_flag(
		directory.path_join(CODEX_APP_ENABLED_FILE_NAME),
		codex_app_enabled and not disable_all
	)
	_write_flag(
		directory.path_join(TERMINAL_CODEX_ENABLED_FILE_NAME),
		terminal_codex_enabled and not disable_all
	)


func _write_flag(path: String, enabled_value: bool) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("1" if enabled_value else "0")
		file.close()


func _focus_target(target_app: String) -> bool:
	var target_path := _target_executable_path(target_app)
	if not _has_valid_executable_path(target_path) or _window_activator == null:
		return false
	if target_app == TARGET_VSCODE:
		var process_id := OS.create_process(target_path, [
			"--reuse-window",
			"--open-url",
			CODEX_URI,
		])
		if process_id == -1:
			return false
	else:
		if bool(_window_activator.call("focus_executable", target_path, 250)):
			return true
		var spawned_process_id := OS.create_process(target_path, [])
		if spawned_process_id == -1:
			return false
	return bool(_window_activator.call("focus_executable", target_path, 1000))


func _is_target_foreground(target_app: String) -> bool:
	var target_path := _target_executable_path(target_app)
	if not _has_valid_executable_path(target_path) or _window_activator == null:
		return false
	return bool(_window_activator.call(
		"is_executable_foreground", target_path
	))


func _target_executable_path(target_app: String) -> String:
	match target_app:
		TARGET_CODEX_APP:
			return codex_app_executable_path
		TARGET_TERMINAL:
			return terminal_executable_path
		_:
			return executable_path


func _detect_appx_executable(package_name: String, executable_name: String) -> String:
	if OS.get_name() != "Windows":
		return ""
	var output: Array = []
	var command := "(Get-AppxPackage -Name '%s' -ErrorAction SilentlyContinue | Select-Object -First 1).InstallLocation" % package_name
	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-Command", command]),
		output,
		true,
		false
	)
	if exit_code != 0:
		return ""
	for value: Variant in output:
		var install_location := String(value).strip_edges()
		if install_location.is_empty():
			continue
		var candidates := [
			install_location.path_join(executable_name),
			install_location.path_join("app").path_join(executable_name),
		]
		for candidate: String in candidates:
			if FileAccess.file_exists(candidate):
				return candidate.simplify_path()
	return ""


func _run_codex_configuration_tool() -> bool:
	var installer_path := _tool_path("install_codex_integration.ps1")
	if not FileAccess.file_exists(installer_path):
		return false
	var output: Array = []
	var exit_code := OS.execute("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-WindowStyle",
		"Hidden",
		"-File",
		installer_path,
	], output, true, false)
	return exit_code == 0


func _run_copilot_configuration_tool() -> bool:
	var installer_path := _tool_path("install_copilot_integration.ps1")
	if not FileAccess.file_exists(installer_path):
		return false
	var output: Array = []
	var exit_code := OS.execute("powershell.exe", [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-WindowStyle",
		"Hidden",
		"-File",
		installer_path,
	], output, true, false)
	return exit_code == 0


func _tool_path(file_name: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://tools".path_join(file_name))
	return OS.get_executable_path().get_base_dir().path_join("tools").path_join(file_name)
