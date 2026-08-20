class_name TaskReminderPanel
extends VBoxContainer

const TaskReminderDatePickerScript = preload("res://scripts/task_reminder_date_picker.gd")
const TaskReminderSectionScript = preload("res://scripts/task_reminder_section.gd")
const TaskReminderThemeScript = preload("res://scripts/task_reminder_theme.gd")

var _coordinator
var _theme: TaskReminderTheme
var _summary: Label
var _scope_buttons: Dictionary = {}
var _active_scope := "today"
var _overdue_count := 0
var _overdue_section: TaskReminderSection
var _today_section: TaskReminderSection
var _upcoming_section: TaskReminderSection
var _completed_section: TaskReminderSection
var _form_panel: PanelContainer
var _form_title: Label
var _title_edit: LineEdit
var _date_button: Button
var _time_edit: LineEdit
var _all_day_check_box: CheckBox
var _form_feedback: Label
var _date_picker: TaskReminderDatePicker
var _editing_id := ""
var _editing_date := ""


func configure(coordinator, theme_mode: String) -> void:
	_coordinator = coordinator
	_theme = TaskReminderThemeScript.new(theme_mode)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	_build()
	_coordinator.reminders_changed.connect(_refresh)
	_refresh()


func focus_reminder(reminder_id: String) -> void:
	if _coordinator == null:
		return
	var reminder: Dictionary = _coordinator.get_reminder(reminder_id)
	if reminder.is_empty():
		return
	var status := String(reminder.get("status", "todo"))
	var due_date := String(reminder.get("due_date", ""))
	if status == "done":
		_set_scope("completed")
	elif due_date > Time.get_date_string_from_system(false):
		_set_scope("upcoming")
	else:
		_set_scope("today")
	for section: TaskReminderSection in [
		_overdue_section, _today_section, _upcoming_section, _completed_section
	]:
		if section.focus_reminder(reminder_id):
			break
	_show_edit_form(reminder)


func show_new_form() -> void:
	_show_new_form()


func _build() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	var heading_stack := VBoxContainer.new()
	heading_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_stack.add_theme_constant_override("separation", 3)
	header.add_child(heading_stack)
	heading_stack.add_child(_label("待辦提醒", 24, "text"))
	_summary = _label("", 13, "text_muted")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_stack.add_child(_summary)
	var add_button := Button.new()
	add_button.name = "AddReminderButton"
	add_button.text = "新增待辦"
	add_button.custom_minimum_size = Vector2(112, 40)
	_theme.style_button(add_button, "primary")
	add_button.pressed.connect(_show_new_form)
	header.add_child(add_button)

	var scope_bar := HFlowContainer.new()
	scope_bar.name = "ReminderScopeBar"
	scope_bar.add_theme_constant_override("h_separation", 8)
	scope_bar.add_theme_constant_override("v_separation", 8)
	add_child(scope_bar)
	for scope: Dictionary in [
		{"id": "today", "label": "今天"},
		{"id": "upcoming", "label": "接下來"},
		{"id": "completed", "label": "已完成"},
		{"id": "all", "label": "全部"},
	]:
		var scope_button := Button.new()
		scope_button.custom_minimum_size = Vector2(88, 36)
		var scope_id := String(scope["id"])
		scope_button.set_meta("label", String(scope["label"]))
		scope_button.pressed.connect(func() -> void: _set_scope(scope_id))
		scope_bar.add_child(scope_button)
		_scope_buttons[scope_id] = scope_button

	_form_panel = PanelContainer.new()
	_form_panel.name = "ReminderEditor"
	_form_panel.add_theme_stylebox_override("panel", _theme.panel("surface", "border_strong", 12))
	_form_panel.visible = false
	add_child(_form_panel)
	_build_form()

	_overdue_section = _add_section(
		"已逾期", "超過日期且仍待完成，優先顯示在最前面。", "沒有逾期事項。", 4, false
	)
	_today_section = _add_section(
		"今天", "今天真正需要處理的清單。", "今天沒有待完成事項，可以新增一件。", 6, false
	)
	_upcoming_section = _add_section(
		"接下來", "依日期排列未來事項，需要時再逐批展開。", "目前沒有未來待辦。", 6, false
	)
	_completed_section = _add_section(
		"已完成", "完成紀錄預設收合，不干擾目前待辦。", "還沒有已完成的待辦。", 6, true
	)

	_date_picker = TaskReminderDatePickerScript.new()
	_date_picker.configure(_theme)
	add_child(_date_picker)
	_date_picker.date_selected.connect(_on_date_selected)


func _add_section(
	title: String,
	description: String,
	empty_text: String,
	page_size: int,
	default_collapsed: bool
) -> TaskReminderSection:
	var section := TaskReminderSectionScript.new()
	section.configure(title, description, empty_text, _theme, page_size, default_collapsed)
	section.edit_requested.connect(_show_edit_form)
	section.status_requested.connect(_set_status)
	section.delete_requested.connect(_delete_reminder)
	section.move_to_today_requested.connect(_move_to_today)
	add_child(section)
	return section


func _build_form() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_form_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var form_header := HBoxContainer.new()
	content.add_child(form_header)
	_form_title = _label("新增待辦", 18, "text")
	_form_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_header.add_child(_form_title)
	var close_button := Button.new()
	close_button.text = "關閉"
	close_button.custom_minimum_size = Vector2(64, 34)
	_theme.style_button(close_button, "quiet")
	close_button.pressed.connect(_hide_form)
	form_header.add_child(close_button)

	_title_edit = LineEdit.new()
	_title_edit.name = "ReminderTitle"
	_title_edit.placeholder_text = "例如：回覆合作信件"
	_title_edit.custom_minimum_size.y = 40
	_title_edit.text_submitted.connect(func(_text: String) -> void: _save_form())
	_theme.style_input(_title_edit)
	content.add_child(_field_with_label("要做什麼", _title_edit))

	var date_content := VBoxContainer.new()
	date_content.add_theme_constant_override("separation", 7)
	_date_button = Button.new()
	_date_button.name = "ReminderDate"
	_date_button.custom_minimum_size.y = 40
	_date_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_theme.style_button(_date_button, "secondary")
	_date_button.pressed.connect(func() -> void:
		_date_picker.open_for(_date_button, _editing_date)
	)
	date_content.add_child(_date_button)
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 7)
	presets.add_theme_constant_override("v_separation", 7)
	for preset: Dictionary in [
		{"label": "今天", "days": 0},
		{"label": "明天", "days": 1},
		{"label": "一週後", "days": 7},
	]:
		var preset_button := Button.new()
		preset_button.text = String(preset["label"])
		preset_button.custom_minimum_size.y = 32
		_theme.style_button(preset_button, "quiet")
		var days := int(preset["days"])
		preset_button.pressed.connect(func() -> void: _set_relative_date(days))
		presets.add_child(preset_button)
	date_content.add_child(presets)
	content.add_child(_field_with_label("安排日期", date_content))

	var schedule_row := HBoxContainer.new()
	schedule_row.add_theme_constant_override("separation", 10)
	_all_day_check_box = CheckBox.new()
	_all_day_check_box.name = "ReminderAllDay"
	_all_day_check_box.text = "整日"
	_all_day_check_box.custom_minimum_size.y = 40
	_theme.style_button(_all_day_check_box, "secondary")
	_all_day_check_box.toggled.connect(_on_all_day_toggled)
	schedule_row.add_child(_all_day_check_box)
	_time_edit = LineEdit.new()
	_time_edit.name = "ReminderTime"
	_time_edit.placeholder_text = "09:30"
	_time_edit.custom_minimum_size = Vector2(110, 40)
	_time_edit.max_length = 5
	_theme.style_input(_time_edit)
	schedule_row.add_child(_time_edit)
	schedule_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_field_with_label("提醒時間", schedule_row))

	_form_feedback = _label("", 13, "danger")
	_form_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_form_feedback)

	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_END
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)
	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(88, 38)
	_theme.style_button(cancel_button, "secondary")
	cancel_button.pressed.connect(_hide_form)
	actions.add_child(cancel_button)
	var save_button := Button.new()
	save_button.name = "SaveReminderButton"
	save_button.text = "加入待辦"
	save_button.custom_minimum_size = Vector2(112, 38)
	_theme.style_button(save_button, "primary")
	save_button.pressed.connect(_save_form)
	actions.add_child(save_button)


func _field_with_label(label_text: String, control: Control) -> VBoxContainer:
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 5)
	field.add_child(_label(label_text, 13, "text_muted"))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(control)
	return field


func _refresh() -> void:
	if not is_instance_valid(_today_section):
		return
	var overdue: Array[Dictionary] = _coordinator.get_overdue_reminders()
	var today: Array[Dictionary] = _coordinator.get_open_today_reminders()
	var upcoming: Array[Dictionary] = _coordinator.get_upcoming_reminders()
	var completed: Array[Dictionary] = _coordinator.get_completed_reminders()
	_overdue_count = overdue.size()
	_summary.text = _summary_text(overdue.size(), today.size(), upcoming.size())
	_overdue_section.set_items(overdue)
	_today_section.set_items(today)
	_upcoming_section.set_items(upcoming)
	_completed_section.set_items(completed)
	_update_scope_labels(today.size(), upcoming.size(), completed.size())
	_apply_scope()


func _summary_text(overdue_count: int, today_count: int, upcoming_count: int) -> String:
	var parts: Array[String] = ["今天 %d 件" % today_count]
	if overdue_count > 0:
		parts.append("逾期 %d 件" % overdue_count)
	if upcoming_count > 0:
		parts.append("未來 %d 件" % upcoming_count)
	return "，".join(parts) + "。點待辦標題可展開快捷操作。"


func _set_scope(scope: String) -> void:
	_active_scope = scope
	_apply_scope()


func _apply_scope() -> void:
	_overdue_section.visible = _overdue_count > 0 and _active_scope in ["today", "all"]
	_today_section.visible = _active_scope in ["today", "all"]
	_upcoming_section.visible = _active_scope in ["upcoming", "all"]
	_completed_section.visible = _active_scope in ["completed", "all"]
	for scope_id: String in _scope_buttons:
		var button := _scope_buttons[scope_id] as Button
		_theme.style_button(button, "primary" if scope_id == _active_scope else "secondary")


func _update_scope_labels(today_count: int, upcoming_count: int, completed_count: int) -> void:
	var counts := {
		"today": today_count + _overdue_count,
		"upcoming": upcoming_count,
		"completed": completed_count,
		"all": today_count + _overdue_count + upcoming_count + completed_count,
	}
	for scope_id: String in _scope_buttons:
		var button := _scope_buttons[scope_id] as Button
		button.text = "%s %d" % [String(button.get_meta("label", "")), int(counts[scope_id])]


func _show_new_form() -> void:
	_editing_id = ""
	_editing_date = Time.get_date_string_from_system(false)
	_form_title.text = "新增待辦"
	_title_edit.text = ""
	_date_button.text = _editing_date
	_time_edit.text = ""
	_all_day_check_box.set_pressed_no_signal(true)
	_form_feedback.text = ""
	_form_panel.visible = true
	_on_all_day_toggled(true)
	_title_edit.grab_focus()


func _show_edit_form(reminder: Dictionary) -> void:
	_editing_id = String(reminder.get("id", ""))
	_editing_date = String(reminder.get("due_date", Time.get_date_string_from_system(false)))
	_form_title.text = "編輯待辦"
	_title_edit.text = String(reminder.get("title", ""))
	_date_button.text = _editing_date
	_time_edit.text = String(reminder.get("due_time", ""))
	_all_day_check_box.set_pressed_no_signal(bool(reminder.get("all_day", false)))
	_form_feedback.text = ""
	_form_panel.visible = true
	_on_all_day_toggled(_all_day_check_box.button_pressed)
	_title_edit.grab_focus()


func _save_form() -> void:
	var title := _title_edit.text.strip_edges()
	if title.is_empty():
		_form_feedback.text = "請輸入待辦內容，才能加入清單。"
		_title_edit.grab_focus()
		return
	var all_day := _all_day_check_box.button_pressed
	var due_time := "" if all_day else _time_edit.text.strip_edges()
	if not all_day and due_time.is_empty():
		_form_feedback.text = "請輸入提醒時間，或改選「整日」。"
		_time_edit.grab_focus()
		return
	if not all_day and not _is_valid_time(due_time):
		_form_feedback.text = "時間格式需為 HH:MM，例如 09:30。"
		_time_edit.grab_focus()
		return
	var result: Dictionary
	if _editing_id.is_empty():
		result = _coordinator.create_reminder(title, _editing_date, due_time, all_day)
	else:
		result = _coordinator.update_reminder(_editing_id, {
			"title": title,
			"due_date": _editing_date,
			"due_time": due_time,
			"all_day": all_day,
		})
	if result.is_empty():
		_form_feedback.text = "無法保存，請確認資料後再試一次。"
		return
	_hide_form()


func _hide_form() -> void:
	_form_panel.visible = false
	_editing_id = ""
	_form_feedback.text = ""


func _set_status(id: String, status: String) -> void:
	_coordinator.set_status(id, status)


func _move_to_today(id: String) -> void:
	_coordinator.update_reminder(id, {"due_date": Time.get_date_string_from_system(false)})


func _delete_reminder(id: String) -> void:
	_coordinator.delete_reminder(id)
	if _editing_id == id:
		_hide_form()


func _set_relative_date(days: int) -> void:
	var today := Time.get_datetime_dict_from_system(false)
	var timestamp := Time.get_unix_time_from_datetime_dict(today) + days * 86400
	var target := Time.get_datetime_dict_from_unix_time(timestamp)
	_on_date_selected("%04d-%02d-%02d" % [target.year, target.month, target.day])


func _on_date_selected(date: String) -> void:
	_editing_date = date
	_date_button.text = date


func _on_all_day_toggled(enabled: bool) -> void:
	if not is_instance_valid(_time_edit):
		return
	_time_edit.editable = not enabled
	_time_edit.modulate = _theme.color("text_faint") if enabled else Color.WHITE
	_time_edit.placeholder_text = "不需時間" if enabled else "09:30"


func _is_valid_time(value: String) -> bool:
	var parts := value.split(":")
	if parts.size() != 2 or parts[0].length() != 2 or parts[1].length() != 2:
		return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	var hour := int(parts[0])
	var minute := int(parts[1])
	return hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59


func _label(text: String, font_size: int, color_role: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", _theme.color(color_role))
	return label
