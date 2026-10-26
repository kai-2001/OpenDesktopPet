class_name TaskReminderTimePicker
extends "res://scripts/task_reminder_popup.gd"

signal time_selected(time: String)

# An odd row count keeps the selected value on the middle row.
const VISIBLE_ROWS := 7
const ROW_HEIGHT := 30
const ROW_GAP := 2
const COLUMN_WIDTH := 76

var _hour := 0
var _minute := 0
var _hour_scroll: ScrollContainer
var _minute_scroll: ScrollContainer
var _hour_buttons: Array[Button] = []
var _minute_buttons: Array[Button] = []


func _init() -> void:
	super()
	name = "TaskReminderTimePicker"
	size = Vector2i(204, 300)


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
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 10)
	content.add_child(columns)
	_hour_scroll = _column(columns, "時", 24, _hour_buttons, _choose_hour)
	var divider := VSeparator.new()
	var divider_line := StyleBoxLine.new()
	divider_line.color = _theme.color("border")
	divider_line.vertical = true
	divider.add_theme_stylebox_override("separator", divider_line)
	columns.add_child(divider)
	_minute_scroll = _column(columns, "分", 60, _minute_buttons, _choose_minute)
	_refresh_selection()


func _column(
	parent: Control, heading: String, count: int, buttons: Array[Button], chosen: Callable
) -> ScrollContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var label := Label.new()
	label.text = heading
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _theme.color("text_muted"))
	column.add_child(label)
	# The scroll bar is hidden like common time pickers; the wheel and
	# dragging still scroll.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = VISIBLE_ROWS * (ROW_HEIGHT + ROW_GAP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ROW_GAP)
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
		_style_row(_hour_buttons[hour], hour == _hour)
	for minute: int in _minute_buttons.size():
		_style_row(_minute_buttons[minute], minute == _minute)


func _style_row(button: Button, selected: bool) -> void:
	_theme.style_button(button, "primary" if selected else "quiet")
	# Buttons take the height of their tallest state, including states left
	# to the default theme, so give every state the same compact style.
	var compact := {}
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := (button.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		compact[state] = style
	compact["hover_pressed"] = compact["pressed"]
	for state: String in compact.keys():
		button.add_theme_stylebox_override(state, compact[state])
		if state != "focus":
			button.add_theme_stylebox_override(state + "_mirrored", compact[state])


# Centre each column on its selected value; values near either end stop at
# the edge. Set it again once the popup has laid out, because a scroll
# container clamps offsets to its current content.
func _scroll_to_selection() -> void:
	_apply_scroll()
	await get_tree().process_frame
	if visible:
		_apply_scroll()


# Re-sort as well: an offset set while the popup was hidden is stored but the
# rows are not moved, and setting the same offset again does not move them.
func _apply_scroll() -> void:
	_hour_scroll.scroll_vertical = _centred_offset(_hour)
	_minute_scroll.scroll_vertical = _centred_offset(_minute)
	_hour_scroll.queue_sort()
	_minute_scroll.queue_sort()


func _centred_offset(index: int) -> int:
	return maxi(0, (index - VISIBLE_ROWS / 2) * (ROW_HEIGHT + ROW_GAP))
