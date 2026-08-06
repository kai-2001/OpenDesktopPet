class_name DetailsWindowController
extends RefCounted

const CodexIntegrationControllerScript = preload("res://scripts/codex_integration_controller.gd")
const TARGET_FPS_OPTIONS := [15, 30, 60]


func build_status_tab(tabs: TabContainer, host: Node) -> Dictionary:
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

	var title: Label = host._new_label(
		"養成狀態", 24, host._details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var stats_status: Label = host._new_label(
		"", 15, host._details_color("#238b9d", "#4fc1ff")
	)
	stats_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(stats_status)

	var companion_status: Label = host._new_label(
		"", 14, host._details_color("#6f65a8", "#c8a7ff")
	)
	companion_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	companion_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(companion_status)

	var wish_status: Label = host._new_label(
		"", 15, host._details_color("#a66b16", "#dcdcaa")
	)
	wish_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wish_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(wish_status)

	content.add_child(HSeparator.new())
	host._add_stat_row(content, "飽食", "hunger", Color("#efa64a"))
	host._add_stat_row(content, "水分", "thirst", Color("#55b7df"))
	host._add_stat_row(content, "體力", "energy", Color("#69c986"))
	host._add_stat_row(content, "心情", "mood", Color("#e97ca6"))
	host._add_stat_row(content, "親密", "affection", Color("#9a83d2"))

	var unlock_status: Label = host._new_label(
		"", 14, host._details_color("#6f65a8", "#c8a7ff")
	)
	unlock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(unlock_status)

	var last_message_status: Label = host._new_label(
		"最近訊息：%s" % host._last_state_message,
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	last_message_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_message_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(last_message_status)
	content.add_child(HSeparator.new())

	var action_title: Label = host._new_label(
		"照顧操作", 16, host._details_color("#30383c", "#d4d4d4")
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
			host._interaction_icon(action), host._interaction_label(action)
		]
		action_button.custom_minimum_size = Vector2(100, 38)
		var action_id := int(definition.id)
		action_button.pressed.connect(
			func() -> void: host._run_care_action(action_id)
		)
		action_grid.add_child(action_button)
		care_action_buttons[action] = action_button
	content.add_child(action_grid)
	content.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "關閉詳細狀態"
	close_button.custom_minimum_size.y = 40
	close_button.pressed.connect(host._destroy_stats_window)
	content.add_child(close_button)

	return {
		"stats_status": stats_status,
		"companion_status": companion_status,
		"wish_status": wish_status,
		"unlock_status": unlock_status,
		"last_message_status": last_message_status,
		"care_action_buttons": care_action_buttons,
	}


func build_settings_tab(tabs: TabContainer, host: Node) -> Dictionary:
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

	var settings_title: Label = host._new_label(
		"桌寵設定", 24, host._details_color("#20272b", "#f0f0f0")
	)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(settings_title)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label: Label = host._new_label(
		"桌寵幀率（FPS）", 16, host._details_color("#30383c", "#d4d4d4")
	)
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	var fps_option_button := OptionButton.new()
	for fps: int in TARGET_FPS_OPTIONS:
		fps_option_button.add_item("%d FPS" % fps, fps)
	fps_option_button.select(fps_option_button.get_item_index(Engine.max_fps))
	fps_option_button.custom_minimum_size = Vector2(120, 40)
	fps_option_button.item_selected.connect(host._on_target_fps_selected)
	fps_row.add_child(fps_option_button)
	settings_content.add_child(fps_row)

	var fps_hint: Label = host._new_label(
		"控制整個桌寵的更新率（15–60）；30 FPS 適合日常使用，降低可省電。",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	fps_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(fps_hint)
	settings_content.add_child(HSeparator.new())

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	var theme_label: Label = host._new_label(
		"詳細面板主題", 16, host._details_color("#30383c", "#d4d4d4")
	)
	theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_label)
	var details_theme_option_button := OptionButton.new()
	details_theme_option_button.add_item("淺色", 0)
	details_theme_option_button.add_item("深色", 1)
	details_theme_option_button.select(
		1 if host._details_theme_mode == "dark" else 0
	)
	details_theme_option_button.custom_minimum_size = Vector2(120, 40)
	details_theme_option_button.item_selected.connect(host._on_details_theme_selected)
	theme_row.add_child(details_theme_option_button)
	settings_content.add_child(theme_row)

	var theme_hint: Label = host._new_label(
		"切換詳細面板的完整配色；設定會自動保存。",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	settings_content.add_child(theme_hint)
	settings_content.add_child(HSeparator.new())

	var codex_title: Label = host._new_label(
		"Codex 完成通知", 18, host._details_color("#30383c", "#d4d4d4")
	)
	codex_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(codex_title)

	var codex_switch_row := HBoxContainer.new()
	codex_switch_row.add_theme_constant_override("separation", 12)
	var codex_switch_label: Label = host._new_label(
		"通知狀態", 16, host._details_color("#30383c", "#d4d4d4")
	)
	codex_switch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_switch_row.add_child(codex_switch_label)
	var codex_state_option_button := OptionButton.new()
	codex_state_option_button.name = "CodexStateOptionButton"
	codex_state_option_button.add_item("開啟", 0)
	codex_state_option_button.add_item("關閉", 1)
	var codex_enabled: bool = (
		host._codex_controller != null and host._codex_controller.enabled
	)
	codex_state_option_button.select(0 if codex_enabled else 1)
	codex_state_option_button.custom_minimum_size = Vector2(112, 40)
	codex_state_option_button.item_selected.connect(host._on_codex_state_selected)
	codex_switch_row.add_child(codex_state_option_button)
	settings_content.add_child(codex_switch_row)

	var codex_port_row := HBoxContainer.new()
	codex_port_row.add_theme_constant_override("separation", 12)
	var codex_port_label: Label = host._new_label(
		"本機通訊埠", 16, host._details_color("#30383c", "#d4d4d4")
	)
	codex_port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_port_row.add_child(codex_port_label)
	var codex_port_spin_box := SpinBox.new()
	codex_port_spin_box.name = "CodexPortSpinBox"
	codex_port_spin_box.min_value = CodexIntegrationControllerScript.MIN_PORT
	codex_port_spin_box.max_value = CodexIntegrationControllerScript.MAX_PORT
	codex_port_spin_box.step = 1
	codex_port_spin_box.value = (
		host._codex_controller.port
		if host._codex_controller != null
		else CodexIntegrationControllerScript.DEFAULT_PORT
	)
	codex_port_spin_box.custom_minimum_size = Vector2(140, 40)
	host._style_spin_box(codex_port_spin_box)
	codex_port_spin_box.value_changed.connect(host._on_codex_port_changed)
	codex_port_row.add_child(codex_port_spin_box)
	settings_content.add_child(codex_port_row)

	var codex_status_label: Label = host._new_label(
		"", 14, host._details_color("#238b9d", "#4fc1ff")
	)
	codex_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(codex_status_label)

	var codex_hint: Label = host._new_label(
		"通知開啟時通訊埠會鎖定；關閉後才可以修改。",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	codex_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(codex_hint)

	var codex_button_row := HBoxContainer.new()
	codex_button_row.add_theme_constant_override("separation", 8)
	var codex_configure_button := Button.new()
	codex_configure_button.name = "CodexConfigureButton"
	codex_configure_button.text = "設定通訊埠"
	codex_configure_button.custom_minimum_size = Vector2(0, 40)
	codex_configure_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._style_codex_action_button(codex_configure_button)
	codex_configure_button.disabled = codex_enabled
	codex_configure_button.pressed.connect(host._configure_codex_port)
	codex_button_row.add_child(codex_configure_button)
	var codex_reconnect_button := Button.new()
	codex_reconnect_button.name = "CodexReconnectButton"
	codex_reconnect_button.text = "重新連線接收器"
	codex_reconnect_button.custom_minimum_size = Vector2(0, 40)
	codex_reconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._style_codex_action_button(codex_reconnect_button)
	codex_reconnect_button.disabled = not codex_enabled
	codex_reconnect_button.pressed.connect(host._reconnect_codex_receiver)
	codex_button_row.add_child(codex_reconnect_button)
	settings_content.add_child(codex_button_row)

	var codex_feedback: Label = host._new_label(
		"通知已關閉；選擇通訊埠後按「設定通訊埠」。",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	codex_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(codex_feedback)
	settings_content.add_child(HSeparator.new())

	var autostart_check_box := CheckBox.new()
	autostart_check_box.text = "登入 Windows 時自動開啟桌寵"
	autostart_check_box.add_theme_font_size_override("font_size", 16)
	host._style_checkbox(autostart_check_box)
	autostart_check_box.custom_minimum_size = Vector2(0, 40)
	autostart_check_box.button_pressed = false
	autostart_check_box.disabled = true
	autostart_check_box.toggled.connect(host._on_autostart_toggled)
	settings_content.add_child(autostart_check_box)

	var settings_feedback: Label = host._new_label(
		"請使用打包版設定開機啟動。"
		if OS.has_feature("editor")
		else "正在讀取 Windows 開機啟動設定…",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(settings_feedback)
	if host._is_autostart_supported():
		host.call_deferred("_start_autostart_operation", "query", false)
	elif not OS.has_feature("editor"):
		settings_feedback.text = "目前平台不支援 Windows 開機啟動設定。"

	var settings_close_button := Button.new()
	settings_close_button.text = "關閉詳細面板"
	settings_close_button.custom_minimum_size.y = 42
	settings_close_button.pressed.connect(host._destroy_stats_window)
	settings_content.add_child(settings_close_button)

	return {
		"fps_option_button": fps_option_button,
		"details_theme_option_button": details_theme_option_button,
		"codex_state_option_button": codex_state_option_button,
		"codex_port_spin_box": codex_port_spin_box,
		"codex_status_label": codex_status_label,
		"codex_configure_button": codex_configure_button,
		"codex_reconnect_button": codex_reconnect_button,
		"codex_feedback": codex_feedback,
		"autostart_check_box": autostart_check_box,
		"settings_feedback": settings_feedback,
	}


func build_character_tab(tabs: TabContainer, host: Node) -> Dictionary:
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

	var title: Label = host._new_label(
		"角色管理", 24, host._details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var hint: Label = host._new_label(
		"角色清單只會在開啟這個頁面時讀取，不會增加平常常駐耗能。",
		13,
		host._details_color("#68747a", "#9da1a6")
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

	var character_list := ItemList.new()
	character_list.name = "CharacterList"
	character_list.custom_minimum_size = Vector2(0, 260)
	character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_list.item_selected.connect(host._on_character_selected)
	content.add_child(character_list)

	var action_row := HFlowContainer.new()
	action_row.alignment = FlowContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("h_separation", 8)
	var character_use_button := Button.new()
	character_use_button.name = "CharacterUseButton"
	character_use_button.text = "使用選取角色"
	character_use_button.custom_minimum_size = Vector2(145, 40)
	character_use_button.disabled = true
	host._apply_primary_button_style(character_use_button)
	character_use_button.pressed.connect(host._use_selected_character)
	action_row.add_child(character_use_button)
	var character_delete_button := Button.new()
	character_delete_button.name = "CharacterDeleteButton"
	character_delete_button.text = "刪除角色包"
	character_delete_button.custom_minimum_size = Vector2(125, 40)
	character_delete_button.disabled = true
	host._apply_danger_button_style(character_delete_button)
	character_delete_button.pressed.connect(host._confirm_delete_selected_character)
	action_row.add_child(character_delete_button)
	content.add_child(action_row)

	var import_row := HFlowContainer.new()
	import_row.alignment = FlowContainer.ALIGNMENT_CENTER
	import_row.add_theme_constant_override("h_separation", 8)
	var import_button := Button.new()
	import_button.name = "CharacterImportButton"
	import_button.text = "匯入角色包"
	import_button.custom_minimum_size = Vector2(135, 40)
	import_button.pressed.connect(host._open_character_import_dialog)
	import_row.add_child(import_button)
	var open_folder_button := Button.new()
	open_folder_button.name = "CharacterPacksFolderButton"
	open_folder_button.text = "開啟角色資料夾"
	open_folder_button.custom_minimum_size = Vector2(145, 40)
	open_folder_button.pressed.connect(host._open_character_packs_folder)
	import_row.add_child(open_folder_button)
	content.add_child(import_row)

	var character_feedback: Label = host._new_label(
		"切換角色會儲存目前進度，並直接在目前視窗載入。",
		13,
		host._details_color("#238b9d", "#4fc1ff")
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
	character_import_dialog.file_selected.connect(host._install_character_archive)
	host._stats_window.add_child(character_import_dialog)

	var character_update_dialog := ConfirmationDialog.new()
	character_update_dialog.name = "CharacterUpdateDialog"
	character_update_dialog.title = "更新角色包"
	character_update_dialog.confirmed.connect(host._install_pending_character_archive)
	host._stats_window.add_child(character_update_dialog)

	var character_delete_dialog := ConfirmationDialog.new()
	character_delete_dialog.name = "CharacterDeleteDialog"
	character_delete_dialog.title = "刪除角色包"
	character_delete_dialog.confirmed.connect(host._delete_selected_character)
	host._stats_window.add_child(character_delete_dialog)

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
