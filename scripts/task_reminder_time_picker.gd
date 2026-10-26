class_name TaskReminderTimePicker
extends "res://scripts/task_reminder_popup.gd"

signal time_selected(time: String)

const VISIBLE_ROWS := 7
const ROW_HEIGHT := 32

var _hour := 0
var _minute := 0
var _hour_scroll: ScrollContainer
var _minute_scroll: ScrollContainer
var _hour_buttons: Array[Button] = []
var _minute_buttons: Array[Button] = []


func _init() -> void:
	super()
	name = "TaskReminderTimePicker"
	size = Vector2i(220, 330)


func open_for(anchor: Control, time: String) -> void:
	var valid := TaskReminderDateTime.parse_time(time)
	if valid.is_empty():
		valid = _now()
	_hour = int(valid.left(2))
	_minute = int(valid.right(2))
	_refresh_selection()
	_popup_below(anchor)
	_scroll_to_selection()


func _build() -> void:
	var content := _content_container()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	content.add_child(header)
	var title := Label.new()
	title.name = "TimePickerDragHandle"
	title.text = "選擇時間"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _theme.color("text"))
	_make_drag_handle(title, "拖曳移動時間選擇器")
	header.add_child(title)
	var now_button := Button.new()
	now_button.name = "TimePickerNow"
	now_button.text = "現在"
	now_button.custom_minimum_size = Vector2(56, 30)
	_theme.style_button(now_button, "secondary")
	now_button.pressed.connect(_choose_now)
	header.add_child(now_button)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	content.add_child(columns)
	_hour_scroll = _column(columns, "時", 24, _hour_buttons, _choose_hour)
	_minute_scroll = _column(columns, "分", 60, _minute_buttons, _choose_minute)
	_refresh_selection()


func _column(
	parent: Control, heading: String, count: int, buttons: Array[Button], chosen: Callable
) -> ScrollContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var label := Label.new()
	label.text = heading
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _theme.color("text_muted"))
	column.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = VISIBLE_ROWS * (ROW_HEIGHT + 2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for value: int in count:
		var button := Button.new()
		button.text = "%02d" % value
		button.custom_minimum_size.y = ROW_HEIGHT
		button.pressed.connect(func() -> void: chosen.call(value))
		list.add_child(button)
		buttons.append(button)
	return scroll


func _choose_hour(hour: int) -> void:
	_hour = hour
	_refresh_selection()
	time_selected.emit(_time_text())


# Choosing the minute completes the time, as in common desktop pickers.
func _choose_minute(minute: int) -> void:
	_minute = minute
	_refresh_selection()
	time_selected.emit(_time_text())
	hide()


func _choose_now() -> void:
	var now := _now()
	_hour = int(now.left(2))
	_minute = int(now.right(2))
	time_selected.emit(now)
	hide()


func _time_text() -> String:
	return "%02d:%02d" % [_hour, _minute]


func _now() -> String:
	var now := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]


func _refresh_selection() -> void:
	for hour: int in _hour_buttons.size():
		_theme.style_button(_hour_buttons[hour], "primary" if hour == _hour else "quiet")
	for minute: int in _minute_buttons.size():
		_theme.style_button(_minute_buttons[minute], "primary" if minute == _minute else "quiet")


# Centre each column on its selected value once the popup has laid out.
func _scroll_to_selection() -> void:
	await get_tree().process_frame
	if not visible:
		return
	for pair: Array in [[_hour_scroll, _hour_buttons[_hour]], [_minute_scroll, _minute_buttons[_minute]]]:
		var scroll := pair[0] as ScrollContainer
		var button := pair[1] as Button
		scroll.scroll_vertical = int(button.position.y - (scroll.size.y - button.size.y) / 2.0)
