extends "res://scripts/agent_integration_controller.gd"

# Drives the desktop (non-headless) Agent code paths for characterization tests
# while keeping every side effect inside a test directory. Installers, Codex
# trust checks and executable detection are replaced by recorders.

const FakeCodexHookTrustServiceScript = preload(
	"res://tests/support/fake_codex_hook_trust_service.gd"
)

static var main_log: Array[String] = []
static var worker_log: Array[String] = []
static var installer_succeeds := true
static var configured: Dictionary = {}
static var home_root := ""
static var _log_mutex := Mutex.new()


static func reset_log() -> void:
	_log_mutex.lock()
	main_log.clear()
	worker_log.clear()
	_log_mutex.unlock()


static func record(entry: String) -> void:
	_log_mutex.lock()
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		main_log.append(entry)
	else:
		worker_log.append(entry)
	_log_mutex.unlock()


static func take_log() -> Array[String]:
	_log_mutex.lock()
	var entries: Array[String] = main_log.duplicate()
	var worker_entries: Array[String] = worker_log.duplicate()
	main_log.clear()
	worker_log.clear()
	_log_mutex.unlock()
	# Worker threads may overlap, so only their set of calls is stable.
	worker_entries.sort()
	for entry: String in worker_entries:
		entries.append("worker " + entry)
	return entries


func _init() -> void:
	super()
	var trust_service = FakeCodexHookTrustServiceScript.new()
	trust_service.recorder = func(entry: String) -> void: record(entry)
	_codex_hook_trust_service = trust_service
	configuration_failed.connect(
		func(target_name: String) -> void: record("signal configuration_failed " + target_name)
	)
	codex_unavailable.connect(
		func(target_name: String, message: String) -> void:
			record("signal codex_unavailable %s %s" % [target_name, message])
	)
	codex_trust_required.connect(
		func(target_name: String, status: String, message: String) -> void:
			record("signal codex_trust_required %s %s %s" % [target_name, status, message])
	)
	codex_trust_ready.connect(
		func(target_name: String, target_app: String) -> void:
			record("signal codex_trust_ready %s %s" % [target_name, target_app])
	)
	codex_trust_refresh_required.connect(
		func(target_name: String, status: String, message: String) -> void:
			record("signal codex_trust_refresh_required %s %s %s" % [target_name, status, message])
	)


func _is_headless() -> bool:
	return false


func _run_configuration_tool(installer_file_name: String) -> bool:
	record("install " + installer_file_name)
	if installer_succeeds:
		configured[installer_file_name] = true
	return installer_succeeds


func _is_configured(installer_file_name: String) -> bool:
	return bool(configured.get(installer_file_name, false))


func is_codex_configured() -> bool:
	return _is_configured("install_codex_integration.ps1")


func is_copilot_configured() -> bool:
	return _is_configured("install_copilot_integration.ps1")


func is_opencode_configured() -> bool:
	return _is_configured("install_opencode_integration.ps1")


func is_claude_code_configured() -> bool:
	return _is_configured("install_claude_code_integration.ps1")


func is_gemini_cli_configured() -> bool:
	return _is_configured("install_gemini_cli_integration.ps1")


func is_antigravity_cli_configured() -> bool:
	return _is_configured("install_antigravity_cli_integration.ps1")


func is_pi_configured() -> bool:
	return _is_configured("install_pi_integration.ps1")


func refresh_executable_paths_if_invalid(targets: Array[String]) -> void:
	# Detection runs every requested target in one pass, so only the set of
	# targets matters, not their order or repetition.
	var unique_targets: Array[String] = []
	for target: String in targets:
		if not unique_targets.has(target):
			unique_targets.append(target)
	unique_targets.sort()
	record("refresh_paths " + ",".join(unique_targets))
	super(targets)


func _detect_executable_path(target: String) -> String:
	record("detect " + target)
	return ""


func _has_live_runtime_owner() -> bool:
	return false


func _user_profile_path() -> String:
	return home_root.path_join("profile")


func _codex_home_path() -> String:
	return home_root.path_join("codex")
