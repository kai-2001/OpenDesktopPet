class_name DetailsWindowController
extends RefCounted

const CodexIntegrationControllerScript = preload("res://scripts/codex_integration_controller.gd")
const CodexToggleSwitchScript = preload("res://scripts/codex_toggle_switch.gd")
const TARGET_FPS_OPTIONS := [15, 30, 60]

signal care_action_requested(action: String)
signal close_requested
signal target_fps_selected(index: int)
signal details_theme_selected(index: int)
signal codex_enabled_toggled(enabled: bool)
signal codex_port_changed(value: float)
signal codex_executable_path_changed(path: String)
signal autostart_toggled(enabled: bool)
signal character_selected(index: int)
signal character_use_requested
signal character_delete_requested
signal character_import_requested
signal open_character_packs_folder_requested
signal character_archive_selected(path: String)
signal character_update_confirmed
signal character_delete_confirmed

var theme_mode := "light"
var last_state_message := "尚無紀錄"
var codex_enabled := false
var codex_port := CodexIntegrationControllerScript.DEFAULT_PORT
var codex_executable_path := ""
var autostart_supported := false
var interaction_label: Callable
var interaction_icon: Callable
var stats_bars: Dictionary = {}


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

	var codex_port_row := HBoxContainer.new()
	codex_port_row.add_theme_constant_override("separation", 8)
	var codex_port_label: Label = _new_label(
		"Codex 完成通知", 16, _details_color("#30383c", "#d4d4d4")
	)
	codex_port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_port_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	codex_port_label.tooltip_text = "Codex 完成通知使用的本機通訊埠"
	codex_port_row.add_child(codex_port_label)
	var codex_port_value_label: Label = _new_label(
		"通訊埠", 14, _details_color("#68747a", "#9da1a6")
	)
	codex_port_value_label.tooltip_text = "Codex 與桌寵必須使用相同通訊埠"
	codex_port_row.add_child(codex_port_value_label)
	var codex_port_spin_box := SpinBox.new()
	codex_port_spin_box.name = "CodexPortSpinBox"
	codex_port_spin_box.tooltip_text = "Codex 完成通知使用的本機通訊埠"
	codex_port_spin_box.min_value = CodexIntegrationControllerScript.MIN_PORT
	codex_port_spin_box.max_value = CodexIntegrationControllerScript.MAX_PORT
	codex_port_spin_box.step = 1
	codex_port_spin_box.value = codex_port
	codex_port_spin_box.custom_minimum_size = Vector2(120, 40)
	_style_spin_box(codex_port_spin_box)
	codex_port_spin_box.value_changed.connect(
		func(value: float) -> void: codex_port_changed.emit(value)
	)
	codex_port_row.add_child(codex_port_spin_box)
	var codex_enabled_toggle := CodexToggleSwitchScript.new()
	codex_enabled_toggle.name = "CodexEnabledToggle"
	codex_enabled_toggle.tooltip_text = "開啟或關閉 Codex 完成通知"
	codex_enabled_toggle.configure(theme_mode, codex_enabled)
	codex_enabled_toggle.toggled.connect(
		func(enabled: bool) -> void:
			codex_enabled_toggled.emit(enabled)
	)
	codex_port_row.add_child(codex_enabled_toggle)
	settings_content.add_child(codex_port_row)

	var codex_status_label: Label = _new_label(
		"", 14, _details_color("#238b9d", "#4fc1ff")
	)
	codex_status_label.name = "CodexStatusLabel"
	codex_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(codex_status_label)

	var codex_executable_label: Label = _new_label(
		"VS Code 執行檔", 14, _details_color("#30383c", "#d4d4d4")
	)
	settings_content.add_child(codex_executable_label)
	var codex_executable_row := HBoxContainer.new()
	codex_executable_row.add_theme_constant_override("separation", 8)
	var codex_executable_line_edit := LineEdit.new()
	codex_executable_line_edit.name = "CodexExecutablePath"
	codex_executable_line_edit.text = codex_executable_path
	codex_executable_line_edit.placeholder_text = "選擇 Code.exe"
	codex_executable_line_edit.tooltip_text = "點擊 Codex 通知時使用的 VS Code 執行檔"
	codex_executable_line_edit.clear_button_enabled = true
	codex_executable_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_executable_line_edit.custom_minimum_size.y = 40
	codex_executable_row.add_child(codex_executable_line_edit)
	var codex_executable_browse_button := Button.new()
	codex_executable_browse_button.name = "CodexExecutableBrowseButton"
	codex_executable_browse_button.text = "📁"
	codex_executable_browse_button.tooltip_text = "選擇 VS Code 執行檔"
	codex_executable_browse_button.custom_minimum_size = Vector2(48, 40)
	codex_executable_browse_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	codex_executable_row.add_child(codex_executable_browse_button)
	settings_content.add_child(codex_executable_row)

	var codex_executable_hint: Label = _new_label(
		"", 13, _details_color("#68747a", "#9da1a6")
	)
	codex_executable_hint.name = "CodexExecutableHint"
	codex_executable_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(codex_executable_hint)
	_update_codex_executable_hint(
		codex_executable_line_edit.text, codex_executable_hint
	)

	var codex_executable_dialog := FileDialog.new()
	codex_executable_dialog.name = "CodexExecutableDialog"
	codex_executable_dialog.title = "選擇 VS Code 執行檔"
	codex_executable_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	codex_executable_dialog.access = FileDialog.ACCESS_FILESYSTEM
	codex_executable_dialog.use_native_dialog = true
	codex_executable_dialog.filters = PackedStringArray([
		"*.exe ; Windows 執行檔",
	])
	settings_scroll.add_child(codex_executable_dialog)
	codex_executable_browse_button.pressed.connect(func() -> void:
		var current_path := codex_executable_line_edit.text.strip_edges()
		if FileAccess.file_exists(current_path):
			codex_executable_dialog.current_path = current_path
		codex_executable_dialog.popup_centered_ratio(0.8)
	)
	codex_executable_dialog.file_selected.connect(func(path: String) -> void:
		codex_executable_line_edit.text = path
		_update_codex_executable_hint(path, codex_executable_hint)
		codex_executable_path_changed.emit(path)
	)
	codex_executable_line_edit.text_submitted.connect(func(path: String) -> void:
		_update_codex_executable_hint(path, codex_executable_hint)
		codex_executable_path_changed.emit(path)
	)
	codex_executable_line_edit.focus_exited.connect(func() -> void:
		var path := codex_executable_line_edit.text
		_update_codex_executable_hint(path, codex_executable_hint)
		codex_executable_path_changed.emit(path)
	)
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
		"codex_enabled_toggle": codex_enabled_toggle,
		"codex_port_spin_box": codex_port_spin_box,
		"codex_status_label": codex_status_label,
		"codex_executable_line_edit": codex_executable_line_edit,
		"autostart_check_box": autostart_check_box,
		"settings_feedback": settings_feedback,
	}


func _update_codex_executable_hint(path: String, hint: Label) -> void:
	var normalized := path.strip_edges().trim_prefix('"').trim_suffix('"')
	if normalized.is_empty():
		hint.text = "尚未找到 VS Code；請按資料夾按鈕選擇 Code.exe。"
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
		hint.text = "點擊 Codex 通知時會使用這個 VS Code 視窗。"
		hint.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)


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

	return {
		"character_tab_index": character_tab_index,
		"character_list": character_list,
		"character_use_button": character_use_button,
		"character_delete_button": character_delete_button,
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
