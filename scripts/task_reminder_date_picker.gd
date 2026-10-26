class_name TaskReminderDatePicker
extends "res://scripts/task_reminder_popup.gd"

signal date_selected(date: String)

const CELL_SIZE := Vector2(36, 34)
# Six weeks always fit a month, so the popup never changes height.
const CELL_COUNT := 42

var _selected_date := ""
var _display_year := 0
var _display_month := 0
var _month_title: Label
var _dates_grid: GridContainer


func _init() -> void:
	super()
	name = "TaskReminderDatePicker"
	size = Vector2i(300, 360)


func open_for(anchor: Control, date: String) -> void:
	var today := _today()
	_selected_date = TaskReminderDateTime.parse_date(date, today)
	if _selected_date.is_empty():
		_selected_date = today
	_set_display_month(_selected_date)
	_popup_below(anchor)
	_focus_date.call_deferred(_selected_date)


func _build() -> void:
	var content := _content_container()

	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 6)
	content.add_child(navigation)
	navigation.add_child(_navigation_button("‹", "上個月（Page Up）", -1))
	_month_title = Label.new()
	_month_title.name = "DatePickerDragHandle"
	_month_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_month_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_month_title.add_theme_font_size_override("font_size", 15)
	_month_title.add_theme_color_override("font_color", _theme.color("text"))
	_make_drag_handle(_month_title, "拖曳移動日期選擇器")
	navigation.add_child(_month_title)
	navigation.add_child(_navigation_button("›", "下個月（Page Down）", 1))

	_dates_grid = GridContainer.new()
	_dates_grid.columns = 7
	_dates_grid.add_theme_constant_override("h_separation", 2)
	_dates_grid.add_theme_constant_override("v_separation", 2)
	content.add_child(_dates_grid)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(footer)
	var today_button := Button.new()
	today_button.name = "DatePickerToday"
	today_button.text = "今天"
	today_button.custom_minimum_size = Vector2(64, 30)
	_theme.style_button(today_button, "secondary")
	today_button.pressed.connect(func() -> void: _choose_date(_today()))
	footer.add_child(today_button)


func _navigation_button(text: String, tooltip: String, offset: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36, 32)
	button.tooltip_text = tooltip
	button.add_theme_font_size_override("font_size", 18)
	_theme.style_button(button, "quiet")
	button.pressed.connect(func() -> void: _shift_month(offset))
	return button


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not visible:
		return
	match key.keycode:
		KEY_PAGEUP:
			_shift_month(-1)
		KEY_PAGEDOWN:
			_shift_month(1)
		_:
			return
	set_input_as_handled()


func _set_display_month(date: String) -> void:
	_display_year = int(date.left(4))
	_display_month = int(date.substr(5, 2))
	_rebuild_dates()


func _shift_month(offset: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var day := 1
	if focused != null and focused.has_meta("date"):
		day = int(String(focused.get_meta("date")).right(2))
	var shifted := TaskReminderDateTime.step_date(
		TaskReminderDateTime.format_date(_display_year, _display_month, 1), 1, offset
	)
	_set_display_month(shifted)
	if focused != null and focused.has_meta("date"):
		_focus_date.call_deferred(TaskReminderDateTime.format_date(
			_display_year, _display_month,
			mini(day, TaskReminderDateTime.days_in_month(_display_year, _display_month))
		))


func _rebuild_dates() -> void:
	if not is_instance_valid(_dates_grid):
		return
	for child: Node in _dates_grid.get_children():
		_dates_grid.remove_child(child)
		child.queue_free()
	_month_title.text = "%04d 年 %02d 月" % [_display_year, _display_month]
	# Weekday names share the grid so their columns match the dates.
	for weekday: String in ["日", "一", "二", "三", "四", "五", "六"]:
		var label := Label.new()
		label.text = weekday
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", _theme.color("text_muted"))
		_dates_grid.add_child(label)
	var first := TaskReminderDateTime.format_date(_display_year, _display_month, 1)
	var start := TaskReminderDateTime.add_days(first, -TaskReminderDateTime.weekday(first))
	var today := _today()
	for index: int in CELL_COUNT:
		var date := TaskReminderDateTime.add_days(start, index)
		var in_month := int(date.substr(5, 2)) == _display_month
		var button := Button.new()
		button.text = str(int(date.right(2)))
		button.custom_minimum_size = CELL_SIZE
		button.set_meta("date", date)
		_theme.style_button(button, "primary" if date == _selected_date else "quiet")
		if date != _selected_date:
			if date == today:
				button.add_theme_stylebox_override("normal", _theme.panel("surface", "accent", 8))
				button.add_theme_color_override("font_color", _theme.color("accent"))
			elif not in_month:
				button.add_theme_color_override("font_color", _theme.color("text_faint"))
		if date == today:
			button.tooltip_text = "今天"
		button.pressed.connect(func() -> void: _choose_date(date))
		_dates_grid.add_child(button)


func _focus_date(date: String) -> void:
	for child: Node in _dates_grid.get_children():
		if String(child.get_meta("date", "")) == date:
			(child as Button).grab_focus()
			return


func _choose_date(date: String) -> void:
	_selected_date = date
	date_selected.emit(date)
	hide()


func _today() -> String:
	return Time.get_date_string_from_system(false)
