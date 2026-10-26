class_name TaskReminderTimePicker
extends "res://scripts/task_reminder_popup.gd"

signal time_selected(time: String)

const MINUTE_STEP := 5

var _hour := -1
var _minute := -1
var _title: Label
var _hour_buttons: Array[Button] = []
var _minute_buttons: Array[Button] = []


func _init() -> void:
	super()
	name = "TaskReminderTimePicker"
	size = Vector2i(300, 300)


func open_for(anchor: Control, time: String) -> void:
	var parts := time.split(":")
	_hour = int(parts[0]) if parts.size() == 2 else -1
	_minute = int(parts[1]) if parts.size() == 2 else -1
	_refresh_selection()
	_popup_below(anchor)


func _build() -> void:
	var content := _content_container()
	_title = Label.new()
	_title.name = "TimePickerDragHandle"
	_title.text = "選擇時間"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", _theme.color("text"))
	_make_drag_handle(_title, "拖曳移動時間選擇器")
	content.add_child(_title)
	content.add_child(_section_label("時"))
	var hours := _grid()
	content.add_child(hours)
	for hour: int in 24:
		var button := _time_button("%02d" % hour)
		button.pressed.connect(func() -> void: _choose_hour(hour))
		hours.add_child(button)
		_hour_buttons.append(button)
	content.add_child(_section_label("分"))
	var minutes := _grid()
	content.add_child(minutes)
	for minute: int in range(0, 60, MINUTE_STEP):
		var button := _time_button("%02d" % minute)
		button.set_meta("minute", minute)
		button.pressed.connect(func() -> void: _choose_minute(minute))
		minutes.add_child(button)
		_minute_buttons.append(button)
	_refresh_selection()


func _choose_hour(hour: int) -> void:
	_hour = hour
	if _minute < 0:
		_minute = 0
	_refresh_selection()
	time_selected.emit(_time_text())


# Picking the minute finishes the time, so the picker closes.
func _choose_minute(minute: int) -> void:
	_minute = minute
	if _hour < 0:
		_hour = 9
	_refresh_selection()
	time_selected.emit(_time_text())
	hide()


func _time_text() -> String:
	return "%02d:%02d" % [_hour, _minute]


func _refresh_selection() -> void:
	if _theme == null:
		return
	for hour: int in _hour_buttons.size():
		_theme.style_button(_hour_buttons[hour], "primary" if hour == _hour else "quiet")
	for button: Button in _minute_buttons:
		var minute := int(button.get_meta("minute"))
		_theme.style_button(button, "primary" if minute == _minute else "quiet")


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _theme.color("text_muted"))
	return label


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	return grid


func _time_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 32)
	return button
