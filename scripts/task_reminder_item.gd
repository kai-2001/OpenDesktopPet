class_name TaskReminderItem
extends PanelContainer

signal edit_requested(reminder: Dictionary)
signal status_requested(id: String, status: String)
signal delete_requested(id: String)
signal move_to_today_requested(id: String)

var reminder: Dictionary = {}
var _theme: TaskReminderTheme
var _today := ""
var _details: VBoxContainer
var _expand_button: Button
var _delete_button: Button
var _delete_reset_timer: Timer
var _delete_armed := false


func configure(value: Dictionary, theme: TaskReminderTheme, today: String) -> void:
	reminder = value.duplicate(true)
	_theme = theme
	_today = today
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", _theme.panel())
	_build()


func expand() -> void:
	_details.visible = true
	_expand_button.text = "收起"


func _build() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 8)
	content.add_child(main_row)

	var status := String(reminder.get("status", "todo"))
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 2)
	main_row.add_child(title_stack)

	var title := Button.new()
	title.name = "ReminderTitleButton"
	title.text = String(reminder.get("title", ""))
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = "展開待辦操作"
	title.add_theme_font_size_override("font_size", 15)
	_theme.style_button(title, "quiet")
	title.pressed.connect(_toggle_details)
	title_stack.add_child(title)

	var meta := Label.new()
	meta.text = _meta_text()
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", _meta_color())
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_stack.add_child(meta)

	var status_label := Label.new()
	status_label.text = _status_text(status)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", _status_color(status))
	status_label.add_theme_stylebox_override("normal", _theme.chip(_status_background(status)))
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_row.add_child(status_label)

	_expand_button = Button.new()
	_expand_button.text = "操作"
	_expand_button.custom_minimum_size = Vector2(58, 34)
	_theme.style_button(_expand_button, "secondary")
	_expand_button.pressed.connect(_toggle_details)
	main_row.add_child(_expand_button)

	_details = VBoxContainer.new()
	_details.visible = false
	_details.add_theme_constant_override("separation", 8)
	content.add_child(_details)

	var separator := HSeparator.new()
	_details.add_child(separator)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	_details.add_child(actions)

	var completion_button := _action_button(
		"恢復待完成" if status == "done" else "完成待辦",
		"secondary" if status == "done" else "primary"
	)
	completion_button.name = "ReminderCompletionAction"
	completion_button.pressed.connect(func() -> void:
		status_requested.emit(_id(), "todo" if status == "done" else "done")
	)
	actions.add_child(completion_button)
	if String(reminder.get("due_date", "")) != _today:
		var today_button := _action_button("移到今天")
		today_button.pressed.connect(func() -> void: move_to_today_requested.emit(_id()))
		actions.add_child(today_button)
	var edit_button := _action_button("編輯內容")
	edit_button.pressed.connect(func() -> void: edit_requested.emit(reminder))
	actions.add_child(edit_button)
	_delete_button = _action_button("刪除", "danger")
	_delete_button.pressed.connect(_request_delete)
	actions.add_child(_delete_button)
	_delete_reset_timer = Timer.new()
	_delete_reset_timer.one_shot = true
	_delete_reset_timer.wait_time = 4.0
	_delete_reset_timer.timeout.connect(_reset_delete_confirmation)
	add_child(_delete_reset_timer)


func _toggle_details() -> void:
	_details.visible = not _details.visible
	_expand_button.text = "收起" if _details.visible else "操作"
	if not _details.visible:
		_reset_delete_confirmation()


func _request_delete() -> void:
	if not _delete_armed:
		_delete_armed = true
		_delete_button.text = "再按一次刪除"
		_delete_button.tooltip_text = "四秒內再按一次；此操作無法復原"
		_delete_reset_timer.start()
		return
	delete_requested.emit(_id())


func _reset_delete_confirmation() -> void:
	_delete_armed = false
	if is_instance_valid(_delete_reset_timer):
		_delete_reset_timer.stop()
	if is_instance_valid(_delete_button):
		_delete_button.text = "刪除"
		_delete_button.tooltip_text = ""


func _action_button(text: String, kind := "secondary") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	_theme.style_button(button, kind)
	return button


func _id() -> String:
	return String(reminder.get("id", ""))


func _meta_text() -> String:
	var date := String(reminder.get("due_date", ""))
	var date_text := "今天" if date == _today else date
	var time_text := "整日" if bool(reminder.get("all_day", false)) else String(reminder.get("due_time", ""))
	return "%s · %s" % [date_text, time_text if not time_text.is_empty() else "未指定時間"]


func _meta_color() -> Color:
	var due_date := String(reminder.get("due_date", ""))
	if due_date < _today and String(reminder.get("status", "todo")) != "done":
		return _theme.color("danger")
	return _theme.color("text_muted")


func _status_text(status: String) -> String:
	return String({
		"todo": "待完成",
		"done": "已完成",
	}.get(status, "待完成"))


func _status_role(status: String) -> String:
	return "success" if status == "done" else "text_muted"


func _status_background(status: String) -> String:
	return "success_soft" if status == "done" else "surface_subtle"


func _status_color(status: String) -> Color:
	return _theme.color(_status_role(status))
