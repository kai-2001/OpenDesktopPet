extends SceneTree

var _main: Node
var _previous_codex_home := ""
var _test_codex_home := ""
var _ui_settings_path := ""
var _previous_ui_settings := PackedByteArray()
var _had_previous_ui_settings := false
const TEST_PORT := 49876


func _init() -> void:
	_previous_codex_home = OS.get_environment("CODEX_HOME")
	_test_codex_home = ProjectSettings.globalize_path("user://codex-ui-test-home")
	_ui_settings_path = ProjectSettings.globalize_path("user://ui_settings.cfg")
	if FileAccess.file_exists(_ui_settings_path):
		_previous_ui_settings = FileAccess.get_file_as_bytes(_ui_settings_path)
		_had_previous_ui_settings = true
	OS.set_environment("CODEX_HOME", _test_codex_home)
	var test_config := ConfigFile.new()
	test_config.set_value("codex", "enabled", false)
	test_config.set_value("codex", "port", 38571)
	test_config.set_value("codex", "executable_path", "")
	test_config.set_value("codex_app", "enabled", false)
	test_config.set_value("codex_app", "executable_path", "")
	test_config.set_value("codex_terminal", "enabled", false)
	test_config.set_value("codex_terminal", "executable_path", "")
	test_config.set_value("opencode_terminal", "enabled", false)
	test_config.set_value("opencode_vscode", "enabled", false)
	test_config.set_value("opencode_app", "enabled", false)
	test_config.set_value("opencode_app", "executable_path", "")
	test_config.set_value("copilot", "enabled", false)
	test_config.set_value("claude_code_vscode", "enabled", false)
	test_config.set_value("claude_code_app", "enabled", false)
	test_config.set_value("claude_code_app", "executable_path", "")
	test_config.set_value("claude_code_terminal", "enabled", false)
	test_config.set_value("gemini_terminal", "enabled", false)
	test_config.set_value("agy_terminal", "enabled", false)
	test_config.save("user://ui_settings.cfg")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run_test")


func _run_test() -> void:
	await process_frame
	_main.call("_show_stats_window")
	await process_frame
	await process_frame

	var stats_window := _main.find_child("StatsWindow", true, false) as Window
	var tabs := _main.find_child("DetailsTabs", true, false) as TabContainer
	var character_list := _main.find_child("CharacterList", true, false) as ItemList
	_assert_true(stats_window != null, "details window exists")
	_assert_true(tabs != null, "details tabs exist")
	_assert_true(tabs.get_tab_count() == 4, "details window has four tabs")
	_assert_true(_main._stats_tab_buttons[2].text == "Agent", "Agent tab uses the short label")
	_assert_true(character_list != null, "character list exists")

	var codex_toggle := _main.find_child(
		"CodexEnabledToggle", true, false
	) as Button
	var copilot_toggle := _main.find_child(
		"CopilotEnabledToggle", true, false
	) as Button
	var codex_app_toggle := _main.find_child(
		"CodexAppEnabledToggle", true, false
	) as Button
	var terminal_toggle := _main.find_child(
		"TerminalCodexEnabledToggle", true, false
	) as Button
	var opencode_toggle := _main.find_child(
		"TerminalOpenCodeEnabledToggle", true, false
	) as Button
	var vscode_opencode_toggle := _main.find_child(
		"VscodeOpenCodeEnabledToggle", true, false
	) as Button
	var opencode_app_toggle := _main.find_child(
		"OpenCodeAppEnabledToggle", true, false
	) as Button
	var claude_vscode_toggle := _main.find_child(
		"ClaudeCodeVscodeEnabledToggle", true, false
	) as Button
	var claude_app_toggle := _main.find_child(
		"ClaudeDesktopEnabledToggle", true, false
	) as Button
	var claude_terminal_toggle := _main.find_child(
		"ClaudeCodeTerminalEnabledToggle", true, false
	) as Button
	var gemini_terminal_toggle := _main.find_child(
		"GeminiCliTerminalEnabledToggle", true, false
	) as Button
	var agy_terminal_toggle := _main.find_child(
		"AgyTerminalEnabledToggle", true, false
	) as Button
	var port_spin_box := _main.find_child(
		"AgentPortSpinBox", true, false
	) as SpinBox
	var status_label := _main.find_child(
		"AgentStatusLabel", true, false
	) as Label
	var executable_path := _main.find_child(
		"VscodeExecutablePath", true, false
	) as LineEdit
	var executable_browse := _main.find_child(
		"VscodeExecutableBrowseButton", true, false
	) as Button
	var executable_hint := _main.find_child(
		"VscodeExecutableHint", true, false
	) as Label
	var codex_app_path := _main.find_child(
		"CodexAppExecutablePath", true, false
	) as LineEdit
	var terminal_path := _main.find_child(
		"TerminalExecutablePath", true, false
	) as LineEdit
	var opencode_app_path := _main.find_child(
		"OpenCodeAppExecutablePath", true, false
	) as LineEdit
	var claude_app_path := _main.find_child(
		"ClaudeAppExecutablePath", true, false
	) as LineEdit
	_assert_true(codex_toggle != null, "Codex enabled toggle exists")
	_assert_true(copilot_toggle != null, "Copilot enabled toggle exists")
	_assert_true(codex_app_toggle != null, "Codex App enabled toggle exists")
	_assert_true(terminal_toggle != null, "Terminal Codex enabled toggle exists")
	_assert_true(opencode_toggle != null, "Terminal OpenCode enabled toggle exists")
	_assert_true(vscode_opencode_toggle != null, "VS Code OpenCode enabled toggle exists")
	_assert_true(opencode_app_toggle != null, "OpenCode App enabled toggle exists")
	_assert_true(claude_vscode_toggle != null, "VS Code Claude Code enabled toggle exists")
	_assert_true(claude_app_toggle != null, "Claude Desktop enabled toggle exists")
	_assert_true(claude_terminal_toggle != null, "Terminal Claude Code enabled toggle exists")
	_assert_true(gemini_terminal_toggle != null, "Terminal Gemini CLI enabled toggle exists")
	_assert_true(agy_terminal_toggle != null, "Terminal Antigravity CLI enabled toggle exists")
	_assert_true(
		(gemini_terminal_toggle.get_parent().get_child(0) as Label).text == "　Gemini CLI（舊版）",
		"Gemini notification toggle includes the legacy annotation"
	)
	_assert_true(
		(agy_terminal_toggle.get_parent().get_child(0) as Label).text == "　Antigravity CLI",
		"Antigravity CLI notification toggle is labeled"
	)
	_assert_true(port_spin_box != null, "Codex port input exists")
	_assert_true(status_label != null, "Codex status label exists")
	_assert_true(executable_path != null, "VS Code executable path input exists")
	_assert_true(executable_browse != null, "VS Code executable browse button exists")
	_assert_true(executable_hint != null, "VS Code executable validation hint exists")
	_assert_true(codex_app_path != null, "Codex App executable path input exists")
	_assert_true(terminal_path != null, "Terminal executable path input exists")
	_assert_true(opencode_app_path != null, "OpenCode App executable path input exists")
	_assert_true(claude_app_path != null, "Claude Desktop executable path input exists")
	_assert_true(
		claude_app_path.get_parent().get_child(claude_app_path.get_index() - 1) is HSeparator,
		"Claude Desktop has its own separator from OpenCode Desktop"
	)
	_assert_true(
		(claude_app_path.get_parent().get_child(claude_app_path.get_index() + 1) as HBoxContainer).get_child(0).text == "Claude",
		"Claude executable section uses the Claude title"
	)
	_assert_true(
		(claude_app_toggle.get_parent().get_child(0) as Label).text == "　Claude Code",
		"Claude notification toggle is labeled Claude Code"
	)
	_assert_true(executable_browse.text == "📁", "browse control uses a folder icon")
	_assert_true(
		executable_path.text.is_empty(),
		"VS Code path detection is deferred until the Agent tab is opened"
	)
	var detected_executable_path := executable_path.text
	var manual_executable_path := "C:/Tools/Portable VS Code/Code.exe"
	executable_path.text = manual_executable_path
	executable_path.text_submitted.emit(manual_executable_path)
	await process_frame
	var ui_config := ConfigFile.new()
	_assert_true(ui_config.load("user://ui_settings.cfg") == OK, "UI settings can be read")
	_assert_true(
		String(ui_config.get_value("codex", "executable_path", ""))
			== manual_executable_path,
		"manually entered VS Code path is saved"
	)
	executable_path.text = detected_executable_path
	executable_path.text_submitted.emit(detected_executable_path)
	await process_frame
	_assert_true(
		_main.find_child("CodexConfigureButton", true, false) == null,
		"Codex port no longer needs a configure button"
	)
	_assert_true(
		_main.find_child("CodexReconnectButton", true, false) == null,
		"Codex toggle replaces the reconnect button"
	)
	_assert_true(not codex_toggle.button_pressed, "new settings default to closed")
	_assert_true(not copilot_toggle.button_pressed, "Copilot defaults to closed")
	_assert_true(not codex_app_toggle.button_pressed, "Codex App defaults to closed")
	_assert_true(not terminal_toggle.button_pressed, "Terminal Codex defaults to closed")
	_assert_true(not opencode_toggle.button_pressed, "Terminal OpenCode defaults to closed")
	_assert_true(not vscode_opencode_toggle.button_pressed, "VS Code OpenCode defaults to closed")
	_assert_true(not opencode_app_toggle.button_pressed, "OpenCode App defaults to closed")
	_assert_true(not claude_vscode_toggle.button_pressed, "VS Code Claude Code defaults to closed")
	_assert_true(not claude_app_toggle.button_pressed, "Claude Desktop defaults to closed")
	_assert_true(not claude_terminal_toggle.button_pressed, "Terminal Claude Code defaults to closed")
	_assert_true(not gemini_terminal_toggle.button_pressed, "Terminal Gemini CLI defaults to closed")
	_assert_true(not agy_terminal_toggle.button_pressed, "Terminal Antigravity CLI defaults to closed")
	_assert_true(codex_toggle.text == "關", "closed toggle shows 關")
	_assert_true(
		(port_spin_box.get_parent().get_child(0) as Label).text == "Agent 通知",
		"first row identifies the shared Agent notification feature"
	)
	_assert_true(
		port_spin_box.get_parent() != codex_toggle.get_parent(),
		"shared port is separate from individual Agent toggles"
	)
	_assert_true(
		port_spin_box.get_parent().get_child_count() == 3,
		"shared port row contains title, port label, and input"
	)
	_assert_true(
		(port_spin_box.get_parent().get_child(1) as Label).text == "通訊埠",
		"port input has a visible label"
	)
	_assert_true(
		status_label.get_parent() == port_spin_box.get_parent().get_parent(),
		"status is directly under the shared port row"
	)
	_assert_true(
		status_label.get_index() == port_spin_box.get_parent().get_index() + 1,
		"status immediately follows the shared port row"
	)
	_assert_true(
		codex_toggle.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"toggle keeps the pointing-hand cursor"
	)
	_assert_true(
		not FileAccess.file_exists(_test_codex_home.path_join(
			"open_desktop_pet_codex_app_enabled.txt"
		)),
		"runtime migration no longer writes Codex enable files"
	)

	codex_toggle.set_pressed_no_signal(false)
	codex_toggle.toggled.emit(false)
	await process_frame
	port_spin_box.set_value_no_signal(TEST_PORT)
	port_spin_box.value_changed.emit(float(TEST_PORT))
	_assert_true(
		int(port_spin_box.value) == TEST_PORT,
		"port changes are retained without a configure button"
	)

	codex_toggle.set_pressed_no_signal(true)
	codex_toggle.toggled.emit(true)
	await process_frame
	_assert_true(codex_toggle.text == "開", "open toggle shows 開")
	var toggle_text_color := codex_toggle.get_theme_color("font_color")
	_assert_true(
		codex_toggle.get_theme_color("font_hover_color") == toggle_text_color
		and codex_toggle.get_theme_color("font_pressed_color") == toggle_text_color
		and codex_toggle.get_theme_color("font_hover_pressed_color") == toggle_text_color
		and codex_toggle.get_theme_color("font_focus_color") == toggle_text_color,
		"toggle text color stays fixed in every pointer and focus state"
	)
	_assert_true(
		not port_spin_box.editable,
		"open state locks the active port"
	)
	_assert_true(_main._agent_controller.codex_enabled, "open state enables VS Code Codex")
	_assert_true(
		not _main._agent_controller.codex_app_enabled,
		"VS Code Codex does not enable Codex App"
	)
	_assert_true(
		status_label.text.contains("127.0.0.1:%d" % TEST_PORT),
		"open state listens on the port selected while closed"
	)

	_assert_true(
		terminal_path.text.is_empty(),
		"terminal executable detection is deferred until the Agent tab is opened"
	)
	tabs.current_tab = 2
	for _frame in 120:
		await process_frame
		if not executable_path.text.is_empty() \
				or not codex_app_path.text.is_empty() \
				or not terminal_path.text.is_empty():
			break
	_assert_true(tabs.current_tab == 2, "Agent notification tab can be selected")
	if OS.get_name() == "Windows":
		_assert_true(
			executable_path.text.is_empty()
			or FileAccess.file_exists(executable_path.text),
			"Agent tab refreshes the VS Code executable path when it can be detected"
		)
		_assert_true(
			codex_app_path.text.is_empty()
			or FileAccess.file_exists(codex_app_path.text),
			"Agent tab refreshes the Codex App executable path when it can be detected"
		)
		_assert_true(
			terminal_path.text.is_empty()
			or FileAccess.file_exists(terminal_path.text),
			"Agent tab refreshes the terminal executable path when it can be detected"
		)
	tabs.current_tab = 3
	await process_frame
	_assert_true(tabs.current_tab == 3, "character tab can be selected")

	_main.call("_prepare_shutdown")
	_assert_true(
		not FileAccess.file_exists(_test_codex_home.path_join(
			"open_desktop_pet_codex_enabled.txt"
		)),
		"shutdown does not restore legacy Codex enable files"
	)
	# Free the scene while CODEX_HOME still points at the test directory.
	_main.free()
	_main = null
	OS.set_environment("CODEX_HOME", _previous_codex_home)
	_restore_ui_settings()
	print("AGENT_SETTINGS_UI_TEST_OK")
	quit()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		push_error("AGENT_SETTINGS_UI_TEST_FAILED: " + message)
		quit(1)


func _restore_ui_settings() -> void:
	if _had_previous_ui_settings:
		var file := FileAccess.open(_ui_settings_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_previous_ui_settings)
			file.close()
	elif FileAccess.file_exists(_ui_settings_path):
		DirAccess.remove_absolute(_ui_settings_path)
