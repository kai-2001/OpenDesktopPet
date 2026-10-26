extends SceneTree

# Characterization test for the Agent settings tab. It drives the real main
# scene through the UI and records what every action does: installer runs,
# executable-path refreshes, controller state, saved settings, the runtime
# registration read by the notification bridges, the visible controls and the
# pet's speech. The recording is compared with tests/fixtures; run with
# ODP_RECORD_AGENT_GOLDEN=1 to rewrite it from the current behavior.

const RecordingControllerScript = preload(
	"res://tests/support/recording_agent_integration_controller.gd"
)
const FakeCodexHookTrustServiceScript = preload(
	"res://tests/support/fake_codex_hook_trust_service.gd"
)
const GOLDEN_PATH := "res://tests/fixtures/agent_settings_golden.txt"
const TEST_PORT := 49871
const CHANGED_PORT := 49872
const TOGGLE_NAMES: Array[String] = [
	"CodexEnabledToggle",
	"ClaudeCodeVscodeEnabledToggle",
	"CopilotEnabledToggle",
	"VscodeOpenCodeEnabledToggle",
	"CodexAppEnabledToggle",
	"OpenCodeAppEnabledToggle",
	"ClaudeDesktopEnabledToggle",
	"TerminalCodexEnabledToggle",
	"PiCodexEnabledToggle",
	"TerminalOpenCodeEnabledToggle",
	"GeminiCliTerminalEnabledToggle",
	"AgyTerminalEnabledToggle",
	"ClaudeCodeTerminalEnabledToggle",
]
const CODEX_TOGGLE_NAMES: Array[String] = [
	"CodexEnabledToggle", "CodexAppEnabledToggle", "TerminalCodexEnabledToggle"
]
const PATH_CONTROLS: Array[Array] = [
	["VscodeExecutablePath", "VscodeExecutableHint"],
	["CodexAppExecutablePath", "CodexAppExecutableHint"],
	["OpenCodeAppExecutablePath", "OpenCodeAppExecutableHint"],
	["ClaudeAppExecutablePath", "ClaudeAppExecutableHint"],
	["TerminalExecutablePath", "TerminalExecutableHint"],
]
const CONTROLLER_PROPERTIES: Array[String] = [
	"enabled",
	"codex_enabled",
	"codex_app_enabled",
	"terminal_codex_enabled",
	"terminal_opencode_enabled",
	"vscode_opencode_enabled",
	"opencode_app_enabled",
	"copilot_enabled",
	"claude_vscode_enabled",
	"claude_app_enabled",
	"claude_terminal_enabled",
	"gemini_terminal_enabled",
	"agy_terminal_enabled",
	"pi_codex_enabled",
	"port",
	"executable_path",
	"codex_app_executable_path",
	"terminal_executable_path",
	"opencode_app_executable_path",
	"claude_app_executable_path",
]
const AGENT_SETTINGS_SECTIONS: Array[String] = [
	"codex",
	"codex_app",
	"codex_terminal",
	"codex_setup",
	"opencode_terminal",
	"opencode_vscode",
	"opencode_app",
	"copilot",
	"claude_code_vscode",
	"claude_code_app",
	"claude_code_terminal",
	"gemini_terminal",
	"agy_terminal",
	"pi_codex_terminal",
]

const UI_SETTINGS_PATH := "user://ui_settings.cfg"

var _main: Node
var _home_root := ""
var _previous_ui_settings := PackedByteArray()
var _had_ui_settings := false
var _output: Array[String] = []
var _previous_state: Dictionary = {}
var _last_bubble_token := 0
var _failed := false


func _init() -> void:
	_home_root = ProjectSettings.globalize_path(
		"user://agent-golden-" + str(Time.get_ticks_usec())
	)
	DirAccess.make_dir_recursive_absolute(_home_root)
	# The run ends with every Agent enabled. Restore the settings afterwards so
	# later tests sharing this user directory never start real installers.
	_had_ui_settings = FileAccess.file_exists(UI_SETTINGS_PATH)
	if _had_ui_settings:
		_previous_ui_settings = FileAccess.get_file_as_bytes(UI_SETTINGS_PATH)
	RecordingControllerScript.home_root = _home_root
	RecordingControllerScript.installer_succeeds = true
	RecordingControllerScript.configured = {}
	FakeCodexHookTrustServiceScript.available = true
	FakeCodexHookTrustServiceScript.trusted = false
	FakeCodexHookTrustServiceScript.availability_errors = 0
	FakeCodexHookTrustServiceScript.status_errors = 0
	var config := ConfigFile.new()
	config.set_value("codex", "enabled", true)
	config.set_value("codex", "port", TEST_PORT)
	config.set_value("codex_terminal", "executable_path", "C:/ODP-golden/startup-terminal.exe")
	config.set_value("claude_code_terminal", "enabled", true)
	config.save(UI_SETTINGS_PATH)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.agent_controller_script = RecordingControllerScript
	root.add_child(_main)
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_main._idle_behavior_timer.stop()
	await _settle()
	await _step("startup with VS Code Codex and terminal Claude Code saved as enabled")

	_main.call("_show_stats_window")
	await _settle()
	await _step("open details window")
	_tabs().current_tab = 3
	await _settle()
	await _step("select Agent tab")

	FakeCodexHookTrustServiceScript.trusted = true
	for toggle_name: String in TOGGLE_NAMES:
		await _press_toggle(toggle_name, true)
		await _step("enable " + toggle_name)
		await _press_toggle(toggle_name, false)
		await _step("disable " + toggle_name)

	RecordingControllerScript.configured = {}
	RecordingControllerScript.installer_succeeds = false
	for toggle_name: String in TOGGLE_NAMES:
		await _press_toggle(toggle_name, true)
		await _step("enable %s while its installer fails" % toggle_name)
		_clear_speech_lock()
	RecordingControllerScript.installer_succeeds = true

	FakeCodexHookTrustServiceScript.trusted = false
	await _press_toggle("CodexAppEnabledToggle", true)
	await _step("enable ChatGPT Codex before the hooks are trusted")
	await _press_button("CodexHookTrustPageReviewButton")
	await _step("open Codex hook review from the Agent tab")
	await _press_button("CodexHookTrustRecheckButton")
	await _step("recheck while still untrusted")
	FakeCodexHookTrustServiceScript.trusted = true
	await _press_button("CodexHookTrustRecheckButton")
	await _step("recheck after trusting the hooks")
	_clear_speech_lock()
	await _press_toggle("CodexAppEnabledToggle", false)
	await _step("disable ChatGPT Codex")

	FakeCodexHookTrustServiceScript.trusted = false
	await _press_toggle("TerminalCodexEnabledToggle", true)
	await _step("enable terminal Codex before the hooks are trusted")
	var trust_dialog := _find("CodexHookTrustDialog") as ConfirmationDialog
	trust_dialog.confirmed.emit()
	await _settle()
	await _step("confirm the trust dialog")
	trust_dialog.canceled.emit()
	await _settle()
	await _step("postpone trust from the dialog")
	await _press_button("CodexHookTrustRecheckButton")
	await _step("recheck with no pending Codex target")

	FakeCodexHookTrustServiceScript.available = false
	await _press_toggle("CodexEnabledToggle", true)
	await _step("enable VS Code Codex without a Codex runtime")
	FakeCodexHookTrustServiceScript.available = true
	FakeCodexHookTrustServiceScript.trusted = true

	FakeCodexHookTrustServiceScript.status_errors = 2
	await _press_toggle("CodexAppEnabledToggle", true)
	await _step("enable ChatGPT Codex while the trust query keeps failing")
	FakeCodexHookTrustServiceScript.status_errors = 1
	await _press_toggle("CodexAppEnabledToggle", true)
	await _step("enable ChatGPT Codex after one failed trust query")
	_clear_speech_lock()
	await _press_toggle("CodexAppEnabledToggle", false)
	await _step("disable ChatGPT Codex after the retried check")

	for controls: Array in PATH_CONTROLS:
		var line_edit := _find(controls[0]) as LineEdit
		var path := "C:/ODP-golden/%s.exe" % controls[0]
		line_edit.text = path
		line_edit.text_submitted.emit(path)
		await _settle()
		await _step("submit " + controls[0])

	var port_spin_box := _find("AgentPortSpinBox") as SpinBox
	port_spin_box.set_value_no_signal(CHANGED_PORT)
	port_spin_box.value_changed.emit(float(CHANGED_PORT))
	await _settle()
	await _step("change port while every Agent is off")
	await _press_toggle("ClaudeCodeTerminalEnabledToggle", true)
	await _step("enable terminal Claude Code on the new port")
	port_spin_box = _find("AgentPortSpinBox") as SpinBox
	port_spin_box.set_value_no_signal(TEST_PORT)
	port_spin_box.value_changed.emit(float(TEST_PORT))
	await _settle()
	await _step("try to change port while an Agent is on")

	await _press_toggle("PiCodexEnabledToggle", true)
	await _step("enable Pi")
	_select_details_theme(1)
	await _settle()
	await _step("switch the details window to the dark theme")
	await _press_toggle("PiCodexEnabledToggle", false)
	await _step("disable Pi in the rebuilt window")
	_select_details_theme(0)
	await _settle()
	await _step("switch back to the light theme")

	_main.call("_destroy_stats_window")
	await _settle()
	await _step("close details window")
	_main.call("_show_stats_window", 3)
	await _settle()
	await _step("reopen details window on the Agent tab")

	for toggle_name: String in TOGGLE_NAMES:
		var toggle := _find(toggle_name) as Button
		if not toggle.button_pressed:
			await _press_toggle(toggle_name, true)
	await _step("enable every Agent")

	_main.call("_prepare_shutdown")
	await _settle()
	await _step("shutdown")
	_main.free()

	_main = load("res://scenes/main.tscn").instantiate()
	_main.agent_controller_script = RecordingControllerScript
	_last_bubble_token = 0
	root.add_child(_main)
	await process_frame
	_main._idle_behavior_timer.stop()
	await _settle()
	await _step("restart with every Agent saved as enabled")
	_main.call("_show_stats_window", 3)
	await _settle()
	await _step("open the Agent tab after restart")

	_main.call("_prepare_shutdown")
	await _settle()
	await _step("final shutdown")
	_main.free()
	_main = null
	_finish()


func _select_details_theme(index: int) -> void:
	# Choose the theme through the settings tab like a user would.
	var settings_tab := _find("設定")
	for node: Node in settings_tab.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option.item_count == 2 and option.get_item_text(1) == "深色":
			option.select(index)
			option.item_selected.emit(index)
			return
	_fail("missing details theme option")


func _press_toggle(toggle_name: String, enabled: bool) -> void:
	var toggle := _find(toggle_name) as Button
	if toggle == null:
		_fail("missing toggle " + toggle_name)
		return
	toggle.set_pressed_no_signal(enabled)
	toggle.toggled.emit(enabled)
	await _settle()


func _press_button(button_name: String) -> void:
	var button := _find(button_name) as Button
	if button == null:
		_fail("missing button " + button_name)
		return
	button.pressed.emit()
	await _settle()


func _clear_speech_lock() -> void:
	# A Codex success notice holds the bubble for a minute; later steps must
	# still be able to show their own speech.
	_main._agent_notification_active = false


func _settle() -> void:
	for _frame in 600:
		await process_frame
		var controller = _main._agent_controller if _main != null else null
		if controller == null:
			break
		if controller._codex_setup_thread == null \
				and controller._executable_path_detection_thread == null \
				and controller._pending_executable_path_detection_targets.is_empty():
			break
	for _frame in 4:
		await process_frame


func _step(title: String) -> void:
	_output.append("## " + title)
	for entry: String in RecordingControllerScript.take_log():
		_output.append("  call " + _normalize(entry))
	if _main != null and _main._bubble_token != _last_bubble_token:
		_last_bubble_token = _main._bubble_token
		_output.append("  say " + _normalize(_strip_breaks(_main.bubble_label.text)))
	var current := _capture_state()
	var keys := current.keys()
	keys.sort()
	for key: String in keys:
		if not _previous_state.has(key) or _previous_state[key] != current[key]:
			# Empty values must not leave trailing whitespace for git diff --check.
			_output.append(("  %s = %s" % [key, current[key]]).strip_edges(false, true))
	for key: String in _previous_state.keys():
		if not current.has(key):
			_output.append("  %s removed" % key)
	_previous_state = current


func _capture_state() -> Dictionary:
	var captured := {}
	var controller = _main._agent_controller
	for property: String in CONTROLLER_PROPERTIES:
		captured["controller." + property] = str(controller.get(property))
	captured["controller.pending_codex_trust"] = str(controller.has_pending_codex_trust())
	captured["controller.running"] = str(controller.is_running())

	var config := ConfigFile.new()
	if config.load("user://ui_settings.cfg") == OK:
		for section: String in AGENT_SETTINGS_SECTIONS:
			if not config.has_section(section):
				continue
			for key: String in config.get_section_keys(section):
				captured["settings.%s.%s" % [section, key]] = str(
					config.get_value(section, key)
				)

	var runtime_path := _home_root.path_join("profile/.open-desktop-pet/open_desktop_pet_runtime.json")
	if FileAccess.file_exists(runtime_path):
		var runtime: Variant = JSON.parse_string(FileAccess.get_file_as_string(runtime_path))
		if runtime is Dictionary:
			captured["runtime.port"] = str(runtime.get("port"))
			for group: String in ["enabled_targets", "executable_paths"]:
				var values: Dictionary = runtime.get(group, {})
				for key: String in values.keys():
					captured["runtime.%s.%s" % [group, key]] = str(values[key])
	else:
		captured["runtime"] = "missing"

	if not is_instance_valid(_main._stats_window):
		captured["ui"] = "closed"
		return captured
	for toggle_name: String in TOGGLE_NAMES:
		var toggle := _find(toggle_name) as Button
		if toggle == null:
			captured["ui.%s" % toggle_name] = "missing"
			continue
		captured["ui.%s" % toggle_name] = "%s %s disabled=%s" % [
			(toggle.get_parent().get_child(0) as Label).text.strip_edges(),
			toggle.text,
			toggle.disabled,
		]
	var port_spin_box := _find("AgentPortSpinBox") as SpinBox
	captured["ui.port"] = "%d editable=%s" % [int(port_spin_box.value), port_spin_box.editable]
	var status_label := _find("AgentStatusLabel") as Label
	captured["ui.status"] = "%s color=%s" % [
		status_label.text, status_label.get_theme_color("font_color").to_html()
	]
	captured["ui.codex_progress_visible"] = str(
		(_find("CodexSetupProgressBar") as Control).visible
	)
	for button_name: String in ["CodexHookTrustPageReviewButton", "CodexHookTrustRecheckButton"]:
		var button := _find(button_name) as Button
		captured["ui.%s" % button_name] = "visible=%s disabled=%s" % [
			button.visible, button.disabled
		]
	var trust_dialog := _find("CodexHookTrustDialog") as ConfirmationDialog
	captured["ui.trust_dialog_visible"] = str(trust_dialog.visible)
	captured["ui.trust_dialog_text"] = trust_dialog.dialog_text.replace("\n", "\\n")
	for controls: Array in PATH_CONTROLS:
		var line_edit := _find(controls[0]) as LineEdit
		var hint := _find(controls[1]) as Label
		var header_row := line_edit.get_parent().get_child(line_edit.get_index() + 1)
		var summary := header_row.get_child(1) as Label
		captured["ui.%s" % controls[0]] = "text=%s hint=%s summary=%s" % [
			line_edit.text, hint.text, summary.text
		]
	return captured


func _find(node_name: String) -> Node:
	if _main == null or not is_instance_valid(_main._stats_window):
		return null
	return _main._stats_window.find_child(node_name, true, false)


func _tabs() -> TabContainer:
	return _find("DetailsTabs") as TabContainer


func _strip_breaks(text: String) -> String:
	return text.replace(char(0x200B), "")


func _normalize(text: String) -> String:
	return text.replace(_home_root, "<home>")


func _restore_ui_settings() -> void:
	if _had_ui_settings:
		var file := FileAccess.open(UI_SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_previous_ui_settings)
		file.close()
	elif FileAccess.file_exists(UI_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UI_SETTINGS_PATH))


func _finish() -> void:
	_restore_ui_settings()
	var recorded := "\n".join(_output) + "\n"
	if OS.get_environment("ODP_RECORD_AGENT_GOLDEN") == "1":
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(GOLDEN_PATH.get_base_dir())
		)
		var file := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
		file.store_string(recorded)
		file.close()
		print("AGENT_SETTINGS_GOLDEN_RECORDED")
		quit(0)
		return
	if not FileAccess.file_exists(GOLDEN_PATH):
		_fail("missing " + GOLDEN_PATH)
		return
	var expected := FileAccess.get_file_as_string(GOLDEN_PATH).replace("\r\n", "\n")
	if expected != recorded:
		var expected_lines := expected.split("\n")
		var recorded_lines := recorded.split("\n")
		for index in maxi(expected_lines.size(), recorded_lines.size()):
			var expected_line := expected_lines[index] if index < expected_lines.size() else "<end>"
			var recorded_line := recorded_lines[index] if index < recorded_lines.size() else "<end>"
			if expected_line != recorded_line:
				push_error("first difference at line %d" % (index + 1))
				push_error("expected: " + expected_line)
				push_error("actual:   " + recorded_line)
				break
		var actual_path := ProjectSettings.globalize_path(
			"user://agent_settings_golden.actual.txt"
		)
		var actual_file := FileAccess.open(actual_path, FileAccess.WRITE)
		actual_file.store_string(recorded)
		actual_file.close()
		_fail("Agent settings behavior changed; actual output: " + actual_path)
		return
	if _failed:
		return
	print("AGENT_SETTINGS_GOLDEN_TEST_OK")
	quit(0)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_restore_ui_settings()
	push_error("AGENT_SETTINGS_GOLDEN_TEST_FAILED: " + message)
	quit(1)
