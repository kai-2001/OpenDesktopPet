extends SceneTree

const ControllerScript = preload("res://scripts/agent_integration_controller.gd")

var _test_root := ""
var _previous_user_profile := ""
var _previous_codex_home := ""


func _init() -> void:
	_previous_user_profile = OS.get_environment("USERPROFILE")
	_previous_codex_home = OS.get_environment("CODEX_HOME")
	_test_root = ProjectSettings.globalize_path(
		"user://agent-configuration-check-" + str(Time.get_ticks_msec())
	)
	OS.set_environment("USERPROFILE", _test_root)
	OS.set_environment("CODEX_HOME", _test_root.path_join(".codex"))
	call_deferred("_run")


func _run() -> void:
	var codex_home := _test_root.path_join(".codex")
	var integration_home := _test_root.path_join(".open-desktop-pet")
	var claude_home := _test_root.path_join(".claude")
	var gemini_home := _test_root.path_join(".gemini")
	var controller = ControllerScript.new()
	_assert_true(not controller.is_codex_configured(), "Codex starts invalid")
	_assert_true(not controller.is_copilot_configured(), "Copilot starts invalid")
	_assert_true(not controller.is_opencode_configured(), "OpenCode starts invalid")
	_assert_true(not controller.is_claude_code_configured(), "Claude Code starts invalid")
	_assert_true(not controller.is_gemini_cli_configured(), "Gemini CLI starts invalid")
	_assert_true(not controller.is_antigravity_cli_configured(), "Antigravity CLI starts invalid")

	_make_directory(codex_home)
	_make_directory(integration_home)
	_write(integration_home.path_join("open_desktop_pet_runtime.ps1"), "# OpenDesktopPet runtime schema v1")
	_write(codex_home.path_join("open_desktop_pet_codex_installed.txt"), "1")
	_write(integration_home.path_join("codex_stop_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_write(
		codex_home.path_join("hooks.json"),
		"{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"commandWindows\":\"powershell.exe -File codex_stop_notify.ps1\"}]}]}}"
	)
	_assert_true(controller.is_codex_configured(), "Codex valid files are detected")
	_write(codex_home.path_join("hooks.json"), "{\"hooks\":{\"Stop\":[]}}")
	_assert_true(not controller.is_codex_configured(), "Codex Stop hook drift is detected")

	_write(integration_home.path_join("open_desktop_pet_copilot_installed.txt"), "1")
	_write(integration_home.path_join("vscode_copilot_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_make_directory(_test_root.path_join(".copilot/hooks"))
	_write(
		_test_root.path_join(".copilot/hooks/open-desktop-pet.json"),
		"{\"hooks\":{\"Stop\":[{\"windows\":\"vscode_copilot_notify.ps1\"}]}}"
	)
	_assert_true(controller.is_copilot_configured(), "Copilot hook is detected")
	_write(_test_root.path_join(".copilot/hooks/open-desktop-pet.json"), "{}")
	_assert_true(not controller.is_copilot_configured(), "Copilot hook drift is detected")

	_write(integration_home.path_join("open_desktop_pet_opencode_installed.txt"), "1")
	_write(integration_home.path_join("opencode_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_make_directory(_test_root.path_join(".config/opencode/plugins"))
	_write(
		_test_root.path_join(".config/opencode/plugins/open-desktop-pet.js"),
		"// OpenDesktopPet OpenCode notification plugin\n" \
			+ "const bridgePath = 'opencode_notify.ps1'\n" \
			+ "session.idle"
	)
	_assert_true(controller.is_opencode_configured(), "OpenCode plugin is detected")
	_write(_test_root.path_join(".config/opencode/plugins/open-desktop-pet.js"), "// replaced")
	_assert_true(not controller.is_opencode_configured(), "OpenCode plugin drift is detected")

	_write(integration_home.path_join("open_desktop_pet_claude_code_installed.txt"), "OpenDesktopPet Claude Code notification hook")
	_write(integration_home.path_join("claude_code_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_make_directory(claude_home)
	_write(
		claude_home.path_join("settings.json"),
		"{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"claude_code_notify.ps1\"}]}]}}"
	)
	_assert_true(controller.is_claude_code_configured(), "Claude Code hook is detected")
	_write(claude_home.path_join("settings.json"), "{\"hooks\":{}}")
	_assert_true(not controller.is_claude_code_configured(), "Claude Code hook drift is detected")

	_write(integration_home.path_join("open_desktop_pet_gemini_cli_installed.txt"), "OpenDesktopPet Gemini CLI notification hooks")
	_write(integration_home.path_join("gemini_cli_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_make_directory(gemini_home)
	_write(
		gemini_home.path_join("settings.json"),
		"{\"hooks\":{\"AfterAgent\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"gemini_cli_notify.ps1\"}]}],\"Notification\":[{\"matcher\":\"ToolPermission\",\"hooks\":[{\"type\":\"command\",\"command\":\"gemini_cli_notify.ps1\"}]}]}}"
	)
	_assert_true(controller.is_gemini_cli_configured(), "Gemini CLI hooks are detected")
	_write(gemini_home.path_join("settings.json"), "{\"hooks\":{\"AfterAgent\":[]}}")
	_assert_true(not controller.is_gemini_cli_configured(), "Gemini CLI hook drift is detected")

	_write(integration_home.path_join("open_desktop_pet_antigravity_cli_installed.txt"), "OpenDesktopPet Antigravity CLI notification hook")
	_write(integration_home.path_join("antigravity_cli_notify.ps1"), "# OpenDesktopPet runtime schema v1")
	_make_directory(gemini_home.path_join("config"))
	_write(
		gemini_home.path_join("config/hooks.json"),
		"{\"open-desktop-pet\":{\"Stop\":[{\"type\":\"command\",\"command\":\"antigravity_cli_notify.ps1\",\"timeout\":5}]}}"
	)
	_assert_true(
		not controller.is_antigravity_cli_configured(),
		"Antigravity CLI legacy hook requires migration"
	)
	var agy_bridge_path := integration_home.path_join("antigravity_cli_notify.ps1").replace("/", "\\")
	var agy_invocation := "& '%s'" % agy_bridge_path.replace("'", "''")
	var agy_command := "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand " \
		+ Marshalls.raw_to_base64(agy_invocation.to_utf16_buffer())
	_write(
		gemini_home.path_join("config/hooks.json"),
		"{\"open-desktop-pet\":{\"Stop\":[{\"type\":\"command\",\"command\":\"%s\",\"timeout\":5}]}}" % agy_command
	)
	_assert_true(controller.is_antigravity_cli_configured(), "Antigravity CLI encoded hook is detected")
	_write(
		gemini_home.path_join("config/hooks.json"),
		"{\"open-desktop-pet\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"antigravity_cli_notify.ps1\"}]}]}}"
	)
	_assert_true(
		not controller.is_antigravity_cli_configured(),
		"Antigravity CLI wrapped hook drift is detected"
	)
	_write(gemini_home.path_join("config/hooks.json"), "{\"open-desktop-pet\":{\"Stop\":[]}}")
	_assert_true(not controller.is_antigravity_cli_configured(), "Antigravity CLI hook drift is detected")

	_cleanup()
	print("AGENT_CONFIGURATION_CHECK_TEST_OK")
	quit(0)


func _make_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)


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
	printerr("AGENT_CONFIGURATION_CHECK_TEST_FAILED: " + message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	OS.set_environment("USERPROFILE", _previous_user_profile)
	OS.set_environment("CODEX_HOME", _previous_codex_home)
	if not _test_root.is_empty() and DirAccess.dir_exists_absolute(_test_root):
		DirAccess.remove_absolute(_test_root)
