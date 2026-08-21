class_name DetailsWindowController
extends RefCounted

const AgentIntegrationControllerScript = preload("res://scripts/agent_integration_controller.gd")
const SettingsToggleSwitchScript = preload("res://scripts/settings_toggle_switch.gd")
const PetVisualScaleScript = preload("res://scripts/pet_visual_scale.gd")
const TaskReminderPanelScript = preload("res://scripts/task_reminder_panel.gd")
const TARGET_FPS_OPTIONS := [15, 30, 60]

signal care_action_requested(action: String)
signal close_requested
signal target_fps_selected(index: int)
signal details_theme_selected(index: int)
signal agent_codex_enabled_toggled(enabled: bool)
signal agent_codex_app_enabled_toggled(enabled: bool)
signal agent_terminal_codex_enabled_toggled(enabled: bool)
signal agent_terminal_opencode_enabled_toggled(enabled: bool)
signal agent_vscode_opencode_enabled_toggled(enabled: bool)
signal agent_opencode_app_enabled_toggled(enabled: bool)
signal agent_copilot_enabled_toggled(enabled: bool)
signal agent_claude_vscode_enabled_toggled(enabled: bool)
signal agent_claude_app_enabled_toggled(enabled: bool)
signal agent_claude_terminal_enabled_toggled(enabled: bool)
signal agent_gemini_terminal_enabled_toggled(enabled: bool)
signal agent_agy_terminal_enabled_toggled(enabled: bool)
signal agent_port_changed(value: float)
signal codex_trust_review_requested
signal codex_trust_recheck_requested
signal vscode_executable_path_changed(path: String)
signal codex_app_executable_path_changed(path: String)
signal terminal_executable_path_changed(path: String)
signal opencode_app_executable_path_changed(path: String)
signal claude_app_executable_path_changed(path: String)
signal autostart_toggled(enabled: bool)
signal keep_screen_on_toggled(enabled: bool)
signal focus_mode_toggled(enabled: bool)
signal visual_scale_previewed(value: float)
signal visual_scale_changed(value: float)
signal character_selected(index: int)
signal character_use_requested
signal character_delete_requested
signal character_import_requested
signal open_character_packs_folder_requested
signal character_archive_selected(path: String)
signal character_update_confirmed
signal character_delete_confirmed
signal mask_effect_changed(anchor: Vector2, scale: float)
signal mask_effect_toggle_requested
signal mask_effect_apply_requested
signal mask_effect_reset_requested

var theme_mode := "light"
var last_state_message := "尚無紀錄"
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
var agent_port := AgentIntegrationControllerScript.DEFAULT_PORT
var vscode_executable_path := ""
var codex_app_executable_path := ""
var terminal_executable_path := ""
var opencode_app_executable_path := ""
var claude_app_executable_path := ""
var autostart_supported := false
var keep_screen_on := false
var focus_mode := false
var visual_scale := PetVisualScaleScript.DEFAULT_VALUE
var interaction_label: Callable
var interaction_icon: Callable
var stats_bars: Dictionary = {}
var _agent_executable_path_summaries: Dictionary = {}
var _task_reminder_panel


func build_status_tab(tabs: TabContainer) -> Dictionary:
	stats_bars.clear()
	var scroll := ScrollContainer.new()
	scroll.name = "狀態"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title: Label = _new_label(
		"養成狀態", 24, _details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var stats_status: Label = _new_label(
		"", 15, _details_color("#238b9d", "#4fc1ff")
	)
	stats_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(stats_status)

	var companion_status: Label = _new_label(
		"", 14, _details_color("#6f65a8", "#c8a7ff")
	)
	companion_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	companion_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(companion_status)

	var wish_status: Label = _new_label(
		"", 15, _details_color("#a66b16", "#dcdcaa")
	)
	wish_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wish_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(wish_status)

	content.add_child(HSeparator.new())
	_add_stat_row(content, "飽食", "hunger", Color("#efa64a"))
	_add_stat_row(content, "水分", "thirst", Color("#55b7df"))
	_add_stat_row(content, "體力", "energy", Color("#69c986"))
	_add_stat_row(content, "心情", "mood", Color("#e97ca6"))
	_add_stat_row(content, "親密", "affection", Color("#9a83d2"))

	var unlock_status: Label = _new_label(
		"", 14, _details_color("#6f65a8", "#c8a7ff")
	)
	unlock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(unlock_status)

	var last_message_status: Label = _new_label(
		"最近訊息：%s" % last_state_message,
		13,
		_details_color("#68747a", "#9da1a6")
	)
	last_message_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_message_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(last_message_status)
	content.add_child(HSeparator.new())

	var action_title: Label = _new_label(
		"照顧操作", 16, _details_color("#30383c", "#d4d4d4")
	)
	action_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(action_title)

	var action_grid := HFlowContainer.new()
	action_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	action_grid.add_theme_constant_override("h_separation", 7)
	action_grid.add_theme_constant_override("v_separation", 7)
	var care_action_buttons: Dictionary = {}
	var panel_actions: Array[Dictionary] = [
		{"action": "feed", "id": 1},
		{"action": "water", "id": 2},
		{"action": "pet", "id": 3},
		{"action": "work", "id": 4},
		{"action": "sleep", "id": 5},
	]
	for definition: Dictionary in panel_actions:
		var action := String(definition.action)
		var action_button := Button.new()
		action_button.text = "%s %s" % [
			_interaction_icon(action), _interaction_label(action)
		]
		action_button.custom_minimum_size = Vector2(100, 38)
		action_button.pressed.connect(
			func() -> void: care_action_requested.emit(action)
		)
		action_grid.add_child(action_button)
		care_action_buttons[action] = action_button
	content.add_child(action_grid)
	content.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "關閉詳細狀態"
	close_button.custom_minimum_size.y = 40
	close_button.pressed.connect(func() -> void: close_requested.emit())
	content.add_child(close_button)

	return {
		"stats_status": stats_status,
		"companion_status": companion_status,
		"wish_status": wish_status,
		"unlock_status": unlock_status,
		"last_message_status": last_message_status,
		"care_action_buttons": care_action_buttons,
		"stats_bars": stats_bars,
	}


func build_reminders_tab(tabs: TabContainer, reminder_coordinator) -> Dictionary:
	var reminders_scroll := ScrollContainer.new()
	reminders_scroll.name = "待辦"
	reminders_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(reminders_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	reminders_scroll.add_child(margin)

	_task_reminder_panel = TaskReminderPanelScript.new()
	_task_reminder_panel.configure(reminder_coordinator, theme_mode)
	margin.add_child(_task_reminder_panel)
	return {
		"reminder_tab_index": reminders_scroll.get_index(),
		"reminder_panel": _task_reminder_panel,
	}


func focus_reminder(reminder_id: String) -> void:
	if is_instance_valid(_task_reminder_panel):
		_task_reminder_panel.focus_reminder(reminder_id)


func start_new_reminder() -> void:
	if is_instance_valid(_task_reminder_panel):
		_task_reminder_panel.show_new_form()


func build_settings_tab(tabs: TabContainer) -> Dictionary:
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "設定"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(settings_scroll)

	var settings_margin := MarginContainer.new()
	settings_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_margin.add_theme_constant_override("margin_left", 24)
	settings_margin.add_theme_constant_override("margin_top", 20)
	settings_margin.add_theme_constant_override("margin_right", 24)
	settings_margin.add_theme_constant_override("margin_bottom", 20)
	settings_scroll.add_child(settings_margin)

	var settings_content := VBoxContainer.new()
	settings_content.add_theme_constant_override("separation", 16)
	settings_margin.add_child(settings_content)

	var settings_title: Label = _new_label(
		"桌寵設定", 24, _details_color("#20272b", "#f0f0f0")
	)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(settings_title)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label: Label = _new_label(
		"桌寵幀率（FPS）", 16, _details_color("#30383c", "#d4d4d4")
	)
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	var fps_option_button := OptionButton.new()
	for fps: int in TARGET_FPS_OPTIONS:
		fps_option_button.add_item("%d FPS" % fps, fps)
	fps_option_button.select(fps_option_button.get_item_index(Engine.max_fps))
	fps_option_button.custom_minimum_size = Vector2(120, 40)
	fps_option_button.item_selected.connect(
		func(index: int) -> void: target_fps_selected.emit(index)
	)
	fps_row.add_child(fps_option_button)
	settings_content.add_child(fps_row)

	var fps_hint: Label = _new_label(
		"控制整個桌寵的更新率（15–60）；30 FPS 適合日常使用，降低可省電。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	fps_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(fps_hint)
	settings_content.add_child(HSeparator.new())

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	var theme_label: Label = _new_label(
		"詳細面板主題", 16, _details_color("#30383c", "#d4d4d4")
	)
	theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_label)
	var details_theme_option_button := OptionButton.new()
	details_theme_option_button.add_item("淺色", 0)
	details_theme_option_button.add_item("深色", 1)
	details_theme_option_button.select(
		1 if theme_mode == "dark" else 0
	)
	details_theme_option_button.custom_minimum_size = Vector2(120, 40)
	details_theme_option_button.item_selected.connect(
		func(index: int) -> void: details_theme_selected.emit(index)
	)
	theme_row.add_child(details_theme_option_button)
	settings_content.add_child(theme_row)

	var theme_hint: Label = _new_label(
		"切換詳細面板的完整配色；設定會自動保存。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	settings_content.add_child(theme_hint)
	settings_content.add_child(HSeparator.new())

	var visual_scale_content := VBoxContainer.new()
	visual_scale_content.add_theme_constant_override("separation", 8)

	var visual_scale_value_label: Label = _new_label(
		"100%", 15, _details_color("#238b9d", "#4fc1ff")
	)
	visual_scale_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visual_scale_value_label.custom_minimum_size.x = 64
	visual_scale_value_label.text = "%d%%" % roundi(visual_scale * 100.0)
	var visual_scale_label: Label = _new_label(
		"桌寵大小", 16, _details_color("#30383c", "#d4d4d4")
	)
	visual_scale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var visual_scale_row := HBoxContainer.new()
	visual_scale_row.add_theme_constant_override("separation", 12)
	visual_scale_row.mouse_filter = Control.MOUSE_FILTER_PASS
	visual_scale_row.add_child(visual_scale_label)
	visual_scale_row.add_child(visual_scale_value_label)

	var visual_scale_slider := HSlider.new()
	visual_scale_slider.name = "VisualScaleSlider"
	visual_scale_slider.min_value = PetVisualScaleScript.MIN_VALUE
	visual_scale_slider.max_value = PetVisualScaleScript.MAX_VALUE
	visual_scale_slider.step = PetVisualScaleScript.STEP
	visual_scale_slider.value = visual_scale
	visual_scale_slider.scrollable = false
	visual_scale_slider.custom_minimum_size = Vector2(0, 32)
	visual_scale_slider.tooltip_text = "調整桌寵顯示大小"
	var visual_scale_track := StyleBoxFlat.new()
	visual_scale_track.bg_color = _details_color("#dce5e7", "#3a4145")
	visual_scale_track.set_corner_radius_all(5)
	visual_scale_track.content_margin_top = 5
	visual_scale_track.content_margin_bottom = 5
	var visual_scale_area := StyleBoxFlat.new()
	visual_scale_area.bg_color = _details_color("#08a6b5", "#35a9bd")
	visual_scale_area.set_corner_radius_all(5)
	visual_scale_area.content_margin_top = 5
	visual_scale_area.content_margin_bottom = 5
	var visual_scale_area_highlight := StyleBoxFlat.new()
	visual_scale_area_highlight.bg_color = _details_color("#087f8b", "#4fc1ff")
	visual_scale_area_highlight.set_corner_radius_all(5)
	visual_scale_area_highlight.content_margin_top = 5
	visual_scale_area_highlight.content_margin_bottom = 5
	var visual_scale_theme := Theme.new()
	visual_scale_theme.set_stylebox("slider", "HSlider", visual_scale_track)
	visual_scale_theme.set_stylebox("grabber_area", "HSlider", visual_scale_area)
	visual_scale_theme.set_stylebox(
		"grabber_area_highlight", "HSlider", visual_scale_area_highlight
	)
	visual_scale_theme.set_icon(
		"grabber", "HSlider", _create_slider_grabber_texture(false)
	)
	visual_scale_theme.set_icon(
		"grabber_highlight", "HSlider", _create_slider_grabber_texture(true)
	)
	visual_scale_theme.set_constant("center_grabber", "HSlider", 1)
	visual_scale_slider.theme = visual_scale_theme
	var visual_scale_commit_timer := Timer.new()
	visual_scale_commit_timer.one_shot = true
	visual_scale_commit_timer.wait_time = 0.2
	visual_scale_slider.add_child(visual_scale_commit_timer)
	visual_scale_commit_timer.timeout.connect(
		func() -> void: visual_scale_changed.emit(visual_scale_slider.value)
	)
	visual_scale_slider.value_changed.connect(
		func(value: float) -> void:
			visual_scale_value_label.text = "%d%%" % roundi(value * 100.0)
			visual_scale_previewed.emit(value)
			visual_scale_commit_timer.start()
	)
	visual_scale_slider.gui_input.connect(
		_handle_visual_scale_wheel.bind(visual_scale_slider)
	)
	visual_scale_content.add_child(visual_scale_row)
	visual_scale_content.add_child(visual_scale_slider)

	var visual_scale_hint: Label = _new_label(
		"可調整為原始顯示大小的 %d%%–%d%%；設定會保存。" % [
			roundi(PetVisualScaleScript.MIN_VALUE * 100.0),
			roundi(PetVisualScaleScript.MAX_VALUE * 100.0),
		],
		13,
		_details_color("#68747a", "#9da1a6")
	)
	visual_scale_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visual_scale_content.add_child(visual_scale_hint)
	settings_content.add_child(visual_scale_content)
	settings_content.add_child(HSeparator.new())

	var focus_mode_check_box := CheckBox.new()
	focus_mode_check_box.text = "專注模式（不自主移動或做動作）"
	focus_mode_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(focus_mode_check_box)
	focus_mode_check_box.custom_minimum_size = Vector2(0, 40)
	focus_mode_check_box.button_pressed = focus_mode
	focus_mode_check_box.toggled.connect(
		func(enabled: bool) -> void: focus_mode_toggled.emit(enabled)
	)
	settings_content.add_child(focus_mode_check_box)

	var focus_mode_hint: Label = _new_label(
		"開啟後會停止桌寵自主移動、吃飯、喝水、睡覺與其他自主動作；手動操作仍可使用。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	focus_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(focus_mode_hint)
	settings_content.add_child(HSeparator.new())

	var keep_screen_on_check_box := CheckBox.new()
	keep_screen_on_check_box.text = "保持螢幕喚醒（阻止系統休眠）"
	keep_screen_on_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(keep_screen_on_check_box)
	keep_screen_on_check_box.custom_minimum_size = Vector2(0, 40)
	keep_screen_on_check_box.button_pressed = keep_screen_on
	keep_screen_on_check_box.toggled.connect(
		func(enabled: bool) -> void: keep_screen_on_toggled.emit(enabled)
	)
	settings_content.add_child(keep_screen_on_check_box)

	var keep_screen_on_hint: Label = _new_label(
		"開啟後會要求 Windows 保持螢幕喚醒；關閉後恢復系統電源計畫。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	keep_screen_on_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(keep_screen_on_hint)
	settings_content.add_child(HSeparator.new())

	var autostart_check_box := CheckBox.new()
	autostart_check_box.text = "登入 Windows 時自動開啟桌寵"
	autostart_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(autostart_check_box)
	autostart_check_box.custom_minimum_size = Vector2(0, 40)
	autostart_check_box.button_pressed = false
	autostart_check_box.disabled = true
	autostart_check_box.toggled.connect(
		func(enabled: bool) -> void: autostart_toggled.emit(enabled)
	)
	settings_content.add_child(autostart_check_box)

	var settings_feedback: Label = _new_label(
		"請使用打包版設定開機啟動。"
		if not autostart_supported
		else "正在讀取 Windows 開機啟動設定…",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(settings_feedback)
	if not autostart_supported:
		settings_feedback.text = "目前平台不支援 Windows 開機啟動設定。"

	var settings_close_button := Button.new()
	settings_close_button.text = "關閉詳細面板"
	settings_close_button.custom_minimum_size.y = 42
	settings_close_button.pressed.connect(func() -> void: close_requested.emit())
	settings_content.add_child(settings_close_button)

	return {
		"fps_option_button": fps_option_button,
		"details_theme_option_button": details_theme_option_button,
		"visual_scale_slider": visual_scale_slider,
		"visual_scale_value_label": visual_scale_value_label,
		"focus_mode_check_box": focus_mode_check_box,
		"keep_screen_on_check_box": keep_screen_on_check_box,
		"autostart_check_box": autostart_check_box,
		"settings_feedback": settings_feedback,
	}


func build_agent_tab(tabs: TabContainer) -> Dictionary:
	var agent_scroll := ScrollContainer.new()
	agent_scroll.name = "Agent通知"
	agent_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(agent_scroll)

	var agent_margin := MarginContainer.new()
	agent_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_margin.add_theme_constant_override("margin_left", 24)
	agent_margin.add_theme_constant_override("margin_top", 20)
	agent_margin.add_theme_constant_override("margin_right", 24)
	agent_margin.add_theme_constant_override("margin_bottom", 20)
	agent_scroll.add_child(agent_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	agent_margin.add_child(content)
	var title: Label = _new_label(
		"Agent 通知", 24, _details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	var port_title: Label = _new_label(
		"Agent 通知", 16, _details_color("#30383c", "#d4d4d4")
	)
	port_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(port_title)
	port_row.add_child(_new_label(
		"通訊埠", 14, _details_color("#68747a", "#9da1a6")
	))
	var port_spin_box := SpinBox.new()
	port_spin_box.name = "AgentPortSpinBox"
	port_spin_box.min_value = AgentIntegrationControllerScript.MIN_PORT
	port_spin_box.max_value = AgentIntegrationControllerScript.MAX_PORT
	port_spin_box.step = 1
	port_spin_box.value = agent_port
	port_spin_box.custom_minimum_size = Vector2(120, 40)
	port_spin_box.tooltip_text = "所有 Agent 共用的桌寵本機通訊埠"
	_style_spin_box(port_spin_box)
	port_spin_box.value_changed.connect(
		func(value: float) -> void: agent_port_changed.emit(value)
	)
	port_row.add_child(port_spin_box)
	content.add_child(port_row)

	var status_label: Label = _new_label(
		"", 14, _details_color("#238b9d", "#4fc1ff")
	)
	status_label.name = "AgentStatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)
	var codex_setup_progress := ProgressBar.new()
	codex_setup_progress.name = "CodexSetupProgressBar"
	codex_setup_progress.custom_minimum_size.y = 5
	codex_setup_progress.show_percentage = false
	codex_setup_progress.indeterminate = true
	codex_setup_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	codex_setup_progress.visible = false
	content.add_child(codex_setup_progress)
	var codex_trust_review_button := Button.new()
	codex_trust_review_button.name = "CodexHookTrustPageReviewButton"
	codex_trust_review_button.text = "開啟 Codex 信任畫面"
	codex_trust_review_button.tooltip_text = "前往 Codex 檢視並信任桌寵的 Stop Hook"
	codex_trust_review_button.custom_minimum_size.y = 40
	codex_trust_review_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	codex_trust_review_button.visible = false
	codex_trust_review_button.pressed.connect(
		func() -> void: codex_trust_review_requested.emit()
	)
	var codex_trust_recheck_button := Button.new()
	codex_trust_recheck_button.name = "CodexHookTrustRecheckButton"
	codex_trust_recheck_button.text = "我已信任，檢查通知"
	codex_trust_recheck_button.tooltip_text = "檢查桌寵的 Codex Stop Hook 是否已受信任"
	codex_trust_recheck_button.custom_minimum_size.y = 40
	codex_trust_recheck_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	codex_trust_recheck_button.visible = false
	codex_trust_recheck_button.pressed.connect(
		func() -> void: codex_trust_recheck_requested.emit()
	)
	var codex_trust_actions := HBoxContainer.new()
	codex_trust_actions.add_theme_constant_override("separation", 10)
	codex_trust_actions.add_child(codex_trust_review_button)
	codex_trust_actions.add_child(codex_trust_recheck_button)
	content.add_child(codex_trust_actions)
	var codex_trust_dialog := ConfirmationDialog.new()
	codex_trust_dialog.name = "CodexHookTrustDialog"
	codex_trust_dialog.title = "信任 Codex 通知 Hook"
	codex_trust_dialog.dialog_text = (
		"Codex 必須先信任桌寵的 Stop Hook，通知才會生效。\n\n"
		+ "1. 按「開啟 Codex 信任畫面」。\n"
		+ "2. 在 PowerShell 選 1. Review hooks，再按 Enter；這一步只會開啟 Hook 清單。\n"
		+ "3. 在 Hook 清單選取 Stop，再按 Enter 開啟詳細內容。\n"
		+ "4. 找到 Open Desktop Pet 的 Hook，將核取狀態切換為 [x]。"
		+ "[ ] 表示尚未信任；顯示 [x] 才算完成信任。\n"
		+ "5. 按 Esc 返回 Hook 清單；若仍在審查畫面，再按一次 Esc 離開。\n"
		+ "6. 回到桌寵，按「我已信任，檢查通知」。\n\n"
		+ "選 2 會信任所有待審 Hook；選 3 不會信任，通知也不會啟用。\n\n"
		+ "不需另外安裝 CLI；桌寵會使用已安裝 Codex 產品提供的核心。\n\n"
		+ "審查選單會顯示在「Codex Hook Review」PowerShell 視窗，"
		+ "不會出現在 GPT Codex 或 VS Code 面板裡。"
	)
	codex_trust_dialog.ok_button_text = "開啟 Codex 信任畫面"
	codex_trust_dialog.cancel_button_text = "稍後"
	agent_scroll.add_child(codex_trust_dialog)
	content.add_child(HSeparator.new())

	var vscode_controls := _build_executable_path_controls(
		content,
		agent_scroll,
		vscode_executable_path,
		"VscodeExecutablePath",
		"VscodeExecutableBrowseButton",
		"VscodeExecutableHint",
		"VS Code",
		"選擇 Code.exe",
		"選擇 VS Code 執行檔",
		"VS Code",
		true,
		func(path: String) -> void: vscode_executable_path_changed.emit(path)
	)
	var vscode_path_line_edit := vscode_controls["line_edit"] as LineEdit

	var codex_toggle := SettingsToggleSwitchScript.new()
	codex_toggle.name = "CodexEnabledToggle"
	codex_toggle.tooltip_text = "開啟或關閉 VS Code 中的 Codex 通知"
	codex_toggle.configure(theme_mode, codex_enabled)
	codex_toggle.toggled.connect(
		func(value: bool) -> void: agent_codex_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Codex", codex_toggle))

	var claude_vscode_toggle := SettingsToggleSwitchScript.new()
	claude_vscode_toggle.name = "ClaudeCodeVscodeEnabledToggle"
	claude_vscode_toggle.tooltip_text = "開啟或關閉 VS Code 中的 Claude Code 通知"
	claude_vscode_toggle.configure(theme_mode, claude_vscode_enabled)
	claude_vscode_toggle.toggled.connect(
		func(value: bool) -> void: agent_claude_vscode_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Claude Code", claude_vscode_toggle))

	var copilot_toggle := SettingsToggleSwitchScript.new()
	copilot_toggle.name = "CopilotEnabledToggle"
	copilot_toggle.tooltip_text = "開啟或關閉 Copilot Agent 通知"
	copilot_toggle.configure(theme_mode, copilot_enabled)
	copilot_toggle.toggled.connect(
		func(value: bool) -> void: agent_copilot_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Copilot", copilot_toggle))

	var vscode_opencode_toggle := SettingsToggleSwitchScript.new()
	vscode_opencode_toggle.name = "VscodeOpenCodeEnabledToggle"
	vscode_opencode_toggle.tooltip_text = "開啟或關閉 VS Code 中的 OpenCode 通知"
	vscode_opencode_toggle.configure(theme_mode, vscode_opencode_enabled)
	vscode_opencode_toggle.toggled.connect(
		func(value: bool) -> void: agent_vscode_opencode_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("OpenCode", vscode_opencode_toggle))

	content.add_child(HSeparator.new())
	var codex_app_controls := _build_executable_path_controls(
		content,
		agent_scroll,
		codex_app_executable_path,
		"CodexAppExecutablePath",
		"CodexAppExecutableBrowseButton",
		"CodexAppExecutableHint",
		"ChatGPT",
		"選擇 ChatGPT.exe",
		"選擇 ChatGPT 執行檔",
		"ChatGPT",
		true,
		func(path: String) -> void: codex_app_executable_path_changed.emit(path)
	)
	var codex_app_toggle := SettingsToggleSwitchScript.new()
	codex_app_toggle.name = "CodexAppEnabledToggle"
	codex_app_toggle.tooltip_text = "開啟或關閉 ChatGPT 中的 Codex 通知"
	codex_app_toggle.configure(theme_mode, codex_app_enabled)
	codex_app_toggle.toggled.connect(
		func(value: bool) -> void: agent_codex_app_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Codex", codex_app_toggle))

	content.add_child(HSeparator.new())
	var opencode_app_controls := _build_executable_path_controls(
		content,
		agent_scroll,
		opencode_app_executable_path,
		"OpenCodeAppExecutablePath",
		"OpenCodeAppExecutableBrowseButton",
		"OpenCodeAppExecutableHint",
		"OpenCode",
		"選擇 OpenCode Desktop.exe",
		"選擇 OpenCode Desktop 執行檔",
		"OpenCode",
		false,
		func(path: String) -> void: opencode_app_executable_path_changed.emit(path)
	)
	var opencode_app_toggle := SettingsToggleSwitchScript.new()
	opencode_app_toggle.name = "OpenCodeAppEnabledToggle"
	opencode_app_toggle.tooltip_text = "開啟或關閉 OpenCode Desktop 通知"
	opencode_app_toggle.configure(theme_mode, opencode_app_enabled)
	opencode_app_toggle.toggled.connect(
		func(value: bool) -> void: agent_opencode_app_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("OpenCode", opencode_app_toggle))

	content.add_child(HSeparator.new())
	var claude_app_controls := _build_executable_path_controls(
		content,
		agent_scroll,
		claude_app_executable_path,
		"ClaudeAppExecutablePath",
		"ClaudeAppExecutableBrowseButton",
		"ClaudeAppExecutableHint",
		"Claude",
		"選擇 Claude.exe",
		"選擇 Claude Code 執行檔",
		"Claude",
		false,
		func(path: String) -> void: claude_app_executable_path_changed.emit(path)
	)
	var claude_app_toggle := SettingsToggleSwitchScript.new()
	claude_app_toggle.name = "ClaudeDesktopEnabledToggle"
	claude_app_toggle.tooltip_text = "開啟或關閉 Claude Desktop Code 通知"
	claude_app_toggle.configure(theme_mode, claude_app_enabled)
	claude_app_toggle.toggled.connect(
		func(value: bool) -> void: agent_claude_app_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Claude Code", claude_app_toggle))

	content.add_child(HSeparator.new())
	var terminal_controls := _build_executable_path_controls(
		content,
		agent_scroll,
		terminal_executable_path,
		"TerminalExecutablePath",
		"TerminalExecutableBrowseButton",
		"TerminalExecutableHint",
		"終端機",
		"選擇 WindowsTerminal.exe",
		"選擇終端機執行檔",
		"終端機",
		false,
		func(path: String) -> void: terminal_executable_path_changed.emit(path)
	)
	var terminal_toggle := SettingsToggleSwitchScript.new()
	terminal_toggle.name = "TerminalCodexEnabledToggle"
	terminal_toggle.tooltip_text = "開啟或關閉終端機中的 Codex CLI 通知"
	terminal_toggle.configure(theme_mode, terminal_codex_enabled)
	terminal_toggle.toggled.connect(
		func(value: bool) -> void: agent_terminal_codex_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Codex", terminal_toggle))

	var opencode_toggle := SettingsToggleSwitchScript.new()
	opencode_toggle.name = "TerminalOpenCodeEnabledToggle"
	opencode_toggle.tooltip_text = "開啟或關閉終端機中的 OpenCode 通知"
	opencode_toggle.configure(theme_mode, terminal_opencode_enabled)
	opencode_toggle.toggled.connect(
		func(value: bool) -> void: agent_terminal_opencode_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("OpenCode", opencode_toggle))

	var gemini_terminal_toggle := SettingsToggleSwitchScript.new()
	gemini_terminal_toggle.name = "GeminiCliTerminalEnabledToggle"
	gemini_terminal_toggle.tooltip_text = "開啟或關閉終端機中的 Gemini CLI 舊版通知（企業/API Key）"
	gemini_terminal_toggle.configure(theme_mode, gemini_terminal_enabled)
	gemini_terminal_toggle.toggled.connect(
		func(value: bool) -> void: agent_gemini_terminal_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Gemini CLI（舊版）", gemini_terminal_toggle))

	var agy_terminal_toggle := SettingsToggleSwitchScript.new()
	agy_terminal_toggle.name = "AgyTerminalEnabledToggle"
	agy_terminal_toggle.tooltip_text = "開啟或關閉終端機中的 Antigravity CLI 通知"
	agy_terminal_toggle.configure(theme_mode, agy_terminal_enabled)
	agy_terminal_toggle.toggled.connect(
		func(value: bool) -> void: agent_agy_terminal_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Antigravity CLI", agy_terminal_toggle))

	var claude_terminal_toggle := SettingsToggleSwitchScript.new()
	claude_terminal_toggle.name = "ClaudeCodeTerminalEnabledToggle"
	claude_terminal_toggle.tooltip_text = "開啟或關閉終端機中的 Claude Code 通知"
	claude_terminal_toggle.configure(theme_mode, claude_terminal_enabled)
	claude_terminal_toggle.toggled.connect(
		func(value: bool) -> void: agent_claude_terminal_enabled_toggled.emit(value)
	)
	content.add_child(_build_agent_row("Claude Code", claude_terminal_toggle))
	_agent_executable_path_summaries = {
		AgentIntegrationControllerScript.TARGET_VSCODE:
			vscode_controls["summary"] as Label,
		AgentIntegrationControllerScript.TARGET_CODEX_APP:
			codex_app_controls["summary"] as Label,
		AgentIntegrationControllerScript.TARGET_OPENCODE_APP:
			opencode_app_controls["summary"] as Label,
		AgentIntegrationControllerScript.TARGET_CLAUDE_APP:
			claude_app_controls["summary"] as Label,
		AgentIntegrationControllerScript.TARGET_TERMINAL:
			terminal_controls["summary"] as Label,
	}

	var vscode_close_button := Button.new()
	vscode_close_button.text = "關閉詳細面板"
	vscode_close_button.custom_minimum_size.y = 42
	vscode_close_button.pressed.connect(func() -> void: close_requested.emit())
	content.add_child(vscode_close_button)

	return {
		"agent_port_spin_box": port_spin_box,
		"agent_status_label": status_label,
		"codex_setup_progress_bar": codex_setup_progress,
		"codex_trust_review_button": codex_trust_review_button,
		"codex_trust_recheck_button": codex_trust_recheck_button,
		"codex_trust_dialog": codex_trust_dialog,
		"codex_enabled_toggle": codex_toggle,
		"copilot_enabled_toggle": copilot_toggle,
		"vscode_opencode_enabled_toggle": vscode_opencode_toggle,
		"codex_app_enabled_toggle": codex_app_toggle,
		"opencode_app_enabled_toggle": opencode_app_toggle,
		"terminal_codex_enabled_toggle": terminal_toggle,
		"terminal_opencode_enabled_toggle": opencode_toggle,
		"gemini_terminal_enabled_toggle": gemini_terminal_toggle,
		"agy_terminal_enabled_toggle": agy_terminal_toggle,
		"claude_vscode_enabled_toggle": claude_vscode_toggle,
		"claude_app_enabled_toggle": claude_app_toggle,
		"claude_terminal_enabled_toggle": claude_terminal_toggle,
		"vscode_executable_line_edit": vscode_path_line_edit,
		"vscode_executable_hint": vscode_controls["hint"] as Label,
		"vscode_executable_summary": vscode_controls["summary"] as Label,
		"codex_app_executable_line_edit": codex_app_controls["line_edit"] as LineEdit,
		"codex_app_executable_hint": codex_app_controls["hint"] as Label,
		"codex_app_executable_summary": codex_app_controls["summary"] as Label,
		"opencode_app_executable_line_edit": opencode_app_controls["line_edit"] as LineEdit,
		"opencode_app_executable_hint": opencode_app_controls["hint"] as Label,
		"opencode_app_executable_summary": opencode_app_controls["summary"] as Label,
		"claude_app_executable_line_edit": claude_app_controls["line_edit"] as LineEdit,
		"claude_app_executable_hint": claude_app_controls["hint"] as Label,
		"claude_app_executable_summary": claude_app_controls["summary"] as Label,
		"terminal_executable_line_edit": terminal_controls["line_edit"] as LineEdit,
		"terminal_executable_hint": terminal_controls["hint"] as Label,
		"terminal_executable_summary": terminal_controls["summary"] as Label,
	}


func _build_agent_row(title_text: String, toggle: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = _new_label(
		"　" + title_text, 16, _details_color("#30383c", "#d4d4d4")
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(toggle)
	return row


func _build_executable_path_controls(
	content: VBoxContainer,
	dialog_parent: Node,
	current_path: String,
	line_edit_name: String,
	browse_button_name: String,
	hint_name: String,
	path_label_text: String,
	placeholder: String,
	dialog_title: String,
	target_name: String,
	required: bool,
	path_changed: Callable
) -> Dictionary:
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	var title_label: Label = _new_label(
		path_label_text, 19, _details_color("#30383c", "#d4d4d4")
	)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_label)
	var line_edit := LineEdit.new()
	line_edit.name = line_edit_name
	line_edit.text = current_path
	line_edit.placeholder_text = placeholder
	line_edit.tooltip_text = "點擊 Agent 通知時切回這個目標：%s" % current_path
	line_edit.clear_button_enabled = true
	line_edit.visible = false
	content.add_child(line_edit)
	var path_summary: Label = _new_label(
		_executable_summary_text(current_path),
		13,
		_details_color("#68747a", "#9da1a6")
	)
	path_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	path_summary.mouse_filter = Control.MOUSE_FILTER_STOP
	path_summary.mouse_default_cursor_shape = Control.CURSOR_HELP
	path_summary.tooltip_text = (
		"完整執行檔路徑：\n%s" % current_path
		if not current_path.is_empty() else "尚未設定執行檔位置"
	)
	header_row.add_child(path_summary)
	var browse_button := Button.new()
	browse_button.name = browse_button_name
	browse_button.text = "📁"
	browse_button.tooltip_text = dialog_title
	browse_button.custom_minimum_size = Vector2(40, 34)
	browse_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_row.add_child(browse_button)
	content.add_child(header_row)
	var hint: Label = _new_label(
		"", 13, _details_color("#68747a", "#9da1a6")
	)
	hint.name = hint_name
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.visible = false
	content.add_child(hint)
	_update_executable_hint(line_edit.text, hint, target_name, required)
	_update_executable_summary(line_edit.text, path_summary)

	browse_button.pressed.connect(func() -> void:
		var dialog := FileDialog.new()
		dialog.name = line_edit_name + "Dialog"
		dialog.title = dialog_title
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.use_native_dialog = true
		dialog.filters = PackedStringArray(["*.exe ; Windows 執行檔"])
		dialog_parent.add_child(dialog)
		dialog.file_selected.connect(func(path: String) -> void:
			line_edit.text = path
			line_edit.tooltip_text = "點擊 Agent 通知時切回這個目標：%s" % path
			_update_executable_hint(path, hint, target_name, required)
			_update_executable_summary(path, path_summary)
			path_changed.call(path)
			dialog.queue_free()
		)
		dialog.popup_centered_ratio(0.8)
	)
	line_edit.text_submitted.connect(func(path: String) -> void:
		_update_executable_hint(path, hint, target_name, required)
		path_changed.call(path)
	)
	line_edit.focus_exited.connect(func() -> void:
		var path := line_edit.text
		_update_executable_hint(path, hint, target_name, required)
		path_changed.call(path)
	)
	line_edit.text_changed.connect(func(path: String) -> void:
		_update_executable_summary(path, path_summary)
	)
	return {"line_edit": line_edit, "hint": hint, "summary": path_summary}


func refresh_executable_path_control(
	path: String,
	line_edit: LineEdit,
	hint: Label,
	path_summary: Label,
	target_name: String,
	required: bool
) -> void:
	if is_instance_valid(line_edit) and not line_edit.has_focus():
		line_edit.text = path
		line_edit.tooltip_text = "點擊 Agent 通知時切回這個目標：%s" % path
	if is_instance_valid(hint):
		_update_executable_hint(path, hint, target_name, required)
	if is_instance_valid(path_summary):
		_update_executable_summary(path, path_summary)


func set_agent_executable_path_detection_state(
	targets: Array, detecting: bool
) -> void:
	for target: String in targets:
		var path_summary := _agent_executable_path_summaries.get(target) as Label
		if not is_instance_valid(path_summary):
			continue
		if detecting:
			path_summary.text = "點擊通知氣泡會切回：偵測中…"
			path_summary.tooltip_text = "正在偵測可用的執行檔位置"
			path_summary.add_theme_color_override(
				"font_color", _details_color("#68747a", "#9da1a6")
			)


func _executable_display_name(path: String) -> String:
	var normalized := path.strip_edges().trim_prefix('"').trim_suffix('"')
	return normalized.get_file() if not normalized.is_empty() else "未設定"


func _executable_summary_text(path: String) -> String:
	return "點擊通知氣泡會切回：%s" % _executable_display_name(path)


func _update_executable_summary(path: String, summary: Label) -> void:
	var normalized := path.strip_edges().trim_prefix('"').trim_suffix('"')
	summary.text = _executable_summary_text(normalized)
	summary.tooltip_text = (
		"完整執行檔路徑：\n%s" % normalized
		if not normalized.is_empty() else "尚未設定執行檔位置"
	)
	if normalized.is_empty() or not FileAccess.file_exists(normalized):
		summary.add_theme_color_override(
			"font_color", _details_color("#b44949", "#ff8c8c")
		)
	else:
		summary.add_theme_color_override(
			"font_color", _details_color("#68747a", "#9da1a6")
		)


func _update_executable_hint(
	path: String, hint: Label, target_name: String, required: bool
) -> void:
	var normalized := path.strip_edges().trim_prefix('"').trim_suffix('"')
	if normalized.is_empty():
		hint.text = (
			"尚未找到 %s；請按資料夾按鈕選擇執行檔。" % target_name
			if required
			else "尚未設定終端機執行檔；外部 CLI 通知仍會顯示，但點擊時無法切回終端機。"
		)
		hint.add_theme_color_override(
			"font_color", _details_color("#b44949", "#ff8c8c")
		)
	elif normalized.get_extension().to_lower() != "exe" \
			or not FileAccess.file_exists(normalized):
		hint.text = "找不到這個執行檔；通知氣泡會保留，直到路徑修正。"
		hint.add_theme_color_override(
			"font_color", _details_color("#b44949", "#ff8c8c")
		)
	else:
		hint.text = ""
		hint.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)


func _update_vscode_executable_hint(path: String, hint: Label) -> void:
	_update_executable_hint(path, hint, "VS Code", true)


func build_character_tab(tabs: TabContainer, stats_window: Window) -> Dictionary:
	var character_scroll := ScrollContainer.new()
	character_scroll.name = "角色"
	character_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var character_tab_index := tabs.get_tab_count()
	tabs.add_child(character_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	character_scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title: Label = _new_label(
		"角色管理", 24, _details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var hint: Label = _new_label(
		"角色清單只會在開啟這個頁面時讀取，不會增加平常常駐耗能。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

	var character_list := ItemList.new()
	character_list.name = "CharacterList"
	character_list.custom_minimum_size = Vector2(0, 260)
	character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_list.item_selected.connect(
		func(index: int) -> void: character_selected.emit(index)
	)
	content.add_child(character_list)

	var effect_panel := VBoxContainer.new()
	effect_panel.name = "MaskEffectEditor"
	effect_panel.add_theme_constant_override("separation", 6)
	var effect_header := PanelContainer.new()
	effect_header.name = "MaskEffectHeader"
	effect_header.custom_minimum_size.y = 34
	effect_header.mouse_filter = Control.MOUSE_FILTER_STOP
	effect_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_configure_mask_effect_header_style(effect_header)
	var effect_header_content := HBoxContainer.new()
	effect_header_content.add_theme_constant_override("separation", 6)
	effect_header_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var effect_title: Label = _new_label(
		"Codex Pet 眼罩特效校正", 17, _details_color("#30383c", "#f0f0f0")
	)
	effect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_header_content.add_child(effect_title)
	var effect_header_state: Label = _new_label(
		"設定", 14, _details_color("#445057", "#d4d4d4")
	)
	effect_header_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_header_content.add_child(effect_header_state)
	var effect_header_chevron: Label = _new_label(
		"▾", 16, _details_color("#68747a", "#9da1a6")
	)
	effect_header_chevron.custom_minimum_size.x = 18
	effect_header_chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_header_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_header_content.add_child(effect_header_chevron)
	effect_header.add_child(effect_header_content)
	effect_header.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				mask_effect_toggle_requested.emit()
	)
	effect_panel.add_child(effect_header)
	var effect_hint: Label = _new_label(
		"只套用到目前使用中的 Codex Pet；點擊上方列展開預覽與調整，按「套用」保存並鎖定。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	effect_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_panel.add_child(effect_hint)

	var effect_values_inner := VBoxContainer.new()
	effect_values_inner.add_theme_constant_override("separation", 2)
	var mask_x := SpinBox.new()
	mask_x.name = "MaskEffectX"
	mask_x.min_value = -200.0
	mask_x.max_value = 200.0
	mask_x.step = 1.0
	mask_x.select_all_on_focus = true
	mask_x.custom_minimum_size = Vector2(92, 34)
	_prepare_mask_numeric_input(mask_x)
	mask_x.tooltip_text = "眼罩水平位置"
	var mask_y := SpinBox.new()
	mask_y.name = "MaskEffectY"
	mask_y.min_value = -200.0
	mask_y.max_value = 200.0
	mask_y.step = 1.0
	mask_y.select_all_on_focus = true
	mask_y.custom_minimum_size = Vector2(92, 34)
	_prepare_mask_numeric_input(mask_y)
	mask_y.tooltip_text = "眼罩垂直位置"
	var mask_scale := SpinBox.new()
	mask_scale.name = "MaskEffectScale"
	mask_scale.min_value = 0.05
	mask_scale.max_value = 2.0
	mask_scale.step = 0.01
	mask_scale.select_all_on_focus = true
	mask_scale.custom_minimum_size = Vector2(92, 34)
	_prepare_mask_numeric_input(mask_scale)
	mask_scale.tooltip_text = "眼罩大小"
	var effect_labels_row := HBoxContainer.new()
	effect_labels_row.add_theme_constant_override("separation", 8)
	for label_text: String in ["X", "Y", "大小"]:
		var field_label: Label = _new_label(
			label_text, 12, _details_color("#68747a", "#9da1a6")
		)
		field_label.custom_minimum_size.x = 92
		field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		effect_labels_row.add_child(field_label)
	var reset_label_spacer := Control.new()
	reset_label_spacer.custom_minimum_size.x = 182
	effect_labels_row.add_child(reset_label_spacer)
	effect_values_inner.add_child(effect_labels_row)

	var effect_inputs_row := HBoxContainer.new()
	effect_inputs_row.add_theme_constant_override("separation", 8)
	effect_inputs_row.add_child(mask_x)
	effect_inputs_row.add_child(mask_y)
	effect_inputs_row.add_child(mask_scale)
	var effect_apply := Button.new()
	effect_apply.name = "MaskEffectApplyButton"
	effect_apply.text = "套用"
	effect_apply.custom_minimum_size = Vector2(92, 34)
	_apply_primary_button_style(effect_apply)
	effect_apply.pressed.connect(
		func() -> void: mask_effect_apply_requested.emit()
	)
	effect_inputs_row.add_child(effect_apply)

	var effect_reset := Button.new()
	effect_reset.name = "MaskEffectResetButton"
	effect_reset.text = "重設預設"
	effect_reset.custom_minimum_size = Vector2(92, 30)
	effect_reset.add_theme_font_size_override("font_size", 13)
	_apply_secondary_button_style(effect_reset)
	effect_reset.pressed.connect(
		func() -> void: mask_effect_reset_requested.emit()
	)
	effect_inputs_row.add_child(effect_reset)
	effect_values_inner.add_child(effect_inputs_row)
	var effect_values := CenterContainer.new()
	effect_values.add_child(effect_values_inner)
	effect_panel.add_child(effect_values)

	var emit_mask_changed := func() -> void:
		mask_effect_changed.emit(
			Vector2(mask_x.value, mask_y.value), mask_scale.value
		)
	mask_x.value_changed.connect(func(_value: float) -> void: emit_mask_changed.call())
	mask_y.value_changed.connect(func(_value: float) -> void: emit_mask_changed.call())
	mask_scale.value_changed.connect(func(_value: float) -> void: emit_mask_changed.call())

	content.add_child(effect_panel)

	var action_row := HFlowContainer.new()
	action_row.alignment = FlowContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("h_separation", 8)
	var character_use_button := Button.new()
	character_use_button.name = "CharacterUseButton"
	character_use_button.text = "使用選取角色"
	character_use_button.custom_minimum_size = Vector2(145, 40)
	character_use_button.disabled = true
	_apply_primary_button_style(character_use_button)
	character_use_button.pressed.connect(
		func() -> void: character_use_requested.emit()
	)
	action_row.add_child(character_use_button)
	var character_delete_button := Button.new()
	character_delete_button.name = "CharacterDeleteButton"
	character_delete_button.text = "刪除角色包"
	character_delete_button.custom_minimum_size = Vector2(125, 40)
	character_delete_button.disabled = true
	_apply_danger_button_style(character_delete_button)
	character_delete_button.pressed.connect(
		func() -> void: character_delete_requested.emit()
	)
	action_row.add_child(character_delete_button)
	content.add_child(action_row)

	var import_row := HFlowContainer.new()
	import_row.alignment = FlowContainer.ALIGNMENT_CENTER
	import_row.add_theme_constant_override("h_separation", 8)
	var import_button := Button.new()
	import_button.name = "CharacterImportButton"
	import_button.text = "匯入角色包"
	import_button.custom_minimum_size = Vector2(135, 40)
	import_button.pressed.connect(
		func() -> void: character_import_requested.emit()
	)
	import_row.add_child(import_button)
	var open_folder_button := Button.new()
	open_folder_button.name = "CharacterPacksFolderButton"
	open_folder_button.text = "開啟角色資料夾"
	open_folder_button.custom_minimum_size = Vector2(145, 40)
	open_folder_button.pressed.connect(
		func() -> void: open_character_packs_folder_requested.emit()
	)
	import_row.add_child(open_folder_button)
	content.add_child(import_row)

	var character_feedback: Label = _new_label(
		"切換角色會儲存目前進度，並直接在目前視窗載入。",
		13,
		_details_color("#238b9d", "#4fc1ff")
	)
	character_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(character_feedback)

	var character_import_dialog := FileDialog.new()
	character_import_dialog.name = "CharacterImportDialog"
	character_import_dialog.title = "匯入角色包"
	character_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	character_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	character_import_dialog.use_native_dialog = true
	character_import_dialog.add_filter("*.petpack, *.zip", "桌寵角色包")
	character_import_dialog.file_selected.connect(
		func(path: String) -> void: character_archive_selected.emit(path)
	)
	stats_window.add_child(character_import_dialog)

	var character_update_dialog := ConfirmationDialog.new()
	character_update_dialog.name = "CharacterUpdateDialog"
	character_update_dialog.title = "更新角色包"
	character_update_dialog.confirmed.connect(
		func() -> void: character_update_confirmed.emit()
	)
	stats_window.add_child(character_update_dialog)

	var character_delete_dialog := ConfirmationDialog.new()
	character_delete_dialog.name = "CharacterDeleteDialog"
	character_delete_dialog.title = "刪除角色包"
	character_delete_dialog.confirmed.connect(
		func() -> void: character_delete_confirmed.emit()
	)
	stats_window.add_child(character_delete_dialog)

	var mask_effect_feedback_dialog := AcceptDialog.new()
	mask_effect_feedback_dialog.name = "MaskEffectFeedbackDialog"
	mask_effect_feedback_dialog.title = "Codex Pet 眼罩設定"
	mask_effect_feedback_dialog.ok_button_text = "確定"
	stats_window.add_child(mask_effect_feedback_dialog)

	return {
		"character_tab_index": character_tab_index,
		"character_list": character_list,
		"character_use_button": character_use_button,
		"character_delete_button": character_delete_button,
		"mask_effect_x": mask_x,
		"mask_effect_y": mask_y,
		"mask_effect_scale": mask_scale,
		"mask_effect_panel": effect_panel,
		"mask_effect_hint": effect_hint,
		"mask_effect_values": effect_values,
		"mask_effect_header_state": effect_header_state,
		"mask_effect_header_chevron": effect_header_chevron,
		"mask_effect_apply_button": effect_apply,
		"mask_effect_reset_button": effect_reset,
		"mask_effect_feedback_dialog": mask_effect_feedback_dialog,
		"character_feedback": character_feedback,
		"character_import_dialog": character_import_dialog,
		"character_update_dialog": character_update_dialog,
		"character_delete_dialog": character_delete_dialog,
	}


func _new_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _details_color(light: String, dark: String) -> Color:
	return Color(dark if theme_mode == "dark" else light)


func _details_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _handle_visual_scale_wheel(event: InputEvent, slider: HSlider) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	var direction := 0.0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = 1.0
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = -1.0
	if is_zero_approx(direction):
		return
	slider.value = clampf(
		slider.value + slider.step * direction,
		slider.min_value,
		slider.max_value
	)
	slider.accept_event()


func _create_slider_grabber_texture(highlighted: bool) -> Texture2D:
	const texture_size := 28
	const shadow_radius := 11.5
	const outer_radius := 10.0
	const inner_radius := 5.0
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(texture_size, texture_size) * 0.5
	var shadow_color := Color(0.0, 0.0, 0.0, 0.14 if highlighted else 0.10)
	var border_color := _details_color("#cfd7da", "#6b7377")
	var outer_color := _details_color("#ffffff", "#f4f6f7")
	var inner_color := _details_color(
		"#079dac" if not highlighted else "#087f8b",
		"#35a9bd" if not highlighted else "#4fc1ff"
	)
	var effective_inner_radius := inner_radius + (0.5 if highlighted else 0.0)
	for y in texture_size:
		for x in texture_size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var pixel_color := Color.TRANSPARENT
			if distance <= effective_inner_radius - 0.5:
				pixel_color = inner_color
			elif distance <= effective_inner_radius + 0.5:
				pixel_color = inner_color.lerp(
					outer_color,
					distance - (effective_inner_radius - 0.5)
				)
			elif distance <= outer_radius - 1.0:
				pixel_color = outer_color
			elif distance <= outer_radius:
				pixel_color = border_color
			elif distance <= outer_radius + 0.5:
				pixel_color = border_color
				pixel_color.a = lerpf(
					1.0,
					shadow_color.a,
					distance - outer_radius
				)
			elif distance <= shadow_radius:
				pixel_color = shadow_color
				pixel_color.a *= clampf(
					(shadow_radius - distance) / (shadow_radius - outer_radius),
					0.0,
					1.0
				)
			image.set_pixel(x, y, pixel_color)
	return ImageTexture.create_from_image(image)


func _prepare_mask_numeric_input(spin_box: SpinBox) -> void:
	var line_edit := spin_box.get_line_edit()
	line_edit.gui_input.connect(
		func(event: InputEvent) -> void:
			_handle_mask_numeric_input(line_edit, event)
	)


func _handle_mask_numeric_input(line_edit: LineEdit, event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode not in [KEY_MINUS, KEY_KP_SUBTRACT]:
		return
	if line_edit.text.begins_with("-") and not line_edit.has_selection():
		return
	line_edit.text = "-"
	line_edit.set_caret_column(1)
	line_edit.accept_event()


func _add_stat_row(parent: VBoxContainer, label_text: String, key: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _new_label(label_text, 15, _details_color("#445057", "#cccccc"))
	label.custom_minimum_size.x = 48
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 22
	bar.show_percentage = true
	var background := StyleBoxFlat.new()
	background.bg_color = _details_color("#e8edef", "#333333")
	background.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_color_override("font_color", _details_color("#263238", "#f0f0f0"))
	bar.add_theme_color_override("font_outline_color", _details_color("#ffffff", "#1e1e1e"))
	bar.add_theme_constant_override("outline_size", 1)
	row.add_child(bar)
	stats_bars[key] = bar
	parent.add_child(row)


func _style_spin_box(spin_box: SpinBox) -> void:
	var line_edit := spin_box.get_line_edit()
	var normal := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#d6dee2", "#3c3c3c"), 6
	)
	var hover := _details_style(
		_details_color("#f7fcfd", "#2a2d2e"),
		_details_color("#78c8d5", "#4e94ce"), 6
	)
	var focus := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#35a9bd", "#3794ff"), 6
	)
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("hover", hover)
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_color_override("font_color", _details_color("#30383c", "#d4d4d4"))
	line_edit.add_theme_color_override("font_uneditable_color", _details_color("#68747a", "#9da1a6"))
	line_edit.add_theme_color_override("caret_color", _details_color("#176f7e", "#4fc1ff"))
	spin_box.add_theme_color_override("font_color", _details_color("#30383c", "#d4d4d4"))


func _style_checkbox(check_box: CheckBox) -> void:
	check_box.add_theme_constant_override("h_separation", 10)
	check_box.add_theme_color_override("font_color", _details_color("#30383c", "#cccccc"))
	check_box.add_theme_color_override("font_hover_color", _details_color("#176f7e", "#ffffff"))
	check_box.add_theme_color_override("font_pressed_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_hover_pressed_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_focus_color", _details_color("#145f6c", "#ffffff"))
	check_box.add_theme_color_override("font_disabled_color", _details_color("#99a3a8", "#6d6d6d"))


func _apply_primary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#35a9bd", "#0e639c"), _details_color("#35a9bd", "#1177bb"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#278fa1", "#1177bb"), _details_color("#278fa1", "#3794ff"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#1d7888", "#094771"), _details_color("#1d7888", "#3794ff"), 8
	))
	button.add_theme_color_override("font_color", Color("#ffffff"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("#ffffff"))


func configure_mask_effect_header(
	state_label: Label, chevron: Label, editing: bool
) -> void:
	state_label.text = "設定"
	chevron.text = "▴" if editing else "▾"


func _configure_mask_effect_header_style(header: Control) -> void:
	var normal := _details_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	header.add_theme_stylebox_override("panel", normal)


func _apply_secondary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#ffffff", "#252526"), _details_color("#c7d0d5", "#45484c"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#f1f4f5", "#303236"), _details_color("#8fa5ae", "#60666b"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#e4eaed", "#3a3d41"), _details_color("#7b919b", "#747a80"), 8
	))
	button.add_theme_color_override("font_color", _details_color("#445057", "#d4d4d4"))
	button.add_theme_color_override("font_hover_color", _details_color("#30383c", "#f0f0f0"))
	button.add_theme_color_override("font_pressed_color", _details_color("#30383c", "#f0f0f0"))


func _apply_danger_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _details_style(
		_details_color("#fffafa", "#2b2020"), _details_color("#e7b4b4", "#8b4545"), 8
	))
	button.add_theme_stylebox_override("hover", _details_style(
		_details_color("#fff0f0", "#3b2424"), _details_color("#d97b7b", "#d16969"), 8
	))
	button.add_theme_stylebox_override("pressed", _details_style(
		_details_color("#f8dddd", "#512b2b"), _details_color("#c85f5f", "#f48771"), 8
	))
	button.add_theme_color_override("font_color", _details_color("#b34747", "#f48771"))
	button.add_theme_color_override("font_hover_color", _details_color("#a53636", "#ff9b8a"))
	button.add_theme_color_override("font_pressed_color", _details_color("#8f2d2d", "#ffffff"))


func _interaction_label(action: String) -> String:
	if interaction_label.is_valid():
		return String(interaction_label.call(action))
	return action


func _interaction_icon(action: String) -> String:
	if interaction_icon.is_valid():
		return String(interaction_icon.call(action))
	return ""
