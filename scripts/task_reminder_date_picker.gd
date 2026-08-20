class_name TaskReminderDatePicker
extends PopupPanel

signal date_selected(date: String)

var _selected_date := ""
var _display_year := 0
var _display_month := 0
var _month_title: Label
var _dates_grid: GridContainer
var _theme: TaskReminderTheme
var _dragging := false
var _drag_offset := Vector2i.ZERO


func _init() -> void:
	name = "TaskReminderDatePicker"
	size = Vector2i(300, 310)
	unresizable = true
	borderless = true
	transient = true
	exclusive = false
	popup_hide.connect(func() -> void: _dragging = false)


func configure(theme: TaskReminderTheme) -> void:
	_theme = theme
	add_theme_stylebox_override("panel", _theme.panel("surface", "border_strong", 12))
	_build()


func open_for(anchor: Control, date: String) -> void:
	_selected_date = date if not date.is_empty() else Time.get_date_string_from_system(false)
	_set_display_month(_selected_date)
	var anchor_position := anchor.get_screen_position()
	position = Vector2i(anchor_position + Vector2(0, anchor.size.y + 4))
	_clamp_to_usable_screen()
	popup()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

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
	_month_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_month_title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_month_title.tooltip_text = "拖曳移動日期選擇器"
	_month_title.gui_input.connect(_on_drag_handle_input)
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


func _on_drag_handle_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = DisplayServer.mouse_get_position() - position
		_month_title.accept_event()
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion == null or not _dragging:
		return
	position = DisplayServer.mouse_get_position() - _drag_offset
	_clamp_to_usable_screen()
	_month_title.accept_event()


func _clamp_to_usable_screen() -> void:
	var screen := DisplayServer.window_get_current_screen(get_window_id())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var maximum := usable.end - size
	position = Vector2i(
		clampi(position.x, usable.position.x, maxi(usable.position.x, maximum.x)),
		clampi(position.y, usable.position.y, maxi(usable.position.y, maximum.y))
	)


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
