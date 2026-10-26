class_name AgentTabView
extends "res://scripts/details_tab_view.gd"

const AgentIntegrationControllerScript = preload("res://scripts/agent_integration_controller.gd")
const AgentChannelCatalogScript = preload("res://scripts/agent_channel_catalog.gd")
const SettingsToggleSwitchScript = preload("res://scripts/settings_toggle_switch.gd")

signal agent_channel_toggled(channel_id: String, enabled: bool)
signal agent_port_changed(value: float)
signal codex_trust_review_requested
signal codex_trust_recheck_requested
signal agent_executable_path_changed(target: String, path: String)

# AgentIntegrationController.get_settings_snapshot() for the Agent tab.
var agent_settings: Dictionary = {}
var _agent_executable_controls: Dictionary = {}


func build(tabs: TabContainer) -> Dictionary:
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
	port_spin_box.value = int(
		agent_settings.get("port", AgentIntegrationControllerScript.DEFAULT_PORT)
	)
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
		"Codex 必須先信任桌寵的 Stop、PermissionRequest、PreToolUse Hook，通知才會生效。\n\n"
		+ "1. 按「開啟 Codex 信任畫面」。\n"
		+ "2. 在 PowerShell 選 1. Review hooks，再按 Enter；這一步只會開啟 Hook 清單。\n"
		+ "3. 在 Hook 清單依序選取 Stop、PermissionRequest、PreToolUse，"
		+ "每一項都按 Enter 開啟詳細內容。\n"
		+ "4. 在每一項找到 Open Desktop Pet 的 Hook，將核取狀態切換為 [x]。"
		+ "[ ] 表示尚未信任；三項都顯示 [x] 才算完成信任。\n"
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
	var channel_states: Dictionary = agent_settings.get("channels", {})
	var executable_paths: Dictionary = agent_settings.get("executable_paths", {})
	var channel_toggles := {}
	_agent_executable_controls = {}
	for target_entry: Dictionary in AgentChannelCatalogScript.TARGETS:
		var target := String(target_entry["target"])
		var node_prefix := String(target_entry["node_prefix"])
		content.add_child(HSeparator.new())
		_agent_executable_controls[target] = _build_executable_path_controls(
			content,
			agent_scroll,
			String(executable_paths.get(target, "")),
			node_prefix + "ExecutablePath",
			node_prefix + "ExecutableBrowseButton",
			node_prefix + "ExecutableHint",
			target_entry["title"],
			target_entry["placeholder"],
			target_entry["dialog_title"],
			target_entry["title"],
			target_entry["required"],
			func(path: String) -> void: agent_executable_path_changed.emit(target, path)
		)
		for channel: Dictionary in AgentChannelCatalogScript.channels_for_target(target):
			var channel_id := String(channel["id"])
			var toggle := SettingsToggleSwitchScript.new()
			toggle.name = channel["node_name"]
			toggle.tooltip_text = channel["tooltip"]
			toggle.configure(theme_mode, bool(channel_states.get(channel_id, false)))
			toggle.toggled.connect(
				func(value: bool) -> void: agent_channel_toggled.emit(channel_id, value)
			)
			content.add_child(_build_agent_row(channel["label"], toggle))
			channel_toggles[channel_id] = toggle

	return {
		"agent_port_spin_box": port_spin_box,
		"agent_status_label": status_label,
		"codex_setup_progress_bar": codex_setup_progress,
		"codex_trust_review_button": codex_trust_review_button,
		"codex_trust_recheck_button": codex_trust_recheck_button,
		"codex_trust_dialog": codex_trust_dialog,
		"channel_toggles": channel_toggles,
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


func refresh_agent_executable_path(target: String, path: String) -> void:
	var controls: Dictionary = _agent_executable_controls.get(target, {})
	if controls.is_empty():
		return
	var target_entry := _agent_target_entry(target)
	var line_edit := controls["line_edit"] as LineEdit
	var hint := controls["hint"] as Label
	var path_summary := controls["summary"] as Label
	if is_instance_valid(line_edit) and not line_edit.has_focus():
		line_edit.text = path
		line_edit.tooltip_text = "點擊 Agent 通知時切回這個目標：%s" % path
	if is_instance_valid(hint):
		_update_executable_hint(path, hint, target_entry["title"], target_entry["required"])
	if is_instance_valid(path_summary):
		_update_executable_summary(path, path_summary)


func _agent_target_entry(target: String) -> Dictionary:
	for target_entry: Dictionary in AgentChannelCatalogScript.TARGETS:
		if target_entry["target"] == target:
			return target_entry
	return {}


func set_agent_executable_path_detection_state(
	targets: Array, detecting: bool
) -> void:
	for target: String in targets:
		var controls: Dictionary = _agent_executable_controls.get(target, {})
		var path_summary := controls.get("summary") as Label
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
