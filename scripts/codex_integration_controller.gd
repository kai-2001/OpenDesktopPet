class_name CodexIntegrationController
extends RefCounted

const CodexNotificationReceiverScript = preload("res://scripts/codex_notification_receiver.gd")
const AgentNotificationRouterScript = preload("res://scripts/agent_notification_router.gd")
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
const OPENCODE_ENABLED_FILE_NAME := "open_desktop_pet_opencode_enabled.txt"
const OPENCODE_VSCODE_ENABLED_FILE_NAME := "open_desktop_pet_opencode_vscode_enabled.txt"
const OPENCODE_APP_ENABLED_FILE_NAME := "open_desktop_pet_opencode_app_enabled.txt"
const OPENCODE_TERMINAL_ENABLED_FILE_NAME := "open_desktop_pet_opencode_terminal_enabled.txt"
const OPENCODE_APP_EXECUTABLE_PATH_FILE_NAME := "open_desktop_pet_opencode_app_executable_path.txt"
const LEGACY_ENABLED_FILE_NAME := "open_desktop_pet_notify_enabled.txt"
const CODEX_INSTALL_MARKER := "open_desktop_pet_codex_installed.txt"
const COPILOT_INSTALL_MARKER := "open_desktop_pet_copilot_installed.txt"
const OPENCODE_INSTALL_MARKER := "open_desktop_pet_opencode_installed.txt"
const CODEX_CONFIG_FILE_NAME := "config.toml"
const CODEX_NOTIFY_SCRIPT_FILE_NAME := "open_desktop_pet_notify.ps1"
const COPILOT_HOOK_CONFIG_FILE_NAME := "open-desktop-pet.json"
const COPILOT_NOTIFY_SCRIPT_FILE_NAME := "vscode_copilot_notify.ps1"
const OPENCODE_PLUGIN_FILE_NAME := "open-desktop-pet.js"
const OPENCODE_NOTIFY_SCRIPT_FILE_NAME := "opencode_notify.ps1"
const CODEX_URI := "vscode://command/chatgpt.openSidebar"
const TARGET_VSCODE := AgentNotificationRouterScript.TARGET_VSCODE
const TARGET_CODEX_APP := AgentNotificationRouterScript.TARGET_CODEX_APP
const TARGET_TERMINAL := AgentNotificationRouterScript.TARGET_TERMINAL
const TARGET_OPENCODE_APP := AgentNotificationRouterScript.TARGET_OPENCODE_APP

signal notification_received(message: String, reaction_action: String, target_app: String)
signal state_changed
signal configuration_failed(target_name: String)
signal executable_path_detection_started(targets: Array)
signal executable_path_detection_finished(targets: Array)

# `enabled` and `executable_path` remain compatibility aliases for older saves.
var enabled := false
var codex_enabled := false
var codex_app_enabled := false
var terminal_codex_enabled := false
var terminal_opencode_enabled := false
var vscode_opencode_enabled := false
var opencode_app_enabled := false
var copilot_enabled := false
var port := DEFAULT_PORT
var executable_path := ""
var codex_app_executable_path := ""
var terminal_executable_path := ""
var opencode_app_executable_path := ""
var _receiver
var _last_event_id := ""
var _active_target_app := TARGET_VSCODE
var _window_activator
var _executable_path_detection_thread: Thread
var _active_executable_path_detection_targets: Array[String] = []
var _pending_executable_path_detection_targets: Array[String] = []


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
		terminal_opencode_enabled = bool(
			config.get_value("opencode_terminal", "enabled", false)
		)
		vscode_opencode_enabled = bool(
			config.get_value("opencode_vscode", "enabled", false)
		)
		opencode_app_enabled = bool(
			config.get_value("opencode_app", "enabled", false)
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
		opencode_app_executable_path = _normalize_executable_path(String(
			config.get_value("opencode_app", "executable_path", "")
		))
	# Older builds stored the internal Codex.exe path for the desktop app.
	# The visible ChatGPT/Codex desktop window is ChatGPT.exe, so migrate it
	# when both executables are in the same Windows App package.
	codex_app_executable_path = _migrate_codex_app_executable_path(
		codex_app_executable_path
	)
	enabled = codex_enabled
	_save_settings()
	_ensure_enabled_configurations()
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


func set_terminal_opencode_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_opencode_configuration():
		terminal_opencode_enabled = false
		_persist_agent_state()
		return
	terminal_opencode_enabled = value
	_persist_agent_state()


func set_vscode_opencode_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_opencode_configuration():
		vscode_opencode_enabled = false
		_persist_agent_state()
		return
	vscode_opencode_enabled = value
	_persist_agent_state()


func set_opencode_app_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_opencode_configuration():
		opencode_app_enabled = false
		_persist_agent_state()
		return
	opencode_app_enabled = value
	_persist_agent_state()


func set_codex_app_executable_path(value: String) -> void:
	codex_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func set_terminal_executable_path(value: String) -> void:
	terminal_executable_path = _normalize_executable_path(value)
	_save_settings()
	state_changed.emit()


func set_opencode_app_executable_path(value: String) -> void:
	opencode_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	_write_bridge_files()
	state_changed.emit()


func refresh_enabled_executable_paths_if_invalid() -> void:
	var targets: Array[String] = []
	if codex_enabled or copilot_enabled:
		targets.append(TARGET_VSCODE)
	if codex_app_enabled:
		targets.append(TARGET_CODEX_APP)
	if terminal_codex_enabled or terminal_opencode_enabled:
		targets.append(TARGET_TERMINAL)
	if vscode_opencode_enabled:
		targets.append(TARGET_VSCODE)
	if opencode_app_enabled:
		targets.append(TARGET_OPENCODE_APP)
	refresh_executable_paths_if_invalid(targets)


func refresh_executable_paths_if_invalid(targets: Array[String]) -> void:
	var invalid_targets := _invalid_executable_path_targets(targets)
	if invalid_targets.is_empty():
		return
	if _executable_path_detection_thread != null:
		for target: String in invalid_targets:
			if not _pending_executable_path_detection_targets.has(target):
				_pending_executable_path_detection_targets.append(target)
		return
	_start_executable_path_detection(invalid_targets)


func _invalid_executable_path_targets(targets: Array[String]) -> Array[String]:
	var invalid_targets: Array[String] = []
	for target: String in targets:
		if not invalid_targets.has(target) \
				and not _has_valid_executable_path(_executable_path_for_target(target)):
			invalid_targets.append(target)
	return invalid_targets


func _start_executable_path_detection(targets: Array[String]) -> void:
	var path_snapshot := {}
	for target: String in targets:
		path_snapshot[target] = _executable_path_for_target(target)
	_active_executable_path_detection_targets = targets.duplicate()
	_executable_path_detection_thread = Thread.new()
	var start_error := _executable_path_detection_thread.start(
		Callable(self, "_detect_invalid_executable_paths").bind(path_snapshot)
	)
	if start_error != OK:
		_executable_path_detection_thread = null
		_active_executable_path_detection_targets.clear()
		return
	executable_path_detection_started.emit(
		_active_executable_path_detection_targets.duplicate()
	)


func _detect_invalid_executable_paths(path_snapshot: Dictionary) -> Dictionary:
	var detected_paths := {}
	for target: String in path_snapshot.keys():
		if target == TARGET_VSCODE:
			detected_paths[target] = detect_vscode_executable()
		elif target == TARGET_CODEX_APP:
			detected_paths[target] = detect_codex_app_executable()
		elif target == TARGET_TERMINAL:
			detected_paths[target] = detect_terminal_executable()
		elif target == TARGET_OPENCODE_APP:
			detected_paths[target] = detect_opencode_app_executable()
	return detected_paths


func _poll_executable_path_detection() -> void:
	if _executable_path_detection_thread == null \
			or _executable_path_detection_thread.is_alive():
		return
	var detected_paths: Dictionary = _executable_path_detection_thread.wait_to_finish()
	_executable_path_detection_thread = null
	var finished_targets := _active_executable_path_detection_targets.duplicate()
	_active_executable_path_detection_targets.clear()
	_apply_detected_executable_paths(detected_paths, finished_targets)
	executable_path_detection_finished.emit(finished_targets)
	if not _pending_executable_path_detection_targets.is_empty():
		var next_targets := _pending_executable_path_detection_targets.duplicate()
		_pending_executable_path_detection_targets.clear()
		_start_executable_path_detection(next_targets)


func _apply_detected_executable_paths(
	detected_paths: Dictionary, targets: Array[String]
) -> void:
	var changed := false
	for target: String in targets:
		var current_path := _executable_path_for_target(target)
		if _has_valid_executable_path(current_path):
			continue
		var detected_path := _normalize_executable_path(
			String(detected_paths.get(target, ""))
		)
		if _has_valid_executable_path(detected_path):
			_set_executable_path_for_target(target, detected_path)
			changed = true
	if changed:
		_save_settings()
		state_changed.emit()


func _stop_executable_path_detection() -> void:
	if _executable_path_detection_thread == null:
		return
	_executable_path_detection_thread.wait_to_finish()
	_executable_path_detection_thread = null
	_active_executable_path_detection_targets.clear()
	_pending_executable_path_detection_targets.clear()


func is_any_enabled() -> bool:
	return codex_enabled or codex_app_enabled or terminal_codex_enabled \
		or terminal_opencode_enabled or vscode_opencode_enabled \
		or opencode_app_enabled or copilot_enabled


func is_running() -> bool:
	return _receiver != null and _receiver.is_running()


func is_codex_configured() -> bool:
	var codex_home := _codex_home_path()
	if codex_home.is_empty():
		return false
	if not FileAccess.file_exists(codex_home.path_join(CODEX_INSTALL_MARKER)):
		return false
	if not FileAccess.file_exists(codex_home.path_join(CODEX_NOTIFY_SCRIPT_FILE_NAME)):
		return false
	var config_text := _read_text_file(codex_home.path_join(CODEX_CONFIG_FILE_NAME))
	return config_text.contains("notify") and config_text.contains(
		CODEX_NOTIFY_SCRIPT_FILE_NAME
	)


func is_copilot_configured() -> bool:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return false
	if not FileAccess.file_exists(integration_home.path_join(COPILOT_INSTALL_MARKER)):
		return false
	if not FileAccess.file_exists(
		integration_home.path_join(COPILOT_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var hook_config := _user_profile_path().path_join(
		".copilot/hooks/%s" % COPILOT_HOOK_CONFIG_FILE_NAME
	)
	var hook_text := _read_text_file(hook_config)
	return hook_text.contains(COPILOT_NOTIFY_SCRIPT_FILE_NAME) and hook_text.contains(
		"Stop"
	)


func is_opencode_configured() -> bool:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return false
	if not FileAccess.file_exists(integration_home.path_join(OPENCODE_INSTALL_MARKER)):
		return false
	if not FileAccess.file_exists(
		integration_home.path_join(OPENCODE_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var plugin_path := _user_profile_path().path_join(
		".config/opencode/plugins/%s" % OPENCODE_PLUGIN_FILE_NAME
	)
	var plugin_text := _read_text_file(plugin_path)
	return plugin_text.contains("OpenDesktopPet OpenCode notification plugin") \
		and plugin_text.contains(OPENCODE_NOTIFY_SCRIPT_FILE_NAME) \
		and plugin_text.contains("session.idle")


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


func _ensure_opencode_configuration() -> bool:
	if is_opencode_configured():
		return true
	if _run_opencode_configuration_tool() and is_opencode_configured():
		return true
	configuration_failed.emit("終端機 OpenCode")
	return false


func _persist_agent_state() -> void:
	_save_settings()
	_write_bridge_files()
	if is_any_enabled():
		_start_receiver()
	else:
		_stop_receiver()
	state_changed.emit()


func _ensure_enabled_configurations() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var changed := false
	if codex_enabled or codex_app_enabled or terminal_codex_enabled:
		if not _ensure_codex_configuration("Codex"):
			codex_enabled = false
			codex_app_enabled = false
			terminal_codex_enabled = false
			enabled = false
			changed = true
	if copilot_enabled and not _ensure_copilot_configuration():
		copilot_enabled = false
		changed = true
	if terminal_opencode_enabled or vscode_opencode_enabled or opencode_app_enabled:
		if not _ensure_opencode_configuration():
			terminal_opencode_enabled = false
			vscode_opencode_enabled = false
			opencode_app_enabled = false
			changed = true
	if changed:
		_save_settings()


func focus_vscode_interface() -> bool:
	return _focus_target(TARGET_VSCODE)


func focus_codex_interface() -> bool:
	return _focus_target(_active_target_app)


func focus_current_target() -> bool:
	return _focus_target(_active_target_app)


func focus_target(target_app: String) -> bool:
	var normalized_target := AgentNotificationRouterScript.normalize_target_app(
		target_app.to_lower()
	)
	_active_target_app = normalized_target
	return _focus_target(normalized_target)


func has_native_window_focus_support() -> bool:
	return _window_activator != null


func is_vscode_interface_foreground() -> bool:
	return _is_target_foreground(TARGET_VSCODE)


func is_codex_interface_foreground() -> bool:
	return is_current_target_foreground()


func is_current_target_foreground() -> bool:
	return _is_target_foreground(_active_target_app)


func is_target_foreground(target_app: String) -> bool:
	return _is_target_foreground(
		AgentNotificationRouterScript.normalize_target_app(target_app.to_lower())
	)


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


func detect_opencode_app_executable() -> String:
	var candidates: Array[String] = []
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	var app_data := OS.get_environment("APPDATA")
	var program_files := OS.get_environment("ProgramFiles")
	var program_files_x86 := OS.get_environment("ProgramFiles(x86)")
	for base_path: String in [local_app_data, app_data, program_files, program_files_x86]:
		if base_path.is_empty():
			continue
		# The CLI is normally installed as `opencode.exe`. Only search that
		# filename inside an explicitly Desktop-named directory; a generic
		# OpenCode directory may belong to the CLI and must not become the
		# Desktop focus target by accident.
		candidates.append(base_path.path_join("OpenCode/OpenCode.exe"))
		candidates.append(base_path.path_join("OpenCode Desktop/OpenCode Desktop.exe"))
		candidates.append(base_path.path_join("OpenCode Desktop/OpenCode.exe"))
		candidates.append(base_path.path_join("OpenCode Desktop/opencode.exe"))
		candidates.append(base_path.path_join("opencode-desktop/OpenCode.exe"))
		candidates.append(base_path.path_join("opencode-desktop/opencode.exe"))
		candidates.append(base_path.path_join("Programs/OpenCode/OpenCode.exe"))
		candidates.append(base_path.path_join("Programs/OpenCode Desktop/OpenCode.exe"))
		candidates.append(base_path.path_join("Programs/OpenCode Desktop/opencode.exe"))
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	var registry_detected := _detect_opencode_app_from_uninstall_registry()
	if not registry_detected.is_empty():
		return registry_detected
	return ""


func _detect_opencode_app_from_uninstall_registry() -> String:
	if OS.get_name() != "Windows":
		return ""
	var output: Array = []
	var command := "Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue | Where-Object { [string]$_.DisplayName -match '(?i)OpenCode' } | ForEach-Object { [string]$_.DisplayIcon; if ([string]$_.InstallLocation) { Join-Path ([string]$_.InstallLocation) 'OpenCode.exe'; Join-Path ([string]$_.InstallLocation) 'OpenCode Desktop.exe' } }"
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
		var candidate := String(value).strip_edges().trim_prefix('"').trim_suffix('"')
		if candidate.contains(','):
			candidate = candidate.split(",", false)[0].strip_edges().trim_prefix('"').trim_suffix('"')
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
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
	var source := String(notification.get("source", "")).to_lower()
	var agent := String(notification.get("agent", "")).to_lower()
	if agent.is_empty():
		agent = AgentNotificationRouterScript.normalize_agent(source)
	if source.is_empty():
		source = agent
	var target_app := AgentNotificationRouterScript.normalize_target_app(
		String(
			notification.get(
				"target_app", notification.get("target_platform", TARGET_VSCODE)
			)
		).to_lower()
	)
	var enabled_by_key := {
		"codex_vscode": codex_enabled,
		"codex_app": codex_app_enabled,
		"codex_terminal": terminal_codex_enabled,
		"copilot": copilot_enabled,
		"opencode_terminal": terminal_opencode_enabled,
		"opencode_vscode": vscode_opencode_enabled,
		"opencode_app": opencode_app_enabled,
	}
	if not AgentNotificationRouterScript.is_notification_enabled(
			source, agent, target_app, enabled_by_key
	):
		return
	_active_target_app = target_app
	var thread_id := String(notification.get("thread_id", notification.get("thread-id", "")))
	var turn_id := String(notification.get("turn_id", notification.get("turn-id", "")))
	var session_id := String(notification.get("session_id", notification.get("session-id", "")))
	var event_id := String(notification.get("event_id", ""))
	if event_id.is_empty():
		var identity := thread_id if not thread_id.is_empty() else session_id
		event_id = "%s:%s:%s:%s" % [source, target_app, identity, turn_id]
	if not event_id.ends_with(":") and event_id == _last_event_id:
		return
	if not event_id.ends_with(":"):
		_last_event_id = event_id

	var display_name := AgentNotificationRouterScript.display_name(source, agent)
	var target_name := AgentNotificationRouterScript.target_display_name(target_app)
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
	config.set_value("opencode_terminal", "enabled", terminal_opencode_enabled)
	config.set_value("opencode_vscode", "enabled", vscode_opencode_enabled)
	config.set_value("opencode_app", "enabled", opencode_app_enabled)
	config.set_value("opencode_app", "executable_path", opencode_app_executable_path)
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


func _read_text_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _user_profile_path() -> String:
	return OS.get_environment("USERPROFILE").strip_edges()


func _codex_home_path() -> String:
	var configured_home := OS.get_environment("CODEX_HOME").strip_edges()
	if not configured_home.is_empty():
		return configured_home
	var user_profile := _user_profile_path()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".codex")


func _integration_home_path() -> String:
	var user_profile := _user_profile_path()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".open-desktop-pet")


func _write_bridge_files(disable_all := false) -> void:
	var integration_home := _integration_home_path()
	if not integration_home.is_empty():
		_write_agent_bridge_files(integration_home, disable_all, false)

	# Keep legacy Codex-home bridge files in sync for existing installations.
	var codex_home := _codex_home_path()
	if codex_home.is_empty():
		return
	_write_agent_bridge_files(codex_home, disable_all, true)


func _write_agent_bridge_files(
	directory: String, disable_all: bool, write_legacy_codex_flag: bool
) -> void:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return
	_write_port_file(directory)
	if write_legacy_codex_flag:
		_write_flag(
			directory.path_join(LEGACY_ENABLED_FILE_NAME),
			(codex_enabled or codex_app_enabled or terminal_codex_enabled) and not disable_all
		)
	_write_flag(
		directory.path_join(CODEX_ENABLED_FILE_NAME),
		(codex_enabled or codex_app_enabled or terminal_codex_enabled) and not disable_all
	)
	_write_flag(
		directory.path_join(COPILOT_ENABLED_FILE_NAME),
		copilot_enabled and not disable_all
	)
	_write_flag(
		directory.path_join(OPENCODE_VSCODE_ENABLED_FILE_NAME),
		vscode_opencode_enabled and not disable_all
	)
	_write_flag(
		directory.path_join(OPENCODE_APP_ENABLED_FILE_NAME),
		opencode_app_enabled and not disable_all
	)
	_write_flag(
		directory.path_join(OPENCODE_TERMINAL_ENABLED_FILE_NAME),
		terminal_opencode_enabled and not disable_all
	)
	_write_text_file(
		directory.path_join(OPENCODE_APP_EXECUTABLE_PATH_FILE_NAME),
		opencode_app_executable_path
	)
	_write_codex_target_flags(directory, disable_all)


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
	_write_flag(
		directory.path_join(OPENCODE_ENABLED_FILE_NAME),
		terminal_opencode_enabled and not disable_all
	)


func _write_flag(path: String, enabled_value: bool) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("1" if enabled_value else "0")
		file.close()


func _write_text_file(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
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
	return _executable_path_for_target(target_app)


func _executable_path_for_target(target_app: String) -> String:
	match target_app:
		TARGET_CODEX_APP:
			return codex_app_executable_path
		TARGET_OPENCODE_APP:
			return opencode_app_executable_path
		TARGET_TERMINAL:
			return terminal_executable_path
		_:
			return executable_path


func _set_executable_path_for_target(target_app: String, path: String) -> void:
	match target_app:
		TARGET_CODEX_APP:
			codex_app_executable_path = path
		TARGET_OPENCODE_APP:
			opencode_app_executable_path = path
		TARGET_TERMINAL:
			terminal_executable_path = path
		_:
			executable_path = path


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


func _run_opencode_configuration_tool() -> bool:
	var installer_path := _tool_path("install_opencode_integration.ps1")
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
