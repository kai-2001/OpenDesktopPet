class_name SettingsTabController
extends RefCounted

# Owns the pet settings shown on the settings tab: frame rate, details theme,
# focus mode, keeping the screen awake, pet size, Windows autostart and update
# checks. It loads them at startup and lives for the whole session; the tab
# controls are bound while the details window exists.

const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_TARGET_FPS := 30
const TARGET_FPS_OPTIONS := [15, 30, 60]
const DEFAULT_KEEP_SCREEN_ON := false
const DEFAULT_FOCUS_MODE := false
const UpdateCheckCoordinatorScript = preload("res://scripts/update_check_coordinator.gd")

# Emitted after the details theme is saved; the window must be rebuilt.
signal theme_changed

var theme_mode := "light"
var keep_screen_on := DEFAULT_KEEP_SCREEN_ON
var focus_mode := DEFAULT_FOCUS_MODE
var fps_option_button: OptionButton
var visual_scale_slider: HSlider
var focus_mode_check_box: CheckBox
var keep_screen_on_check_box: CheckBox
var autostart_check_box: CheckBox
var _state: Node
var _pet: Node2D
var _gameplay_coordinator
var _autostart_service
var _update_check_coordinator
var _theme_option_button: OptionButton
var _visual_scale_value_label: Label
var _settings_feedback: Label
var _update_auto_check_box: CheckBox
var _update_status_label: Label
var _update_check_button: Button
var _update_release_page_button: Button
var _update_skip_button: Button


func configure(state: Node, pet: Node2D, gameplay_coordinator) -> void:
	_state = state
	_pet = pet
	_gameplay_coordinator = gameplay_coordinator


func set_autostart_service(service) -> void:
	_autostart_service = service
	_autostart_service.operation_completed.connect(_finish_autostart_operation)


func set_update_check(coordinator) -> void:
	_update_check_coordinator = coordinator
	_update_check_coordinator.state_changed.connect(refresh_update_ui)


func load_runtime_settings() -> void:
	var config := ConfigFile.new()
	var target_fps := DEFAULT_TARGET_FPS
	var saved_keep_screen_on := DEFAULT_KEEP_SCREEN_ON
	var saved_focus_mode := DEFAULT_FOCUS_MODE
	if config.load(UI_SETTINGS_PATH) == OK:
		target_fps = int(config.get_value(
			"performance", "target_fps", DEFAULT_TARGET_FPS
		))
		theme_mode = String(config.get_value(
			"appearance", "details_theme", "light"
		))
		saved_keep_screen_on = bool(config.get_value(
			"power", "keep_screen_on", DEFAULT_KEEP_SCREEN_ON
		))
		saved_focus_mode = bool(config.get_value(
			"behavior", "focus_mode", DEFAULT_FOCUS_MODE
		))
	if theme_mode not in ["light", "dark"]:
		theme_mode = "light"
	Engine.max_fps = _normalize_target_fps(target_fps)
	_apply_keep_screen_on(saved_keep_screen_on)
	_apply_focus_mode(saved_focus_mode)


func is_autostart_supported() -> bool:
	return _autostart_service != null and _autostart_service.is_supported()


func bind(view, refs: Dictionary) -> void:
	view.target_fps_selected.connect(_on_target_fps_selected)
	view.details_theme_selected.connect(_on_theme_selected)
	view.autostart_toggled.connect(_on_autostart_toggled)
	view.keep_screen_on_toggled.connect(_on_keep_screen_on_toggled)
	view.focus_mode_toggled.connect(_on_focus_mode_toggled)
	view.update_auto_check_toggled.connect(_on_update_auto_check_toggled)
	view.update_check_requested.connect(_on_update_check_requested)
	view.update_release_page_requested.connect(_on_update_release_page_requested)
	view.update_skip_requested.connect(_on_update_skip_requested)
	view.visual_scale_previewed.connect(_on_visual_scale_previewed)
	view.visual_scale_changed.connect(_on_visual_scale_changed)
	fps_option_button = refs["fps_option_button"] as OptionButton
	_theme_option_button = refs["details_theme_option_button"] as OptionButton
	visual_scale_slider = refs["visual_scale_slider"] as HSlider
	_visual_scale_value_label = refs["visual_scale_value_label"] as Label
	focus_mode_check_box = refs["focus_mode_check_box"] as CheckBox
	keep_screen_on_check_box = refs["keep_screen_on_check_box"] as CheckBox
	autostart_check_box = refs["autostart_check_box"] as CheckBox
	_settings_feedback = refs["settings_feedback"] as Label
	_update_auto_check_box = refs["update_auto_check_box"] as CheckBox
	_update_status_label = refs["update_status_label"] as Label
	_update_check_button = refs["update_check_button"] as Button
	_update_release_page_button = refs["update_release_page_button"] as Button
	_update_skip_button = refs["update_skip_button"] as Button
	refresh_update_ui()


## The settings view cannot request this before its signals and control
## references exist, so the owner queues it once binding is complete.
func query_autostart() -> void:
	if is_autostart_supported():
		call_deferred("_start_autostart_operation", "query", false)


func unbind() -> void:
	fps_option_button = null
	_theme_option_button = null
	visual_scale_slider = null
	_visual_scale_value_label = null
	focus_mode_check_box = null
	keep_screen_on_check_box = null
	autostart_check_box = null
	_settings_feedback = null
	_update_auto_check_box = null
	_update_status_label = null
	_update_check_button = null
	_update_release_page_button = null
	_update_skip_button = null


func refresh_visual_scale(value: float) -> void:
	if is_instance_valid(visual_scale_slider):
		visual_scale_slider.set_value_no_signal(value)
	if is_instance_valid(_visual_scale_value_label):
		_visual_scale_value_label.text = "%d%%" % roundi(value * 100.0)


func refresh_update_ui() -> void:
	if _update_check_coordinator == null:
		return
	if is_instance_valid(_update_auto_check_box):
		_update_auto_check_box.set_pressed_no_signal(
			_update_check_coordinator.auto_check_enabled
		)
	if is_instance_valid(_update_status_label):
		_update_status_label.text = _update_check_coordinator.status_text()
	var checking: bool = (
		_update_check_coordinator.state == UpdateCheckCoordinatorScript.STATE_CHECKING
	)
	if is_instance_valid(_update_check_button):
		_update_check_button.disabled = checking
	var has_update: bool = _update_check_coordinator.has_update()
	if is_instance_valid(_update_release_page_button):
		_update_release_page_button.visible = has_update
	if is_instance_valid(_update_skip_button):
		_update_skip_button.visible = has_update


func set_target_fps(value: int) -> void:
	var target_fps := _normalize_target_fps(value)
	Engine.max_fps = target_fps
	if is_instance_valid(fps_option_button):
		var target_index := fps_option_button.get_item_index(target_fps)
		if target_index >= 0 and fps_option_button.selected != target_index:
			fps_option_button.select(target_index)
	_save_setting("performance", "target_fps", target_fps)


func _apply_keep_screen_on(enabled: bool) -> void:
	keep_screen_on = enabled
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(enabled)
	if is_instance_valid(keep_screen_on_check_box):
		keep_screen_on_check_box.set_pressed_no_signal(enabled)


func _apply_focus_mode(enabled: bool) -> void:
	focus_mode = enabled
	_state.auto_care_quiet = enabled
	if enabled and _gameplay_coordinator != null:
		_gameplay_coordinator.cancel_autonomous_action()
	if is_instance_valid(focus_mode_check_box):
		focus_mode_check_box.set_pressed_no_signal(enabled)


func _normalize_target_fps(value: int) -> int:
	var nearest: int = TARGET_FPS_OPTIONS[0]
	for candidate: int in TARGET_FPS_OPTIONS:
		if absi(candidate - value) < absi(nearest - value):
			nearest = candidate
	return nearest


func _on_target_fps_selected(index: int) -> void:
	set_target_fps(fps_option_button.get_item_id(index))


func _on_theme_selected(index: int) -> void:
	var requested := "dark" if index == 1 else "light"
	if requested == theme_mode:
		return
	theme_mode = requested
	_save_setting("appearance", "details_theme", theme_mode)
	theme_changed.emit()


func _on_keep_screen_on_toggled(enabled: bool) -> void:
	_apply_keep_screen_on(enabled)
	_save_setting("power", "keep_screen_on", enabled)


func _on_focus_mode_toggled(enabled: bool) -> void:
	_apply_focus_mode(enabled)
	_save_setting("behavior", "focus_mode", enabled)


func _on_visual_scale_previewed(value: float) -> void:
	_pet.set_visual_size(value)


func _on_visual_scale_changed(value: float) -> void:
	_state.set_visual_scale(value)


func _on_update_auto_check_toggled(enabled: bool) -> void:
	if _update_check_coordinator != null:
		_update_check_coordinator.set_auto_check_enabled(enabled)


func _on_update_check_requested() -> void:
	if _update_check_coordinator != null:
		_update_check_coordinator.check_now()


func _on_update_release_page_requested() -> void:
	if _update_check_coordinator == null:
		return
	var url: String = _update_check_coordinator.release_page_url()
	if not url.is_empty():
		OS.shell_open(url)


func _on_update_skip_requested() -> void:
	if _update_check_coordinator != null:
		_update_check_coordinator.skip_latest_version()


func _on_autostart_toggled(enabled: bool) -> void:
	if not is_autostart_supported():
		return
	_start_autostart_operation("set", enabled)


func _start_autostart_operation(operation: String, enabled: bool) -> void:
	if is_instance_valid(autostart_check_box):
		autostart_check_box.disabled = true
	if is_instance_valid(_settings_feedback):
		_settings_feedback.text = (
			"正在讀取 Windows 開機啟動設定…"
			if operation == "query"
			else "正在套用開機啟動設定…"
		)
	if _autostart_service == null:
		_finish_autostart_operation(
			-1, operation, enabled,
			{"exists": false, "matches": false, "success": false}
		)
		return
	if operation == "query":
		_autostart_service.query()
	else:
		_autostart_service.set_enabled(enabled)


func _finish_autostart_operation(
	operation_id: int,
	operation: String,
	enabled: bool,
	result: Dictionary
) -> void:
	# A panel can be closed and recreated while an older registry request is
	# finishing. Only the newest request may update the current controls.
	if _autostart_service != null \
			and operation_id >= 0 \
			and not _autostart_service.is_latest_operation(operation_id):
		return
	if not is_instance_valid(autostart_check_box) \
			or autostart_check_box.is_queued_for_deletion():
		return
	autostart_check_box.disabled = false
	if operation == "query":
		var matches := bool(result.get("matches", false))
		var exists := bool(result.get("exists", false))
		var legacy_matches := bool(result.get("legacy_matches", false))
		autostart_check_box.set_pressed_no_signal(matches)
		if matches:
			_settings_feedback.text = "已設定由目前這個 EXE 隨 Windows 登入啟動。"
		elif legacy_matches:
			# Older builds stored Godot's forward-slash executable path. The
			# entry already expresses the user's autostart preference, so
			# migrate it to a native Windows command automatically.
			_settings_feedback.text = "正在更新舊的開機啟動路徑…"
			_start_autostart_operation("set", true)
		elif exists:
			_settings_feedback.text = "偵測到其他位置的舊設定；重新勾選即可更新。"
		else:
			_settings_feedback.text = "這項設定只套用到目前的 Windows 使用者。"
	elif bool(result.get("success", false)):
		autostart_check_box.set_pressed_no_signal(enabled)
		_settings_feedback.text = (
			"已啟用開機自動啟動。" if enabled else "已關閉開機自動啟動。"
		)
	else:
		autostart_check_box.set_pressed_no_signal(not enabled)
		_settings_feedback.text = "設定失敗，請稍後再試。"


func _save_setting(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value(section, key, value)
	config.save(UI_SETTINGS_PATH)
