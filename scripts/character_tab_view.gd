class_name CharacterTabView
extends "res://scripts/details_tab_view.gd"

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


func build(tabs: TabContainer, stats_window: Window) -> Dictionary:
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
