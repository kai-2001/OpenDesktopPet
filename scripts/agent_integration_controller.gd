class_name AgentIntegrationController
extends RefCounted

const LocalAgentNotificationReceiverScript = preload("res://scripts/local_agent_notification_receiver.gd")
const AgentNotificationRouterScript = preload("res://scripts/agent_notification_router.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_PORT := 38571
const MIN_PORT := 1024
const MAX_PORT := 65535
const RUNTIME_FILE_NAME := "open_desktop_pet_runtime.json"
const RUNTIME_HELPER_FILE_NAME := "open_desktop_pet_runtime.ps1"
const RUNTIME_SCHEMA_VERSION := 1
const RUNTIME_BRIDGE_MARKER := "OpenDesktopPet runtime schema v1"
const CODEX_INSTALL_MARKER := "open_desktop_pet_codex_installed.txt"
const COPILOT_INSTALL_MARKER := "open_desktop_pet_copilot_installed.txt"
const OPENCODE_INSTALL_MARKER := "open_desktop_pet_opencode_installed.txt"
const CLAUDE_CODE_INSTALL_MARKER := "open_desktop_pet_claude_code_installed.txt"
const GEMINI_CLI_INSTALL_MARKER := "open_desktop_pet_gemini_cli_installed.txt"
const AGY_INSTALL_MARKER := "open_desktop_pet_antigravity_cli_installed.txt"
const CODEX_CONFIG_FILE_NAME := "config.toml"
const CODEX_NOTIFY_SCRIPT_FILE_NAME := "open_desktop_pet_notify.ps1"
const COPILOT_HOOK_CONFIG_FILE_NAME := "open-desktop-pet.json"
const COPILOT_NOTIFY_SCRIPT_FILE_NAME := "vscode_copilot_notify.ps1"
const OPENCODE_PLUGIN_FILE_NAME := "open-desktop-pet.js"
const OPENCODE_NOTIFY_SCRIPT_FILE_NAME := "opencode_notify.ps1"
const CLAUDE_CODE_NOTIFY_SCRIPT_FILE_NAME := "claude_code_notify.ps1"
const CLAUDE_CODE_SETTINGS_FILE_NAME := "settings.json"
const GEMINI_CLI_NOTIFY_SCRIPT_FILE_NAME := "gemini_cli_notify.ps1"
const GEMINI_CLI_SETTINGS_FILE_NAME := "settings.json"
const AGY_NOTIFY_SCRIPT_FILE_NAME := "antigravity_cli_notify.ps1"
const AGY_HOOKS_FILE_NAME := "hooks.json"
const AGY_HOOK_NAME := "open-desktop-pet"
const CODEX_URI := "vscode://command/chatgpt.openSidebar"
const CLAUDE_CODE_VSCODE_URI := "vscode://anthropic.claude-code/open"
const TARGET_VSCODE := AgentNotificationRouterScript.TARGET_VSCODE
const TARGET_CODEX_APP := AgentNotificationRouterScript.TARGET_CODEX_APP
const TARGET_TERMINAL := AgentNotificationRouterScript.TARGET_TERMINAL
const TARGET_OPENCODE_APP := AgentNotificationRouterScript.TARGET_OPENCODE_APP
const TARGET_CLAUDE_APP := AgentNotificationRouterScript.TARGET_CLAUDE_APP

signal notification_received(
	message: String, reaction_action: String, target_app: String, agent: String
)
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
var claude_vscode_enabled := false
var claude_app_enabled := false
var claude_terminal_enabled := false
var gemini_terminal_enabled := false
var agy_terminal_enabled := false
var port := DEFAULT_PORT
var executable_path := ""
var codex_app_executable_path := ""
var terminal_executable_path := ""
var opencode_app_executable_path := ""
var claude_app_executable_path := ""
var _receiver
var _last_event_id := ""
var _active_target_app := TARGET_VSCODE
var _active_agent := "codex"
var _window_activator
var _runtime_instance_id := ""
var _executable_path_detection_thread: Thread
var _active_executable_path_detection_targets: Array[String] = []
var _pending_executable_path_detection_targets: Array[String] = []


func _init() -> void:
	_runtime_instance_id = "%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
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
		claude_vscode_enabled = bool(
			config.get_value("claude_code_vscode", "enabled", false)
		)
		claude_app_enabled = bool(
			config.get_value("claude_code_app", "enabled", false)
		)
		claude_terminal_enabled = bool(
			config.get_value("claude_code_terminal", "enabled", false)
		)
		gemini_terminal_enabled = bool(
			config.get_value("gemini_terminal", "enabled", false)
		)
		agy_terminal_enabled = bool(
			config.get_value("agy_terminal", "enabled", false)
		)
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
		claude_app_executable_path = _normalize_executable_path(String(
			config.get_value("claude_code_app", "executable_path", "")
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
	_refresh_runtime_registration()


func poll() -> void:
	_poll_executable_path_detection()
	if _receiver != null:
		_receiver.poll()


func shutdown() -> void:
	_stop_executable_path_detection()
	_stop_receiver()
	_remove_runtime_if_owned()


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


func set_claude_vscode_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_claude_code_configuration("Claude Code"):
		claude_vscode_enabled = false
		_persist_agent_state()
		return
	claude_vscode_enabled = value
	_persist_agent_state()


func set_claude_app_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_claude_code_configuration("Claude Desktop"):
		claude_app_enabled = false
		_persist_agent_state()
		return
	claude_app_enabled = value
	_persist_agent_state()


func set_claude_terminal_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_claude_code_configuration("Claude 終端機"):
		claude_terminal_enabled = false
		_persist_agent_state()
		return
	claude_terminal_enabled = value
	_persist_agent_state()


func set_gemini_terminal_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_gemini_cli_configuration():
		gemini_terminal_enabled = false
		_persist_agent_state()
		return
	gemini_terminal_enabled = value
	_persist_agent_state()


func set_agy_terminal_enabled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless" \
			and not _ensure_antigravity_cli_configuration():
		agy_terminal_enabled = false
		_persist_agent_state()
		return
	agy_terminal_enabled = value
	_persist_agent_state()


func set_codex_app_executable_path(value: String) -> void:
	codex_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	_publish_runtime_if_running()
	state_changed.emit()


func set_terminal_executable_path(value: String) -> void:
	terminal_executable_path = _normalize_executable_path(value)
	_save_settings()
	_publish_runtime_if_running()
	state_changed.emit()


func set_opencode_app_executable_path(value: String) -> void:
	opencode_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	_publish_runtime_if_running()
	state_changed.emit()


func set_claude_app_executable_path(value: String) -> void:
	claude_app_executable_path = _normalize_executable_path(value)
	_save_settings()
	_publish_runtime_if_running()
	state_changed.emit()


func refresh_enabled_executable_paths_if_invalid() -> void:
	var targets: Array[String] = []
	if codex_enabled or copilot_enabled:
		targets.append(TARGET_VSCODE)
	if codex_app_enabled:
		targets.append(TARGET_CODEX_APP)
	if terminal_codex_enabled or terminal_opencode_enabled \
			or gemini_terminal_enabled or agy_terminal_enabled:
		targets.append(TARGET_TERMINAL)
	if vscode_opencode_enabled:
		targets.append(TARGET_VSCODE)
	if opencode_app_enabled:
		targets.append(TARGET_OPENCODE_APP)
	if claude_vscode_enabled:
		targets.append(TARGET_VSCODE)
	if claude_app_enabled:
		targets.append(TARGET_CLAUDE_APP)
	if claude_terminal_enabled:
		targets.append(TARGET_TERMINAL)
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
		elif target == TARGET_CLAUDE_APP:
			detected_paths[target] = detect_claude_app_executable()
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
		or opencode_app_enabled or copilot_enabled \
		or claude_vscode_enabled or claude_app_enabled or claude_terminal_enabled \
		or gemini_terminal_enabled or agy_terminal_enabled


func is_running() -> bool:
	return _receiver != null and _receiver.is_running()


func is_codex_configured() -> bool:
	var codex_home := _codex_home_path()
	var integration_home := _integration_home_path()
	if codex_home.is_empty() or integration_home.is_empty():
		return false
	if not FileAccess.file_exists(codex_home.path_join(CODEX_INSTALL_MARKER)):
		return false
	if not _has_runtime_bridge_support(
		integration_home, codex_home.path_join(CODEX_NOTIFY_SCRIPT_FILE_NAME)
	):
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
	if not _has_runtime_bridge_support(
		integration_home, integration_home.path_join(COPILOT_NOTIFY_SCRIPT_FILE_NAME)
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
	if not _has_runtime_bridge_support(
		integration_home, integration_home.path_join(OPENCODE_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var plugin_path := _user_profile_path().path_join(
		".config/opencode/plugins/%s" % OPENCODE_PLUGIN_FILE_NAME
	)
	var plugin_text := _read_text_file(plugin_path)
	return plugin_text.contains("OpenDesktopPet OpenCode notification plugin") \
		and plugin_text.contains(OPENCODE_NOTIFY_SCRIPT_FILE_NAME) \
		and plugin_text.contains("session.idle")


func is_claude_code_configured() -> bool:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return false
	if not FileAccess.file_exists(integration_home.path_join(CLAUDE_CODE_INSTALL_MARKER)):
		return false
	if not _has_runtime_bridge_support(
		integration_home, integration_home.path_join(CLAUDE_CODE_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var settings_text := _read_text_file(
		_claude_home_path().path_join(CLAUDE_CODE_SETTINGS_FILE_NAME)
	)
	return settings_text.contains(CLAUDE_CODE_NOTIFY_SCRIPT_FILE_NAME) \
		and settings_text.contains('"Stop"')


func is_gemini_cli_configured() -> bool:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return false
	if not FileAccess.file_exists(integration_home.path_join(GEMINI_CLI_INSTALL_MARKER)):
		return false
	if not _has_runtime_bridge_support(
		integration_home, integration_home.path_join(GEMINI_CLI_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var settings_text := _read_text_file(
		_gemini_home_path().path_join(GEMINI_CLI_SETTINGS_FILE_NAME)
	)
	return settings_text.contains(GEMINI_CLI_NOTIFY_SCRIPT_FILE_NAME) \
		and settings_text.contains('"AfterAgent"') \
		and settings_text.contains('"Notification"')


func is_antigravity_cli_configured() -> bool:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return false
	if not FileAccess.file_exists(integration_home.path_join(AGY_INSTALL_MARKER)):
		return false
	if not _has_runtime_bridge_support(
		integration_home, integration_home.path_join(AGY_NOTIFY_SCRIPT_FILE_NAME)
	):
		return false
	var hooks_text := _read_text_file(
		_gemini_home_path().path_join("config").path_join(AGY_HOOKS_FILE_NAME)
	)
	var parsed_hooks: Variant = JSON.parse_string(hooks_text)
	if not parsed_hooks is Dictionary:
		return false
	var hook_definition: Variant = parsed_hooks.get(AGY_HOOK_NAME, {})
	if not hook_definition is Dictionary:
		return false
	var stop_handlers: Variant = hook_definition.get("Stop", [])
	if not stop_handlers is Array:
		return false
	var expected_command := _expected_antigravity_cli_hook_command()
	for handler in stop_handlers:
		if handler is Dictionary and String(handler.get("command", "")) == expected_command:
			return true
	return false


func _expected_antigravity_cli_hook_command() -> String:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return ""
	var bridge_path := integration_home.path_join(AGY_NOTIFY_SCRIPT_FILE_NAME).replace("/", "\\")
	var bridge_invocation := "& '%s'" % bridge_path.replace("'", "''")
	var encoded_invocation := Marshalls.raw_to_base64(bridge_invocation.to_utf16_buffer())
	return "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand %s" % encoded_invocation


func _has_runtime_bridge_support(integration_home: String, bridge_path: String) -> bool:
	var helper_text := _read_text_file(integration_home.path_join(RUNTIME_HELPER_FILE_NAME))
	var bridge_text := _read_text_file(bridge_path)
	return helper_text.contains(RUNTIME_BRIDGE_MARKER) and bridge_text.contains(
		RUNTIME_BRIDGE_MARKER
	)


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


func _ensure_claude_code_configuration(target_name: String) -> bool:
	if is_claude_code_configured():
		return true
	if _run_claude_code_configuration_tool() and is_claude_code_configured():
		return true
	configuration_failed.emit(target_name)
	return false


func _ensure_gemini_cli_configuration() -> bool:
	if is_gemini_cli_configured():
		return true
	if _run_gemini_cli_configuration_tool() and is_gemini_cli_configured():
		return true
	configuration_failed.emit("Gemini CLI 終端機")
	return false


func _ensure_antigravity_cli_configuration() -> bool:
	if is_antigravity_cli_configured():
		return true
	if _run_antigravity_cli_configuration_tool() and is_antigravity_cli_configured():
		return true
	configuration_failed.emit("Antigravity CLI 終端機")
	return false


func _persist_agent_state() -> void:
	_save_settings()
	_refresh_runtime_registration()
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
	if claude_vscode_enabled or claude_app_enabled or claude_terminal_enabled:
		if not _ensure_claude_code_configuration("Claude Code"):
			claude_vscode_enabled = false
			claude_app_enabled = false
			claude_terminal_enabled = false
			changed = true
	if gemini_terminal_enabled and not _ensure_gemini_cli_configuration():
		gemini_terminal_enabled = false
		changed = true
	if agy_terminal_enabled and not _ensure_antigravity_cli_configuration():
		agy_terminal_enabled = false
		changed = true
	if changed:
		_save_settings()


func focus_vscode_interface() -> bool:
	return _focus_target(TARGET_VSCODE)


func focus_codex_interface() -> bool:
	return _focus_target(_active_target_app, _active_agent)


func focus_current_target() -> bool:
	return _focus_target(_active_target_app, _active_agent)


func focus_target(target_app: String, agent := "") -> bool:
	var normalized_target := AgentNotificationRouterScript.normalize_target_app(
		target_app.to_lower()
	)
	_active_target_app = normalized_target
	if not String(agent).is_empty():
		_active_agent = AgentNotificationRouterScript.normalize_agent(agent)
	return _focus_target(normalized_target, _active_agent)


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


func detect_claude_app_executable() -> String:
	var candidates: Array[String] = []
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	var app_data := OS.get_environment("APPDATA")
	var program_files := OS.get_environment("ProgramFiles")
	var program_files_x86 := OS.get_environment("ProgramFiles(x86)")
	for base_path: String in [local_app_data, app_data, program_files, program_files_x86]:
		if base_path.is_empty():
			continue
		candidates.append(base_path.path_join("Claude/Claude.exe"))
		candidates.append(base_path.path_join("Anthropic/Claude/Claude.exe"))
		candidates.append(base_path.path_join("Programs/Claude/Claude.exe"))
	for path_entry: String in OS.get_environment("PATH").split(";", false):
		var directory := path_entry.strip_edges().trim_prefix('"').trim_suffix('"')
		if not directory.is_empty():
			candidates.append(directory.path_join("Claude.exe"))
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate.simplify_path()
	var appx_detected := _detect_claude_app_from_appx()
	if not appx_detected.is_empty():
		return appx_detected
	return ""


func _detect_claude_app_from_appx() -> String:
	if OS.get_name() != "Windows":
		return ""
	var output: Array = []
	var command := "Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue | ForEach-Object { if ([string]$_.InstallLocation) { Join-Path ([string]$_.InstallLocation) 'app\\Claude.exe'; Join-Path ([string]$_.InstallLocation) 'Claude.exe' } }"
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
		for line: String in String(value).split("\n", false):
			var candidate := line.strip_edges().trim_prefix('"').trim_suffix('"')
			if FileAccess.file_exists(candidate):
				return candidate.simplify_path()
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
		"claude_terminal": claude_terminal_enabled,
		"claude_vscode": claude_vscode_enabled,
		"claude_app": claude_app_enabled,
		"gemini_terminal": gemini_terminal_enabled,
		"agy_terminal": agy_terminal_enabled,
	}
	if not AgentNotificationRouterScript.is_notification_enabled(
			source, agent, target_app, enabled_by_key
	):
		return
	_active_target_app = target_app
	_active_agent = agent
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
				"pet", target_app, agent
			)
		"codex_waiting", "waiting", "approval-requested":
			notification_received.emit(
				"%s 正在等待你回到 %s 處理下一步。" % [display_name, target_name],
				"idle", target_app, agent
			)
		"agent-error", "codex_error", "failed", "error":
			notification_received.emit(
				"%s 發生錯誤，請回到 %s 查看。" % [display_name, target_name],
				"idle", target_app, agent
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
	config.set_value("claude_code_vscode", "enabled", claude_vscode_enabled)
	config.set_value("claude_code_app", "enabled", claude_app_enabled)
	config.set_value("claude_code_app", "executable_path", claude_app_executable_path)
	config.set_value("claude_code_terminal", "enabled", claude_terminal_enabled)
	config.set_value("gemini_terminal", "enabled", gemini_terminal_enabled)
	config.set_value("agy_terminal", "enabled", agy_terminal_enabled)
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


func _claude_home_path() -> String:
	var user_profile := _user_profile_path()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".claude")


func _gemini_home_path() -> String:
	var user_profile := _user_profile_path()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".gemini")


func _integration_home_path() -> String:
	var user_profile := _user_profile_path()
	if user_profile.is_empty():
		return ""
	return user_profile.path_join(".open-desktop-pet")


func _refresh_runtime_registration() -> void:
	# Headless validation must never mutate the real user's notification state.
	if DisplayServer.get_name() == "headless":
		if is_any_enabled():
			_start_receiver()
		else:
			_stop_receiver()
		return
	if not is_any_enabled():
		_stop_receiver()
		_remove_runtime_if_owned()
		return
	if _start_receiver():
		_write_runtime_state()


func _start_receiver() -> bool:
	if not is_any_enabled():
		return false
	if is_running() and _receiver.get_port() == port:
		return true
	if DisplayServer.get_name() != "headless" and _has_live_runtime_owner():
		push_warning("另一個 Open Desktop Pet 實例正在管理 Agent 通知。")
		return false
	_stop_receiver()
	_receiver = LocalAgentNotificationReceiverScript.new()
	_receiver.notification_received.connect(_handle_notification)
	if not _receiver.start(port):
		push_warning("Agent 通知接收器無法監聽通訊埠 %d。" % port)
		_receiver = null
		return false
	return true


func _has_live_runtime_owner() -> bool:
	var runtime := _read_runtime_state()
	if runtime.is_empty() or String(runtime.get("instance_id", "")) == _runtime_instance_id:
		return false
	var runtime_pid := int(runtime.get("pid", 0))
	if runtime_pid <= 0 or OS.get_name() != "Windows":
		return false
	var output: Array = []
	var command := "if (Get-Process -Id %d -ErrorAction SilentlyContinue) { exit 0 }; exit 1" % runtime_pid
	return OS.execute(
		"powershell.exe", PackedStringArray(["-NoProfile", "-Command", command]), output, true, false
	) == 0


func _write_runtime_state() -> bool:
	if not is_running():
		return false
	var integration_home := _integration_home_path()
	if integration_home.is_empty() or DirAccess.make_dir_recursive_absolute(integration_home) != OK:
		return false
	var runtime_path := integration_home.path_join(RUNTIME_FILE_NAME)
	var temporary_path := "%s.%s.tmp" % [runtime_path, _runtime_instance_id]
	var payload := {
		"schema_version": RUNTIME_SCHEMA_VERSION,
		"instance_id": _runtime_instance_id,
		"pid": OS.get_process_id(),
		"port": port,
		"updated_unix_time": Time.get_unix_time_from_system(),
		"enabled_targets": {
			"codex_vscode": codex_enabled,
			"codex_app": codex_app_enabled,
			"codex_terminal": terminal_codex_enabled,
			"copilot": copilot_enabled,
			"opencode_terminal": terminal_opencode_enabled,
			"opencode_vscode": vscode_opencode_enabled,
			"opencode_app": opencode_app_enabled,
			"claude_terminal": claude_terminal_enabled,
			"claude_vscode": claude_vscode_enabled,
			"claude_app": claude_app_enabled,
			"gemini_terminal": gemini_terminal_enabled,
			"agy_terminal": agy_terminal_enabled,
		},
		"executable_paths": {
			"codex_app": codex_app_executable_path,
			"terminal": terminal_executable_path,
			"opencode_app": opencode_app_executable_path,
			"claude_app": claude_app_executable_path,
		},
	}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	if FileAccess.file_exists(runtime_path) and DirAccess.remove_absolute(runtime_path) != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	if DirAccess.rename_absolute(temporary_path, runtime_path) != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	_remove_legacy_bridge_state()
	return true


func _publish_runtime_if_running() -> void:
	if DisplayServer.get_name() != "headless" and is_running():
		_write_runtime_state()


func _remove_runtime_if_owned() -> void:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return
	var runtime := _read_runtime_state()
	if String(runtime.get("instance_id", "")) != _runtime_instance_id:
		return
	DirAccess.remove_absolute(integration_home.path_join(RUNTIME_FILE_NAME))
	_remove_legacy_bridge_state()


func _read_runtime_state() -> Dictionary:
	var integration_home := _integration_home_path()
	if integration_home.is_empty():
		return {}
	var runtime_path := integration_home.path_join(RUNTIME_FILE_NAME)
	if not FileAccess.file_exists(runtime_path):
		return {}
	var file := FileAccess.open(runtime_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _remove_legacy_bridge_state() -> void:
	var file_names := PackedStringArray([
		"open_desktop_pet_notify_port.txt",
		"open_desktop_pet_notify_enabled.txt",
		"open_desktop_pet_codex_enabled.txt",
		"open_desktop_pet_vscode_codex_enabled.txt",
		"open_desktop_pet_codex_app_enabled.txt",
		"open_desktop_pet_terminal_codex_enabled.txt",
		"open_desktop_pet_copilot_enabled.txt",
		"open_desktop_pet_opencode_enabled.txt",
		"open_desktop_pet_opencode_vscode_enabled.txt",
		"open_desktop_pet_opencode_app_enabled.txt",
		"open_desktop_pet_opencode_terminal_enabled.txt",
		"open_desktop_pet_opencode_app_executable_path.txt",
		"open_desktop_pet_claude_enabled.txt",
		"open_desktop_pet_claude_vscode_enabled.txt",
		"open_desktop_pet_claude_app_enabled.txt",
		"open_desktop_pet_claude_terminal_enabled.txt",
		"open_desktop_pet_claude_app_executable_path.txt",
		"open_desktop_pet_gemini_enabled.txt",
		"open_desktop_pet_agy_enabled.txt",
	])
	for directory in [_integration_home_path(), _codex_home_path()]:
		if directory.is_empty():
			continue
		for file_name in file_names:
			var path: String = String(directory).path_join(String(file_name))
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _focus_target(target_app: String, agent := "") -> bool:
	var target_path := _target_executable_path(target_app)
	if not _has_valid_executable_path(target_path) or _window_activator == null:
		return false
	if target_app == TARGET_VSCODE:
		var uri := CLAUDE_CODE_VSCODE_URI if agent == "claude" else CODEX_URI
		var process_id := OS.create_process(target_path, [
			"--reuse-window",
			"--open-url",
			uri,
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
		TARGET_CLAUDE_APP:
			return claude_app_executable_path
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
		TARGET_CLAUDE_APP:
			claude_app_executable_path = path
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


func _run_claude_code_configuration_tool() -> bool:
	var installer_path := _tool_path("install_claude_code_integration.ps1")
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


func _run_gemini_cli_configuration_tool() -> bool:
	var installer_path := _tool_path("install_gemini_cli_integration.ps1")
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


func _run_antigravity_cli_configuration_tool() -> bool:
	var installer_path := _tool_path("install_antigravity_cli_integration.ps1")
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
