extends SceneTree

# The autostart query answers asynchronously from the Windows registry. It
# must only start once the settings tab controls exist, otherwise its result
# has no checkbox to update and the checkbox stays disabled.

const SettingsTabControllerScript = preload("res://scripts/settings_tab_controller.gd")
const PetStateScript = preload("res://scripts/pet_state.gd")


class FakeAutostartService:
	extends RefCounted

	signal operation_completed(
		operation_id: int, operation: String, enabled: bool, result: Dictionary
	)

	var operations: Array[String] = []

	func is_supported() -> bool:
		return true

	func is_latest_operation(_operation_id: int) -> bool:
		return true

	func query() -> void:
		operations.append("query")
		operation_completed.emit(
			operations.size(), "query", false, {"exists": true, "matches": true}
		)

	func set_enabled(enabled: bool) -> void:
		operations.append("set %s" % enabled)
		operation_completed.emit(operations.size(), "set", enabled, {"success": true})


class FakeView:
	extends RefCounted

	signal target_fps_selected(index: int)
	signal details_theme_selected(index: int)
	signal autostart_toggled(enabled: bool)
	signal keep_screen_on_toggled(enabled: bool)
	signal focus_mode_toggled(enabled: bool)
	signal update_auto_check_toggled(enabled: bool)
	signal update_check_requested
	signal update_release_page_requested
	signal update_skip_requested
	signal visual_scale_previewed(value: float)
	signal visual_scale_changed(value: float)


var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := PetStateScript.new()
	var service := FakeAutostartService.new()
	var controller = SettingsTabControllerScript.new()
	controller.configure(state, null, null)
	controller.set_autostart_service(service)

	var host := Node.new()
	root.add_child(host)
	var refs := {
		"fps_option_button": OptionButton.new(),
		"details_theme_option_button": OptionButton.new(),
		"visual_scale_slider": HSlider.new(),
		"visual_scale_value_label": Label.new(),
		"focus_mode_check_box": CheckBox.new(),
		"keep_screen_on_check_box": CheckBox.new(),
		"autostart_check_box": CheckBox.new(),
		"settings_feedback": Label.new(),
		"update_auto_check_box": CheckBox.new(),
		"update_status_label": Label.new(),
		"update_check_button": Button.new(),
		"update_release_page_button": Button.new(),
		"update_skip_button": Button.new(),
	}
	for control: Control in refs.values():
		host.add_child(control)
	var autostart_check_box := refs["autostart_check_box"] as CheckBox
	autostart_check_box.disabled = true

	var view := FakeView.new()
	controller.bind(view, refs)
	controller.query_autostart()
	_assert_true(service.operations.is_empty(), "the query waits until binding finishes")
	await process_frame
	_assert_true(service.operations == ["query"], "the query runs once after binding")
	_assert_true(not autostart_check_box.disabled, "the query result re-enables the checkbox")
	_assert_true(autostart_check_box.button_pressed, "the query result shows the saved state")
	_assert_true(
		(refs["settings_feedback"] as Label).text.contains("已設定"),
		"the query result explains the saved state"
	)

	view.autostart_toggled.emit(false)
	_assert_true(service.operations[-1] == "set false", "the checkbox changes the setting")
	_assert_true(not autostart_check_box.button_pressed, "the checkbox shows the new state")

	controller.unbind()
	host.free()
	state.free()
	if _failed:
		return
	print("SETTINGS_TAB_CONTROLLER_TEST_OK")
	quit(0)


func _assert_true(value: bool, message: String) -> void:
	if value or _failed:
		return
	_failed = true
	push_error("SETTINGS_TAB_CONTROLLER_TEST_FAILED: " + message)
	quit(1)
