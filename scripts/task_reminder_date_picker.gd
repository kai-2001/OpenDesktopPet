class_name TaskReminderDatePicker
extends "res://scripts/task_reminder_popup.gd"

signal date_selected(date: String)

var _selected_date := ""
var _display_year := 0
var _display_month := 0
var _month_title: Label
var _dates_grid: GridContainer


func _init() -> void:
	super()
	name = "TaskReminderDatePicker"
	size = Vector2i(300, 310)


func open_for(anchor: Control, date: String) -> void:
	_selected_date = date if not date.is_empty() else Time.get_date_string_from_system(false)
	_set_display_month(_selected_date)
	_popup_below(anchor)


func _build() -> void:
	var content := _content_container()

	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 6)
	content.add_child(navigation)
	var previous := Button.new()
	previous.text = "上個月"
	previous.custom_minimum_size.x = 36
	previous.tooltip_text = "顯示上個月"
	_theme.style_button(previous, "quiet")
	previous.pressed.connect(func() -> void: _shift_month(-1))
	navigation.add_child(previous)
	_month_title = Label.new()
	_month_title.name = "DatePickerDragHandle"
	_month_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_month_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_month_title.add_theme_font_size_override("font_size", 15)
	_month_title.add_theme_color_override("font_color", _theme.color("text"))
	_make_drag_handle(_month_title, "拖曳移動日期選擇器")
	navigation.add_child(_month_title)
	var next := Button.new()
	next.text = "下個月"
	next.custom_minimum_size.x = 36
	next.tooltip_text = "顯示下個月"
	_theme.style_button(next, "quiet")
	next.pressed.connect(func() -> void: _shift_month(1))
	navigation.add_child(next)

	var weekdays := GridContainer.new()
	weekdays.columns = 7
	for weekday: String in ["日", "一", "二", "三", "四", "五", "六"]:
		var label := Label.new()
		label.text = weekday
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 36
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", _theme.color("text_muted"))
		weekdays.add_child(label)
	content.add_child(weekdays)

	_dates_grid = GridContainer.new()
	_dates_grid.columns = 7
	_dates_grid.add_theme_constant_override("h_separation", 2)
	_dates_grid.add_theme_constant_override("v_separation", 2)
	content.add_child(_dates_grid)


func _set_display_month(date: String) -> void:
	var parts := date.split("-")
	if parts.size() < 3:
		date = Time.get_date_string_from_system(false)
		parts = date.split("-")
	_display_year = int(parts[0])
	_display_month = int(parts[1])
	_rebuild_dates()


func _shift_month(offset: int) -> void:
	_display_month += offset
	if _display_month < 1:
		_display_month = 12
		_display_year -= 1
	elif _display_month > 12:
		_display_month = 1
		_display_year += 1
	_rebuild_dates()


func _rebuild_dates() -> void:
	if not is_instance_valid(_dates_grid):
		return
	for child: Node in _dates_grid.get_children():
		child.queue_free()
	_month_title.text = "%04d 年 %02d 月" % [_display_year, _display_month]
	var first_weekday := _weekday(_display_year, _display_month, 1)
	for _index: int in first_weekday:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(36, 34)
		_dates_grid.add_child(spacer)
	for day: int in range(1, _days_in_month(_display_year, _display_month) + 1):
		var button := Button.new()
		button.text = str(day)
		button.custom_minimum_size = Vector2(36, 34)
		var date := "%04d-%02d-%02d" % [_display_year, _display_month, day]
		_theme.style_button(button, "quiet")
		if date == Time.get_date_string_from_system(false):
			button.add_theme_color_override("font_color", _theme.color("accent"))
			button.tooltip_text = "今天"
		button.set_meta("date", date)
		button.pressed.connect(func() -> void: _choose_date(date))
		_dates_grid.add_child(button)


func _choose_date(date: String) -> void:
	_selected_date = date
	date_selected.emit(date)
	hide()


func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if _is_leap_year(year) else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31


func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


func _weekday(year: int, month: int, day: int) -> int:
	var timestamp := Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": 0,
		"minute": 0,
		"second": 0,
	})
	var datetime := Time.get_datetime_dict_from_unix_time(timestamp)
	return int(datetime.get("weekday", 0))
