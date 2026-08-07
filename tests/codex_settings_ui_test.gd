extends SceneTree

var _main: Node
var _previous_codex_home := ""
var _test_codex_home := ""


func _init() -> void:
	_previous_codex_home = OS.get_environment("CODEX_HOME")
	_test_codex_home = ProjectSettings.globalize_path("user://codex-ui-test-home")
	OS.set_environment("CODEX_HOME", _test_codex_home)
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
	_assert_true(tabs.get_tab_count() == 3, "details window has three tabs")
	_assert_true(character_list != null, "character list exists")

	var enabled_toggle := _main.find_child(
		"CodexEnabledToggle", true, false
	) as Button
	var port_spin_box := _main.find_child(
		"CodexPortSpinBox", true, false
	) as SpinBox
	var status_label := _main.find_child(
		"CodexStatusLabel", true, false
	) as Label
	var executable_path := _main.find_child(
		"CodexExecutablePath", true, false
	) as LineEdit
	var executable_browse := _main.find_child(
		"CodexExecutableBrowseButton", true, false
	) as Button
	var executable_dialog := _main.find_child(
		"CodexExecutableDialog", true, false
	) as FileDialog
	var executable_hint := _main.find_child(
		"CodexExecutableHint", true, false
	) as Label
	_assert_true(enabled_toggle != null, "Codex enabled toggle exists")
	_assert_true(port_spin_box != null, "Codex port input exists")
	_assert_true(status_label != null, "Codex status label exists")
	_assert_true(executable_path != null, "VS Code executable path input exists")
	_assert_true(executable_browse != null, "VS Code executable browse button exists")
	_assert_true(executable_dialog != null, "VS Code executable file dialog exists")
	_assert_true(executable_hint != null, "VS Code executable validation hint exists")
	_assert_true(executable_browse.text == "📁", "browse control uses a folder icon")
	_assert_true(
		executable_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE,
		"VS Code selector opens one executable file"
	)
	_assert_true(
		executable_dialog.filters.size() == 1
			and executable_dialog.filters[0].contains("*.exe"),
		"VS Code selector filters Windows executables"
	)
	if OS.get_name() == "Windows":
		_assert_true(
			FileAccess.file_exists(executable_path.text),
			"standard VS Code installation is detected automatically"
		)
		_assert_true(
			executable_path.text.get_extension().to_lower() == "exe",
			"detected VS Code path is an executable"
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
	_assert_true(not enabled_toggle.button_pressed, "new settings default to closed")
	_assert_true(enabled_toggle.text == "關", "closed toggle shows 關")
	_assert_true(
		(port_spin_box.get_parent().get_child(0) as Label).text == "Codex 完成通知",
		"first row identifies the Codex notification feature"
	)
	_assert_true(
		port_spin_box.get_parent() == enabled_toggle.get_parent(),
		"port input and toggle share the first row"
	)
	_assert_true(
		port_spin_box.get_parent().get_child_count() == 4,
		"first row contains feature label, port label, input, and toggle"
	)
	_assert_true(
		(port_spin_box.get_parent().get_child(1) as Label).text == "通訊埠",
		"port input has a visible label"
	)
	_assert_true(
		status_label.get_parent() == port_spin_box.get_parent().get_parent(),
		"status is the second Codex row"
	)
	_assert_true(
		status_label.get_index() == port_spin_box.get_parent().get_index() + 1,
		"status immediately follows the control row"
	)
	_assert_true(
		enabled_toggle.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"toggle keeps the pointing-hand cursor"
	)
	var enabled_file := _test_codex_home.path_join(
		"open_desktop_pet_notify_enabled.txt"
	)
	var port_file := _test_codex_home.path_join(
		"open_desktop_pet_notify_port.txt"
	)
	_assert_true(
		FileAccess.get_file_as_string(enabled_file).strip_edges() == "0",
		"closed state disables the Codex sender"
	)

	enabled_toggle.set_pressed_no_signal(false)
	enabled_toggle.toggled.emit(false)
	await process_frame
	port_spin_box.set_value_no_signal(39876)
	port_spin_box.value_changed.emit(39876.0)
	_assert_true(
		FileAccess.get_file_as_string(port_file).strip_edges() == "39876",
		"port changes are applied without a configure button"
	)

	enabled_toggle.set_pressed_no_signal(true)
	enabled_toggle.toggled.emit(true)
	await process_frame
	_assert_true(enabled_toggle.text == "開", "open toggle shows 開")
	var toggle_text_color := enabled_toggle.get_theme_color("font_color")
	_assert_true(
		enabled_toggle.get_theme_color("font_hover_color") == toggle_text_color
		and enabled_toggle.get_theme_color("font_pressed_color") == toggle_text_color
		and enabled_toggle.get_theme_color("font_hover_pressed_color") == toggle_text_color
		and enabled_toggle.get_theme_color("font_focus_color") == toggle_text_color,
		"toggle text color stays fixed in every pointer and focus state"
	)
	_assert_true(
		not port_spin_box.editable,
		"open state locks the active port"
	)
	_assert_true(
		FileAccess.get_file_as_string(enabled_file).strip_edges() == "1",
		"open state enables the Codex sender"
	)
	_assert_true(
		status_label.text.contains("127.0.0.1:39876"),
		"open state listens on the port selected while closed"
	)

	tabs.current_tab = 2
	await process_frame
	_assert_true(tabs.current_tab == 2, "character tab can be selected")

	_main.call("_prepare_shutdown")
	_assert_true(
		FileAccess.get_file_as_string(enabled_file).strip_edges() == "0",
		"shutdown disables the Codex sender"
	)
	# Free the scene while CODEX_HOME still points at the test directory. The
	# shutdown callback writes the disabled marker again during tree exit.
	_main.free()
	_main = null
	OS.set_environment("CODEX_HOME", _previous_codex_home)
	print("CODEX_SETTINGS_UI_TEST_OK")
	quit()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		push_error("CODEX_SETTINGS_UI_TEST_FAILED: " + message)
		quit(1)
