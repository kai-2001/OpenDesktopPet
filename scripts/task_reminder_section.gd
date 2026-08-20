class_name TaskReminderSection
extends VBoxContainer

const TaskReminderItemScript = preload("res://scripts/task_reminder_item.gd")

signal edit_requested(reminder: Dictionary)
signal status_requested(id: String, status: String)
signal delete_requested(id: String)
signal move_to_today_requested(id: String)

var _theme: TaskReminderTheme
var _title := ""
var _empty_text := ""
var _page_size := 6
var _visible_count := 6
var _collapsed := false
var _items: Array[Dictionary] = []
var _header_button: Button
var _header_title: Label
var _header_state: Label
var _header_chevron: Label
var _description_label: Label
var _list: VBoxContainer
var _more_button: Button


func configure(
	title: String,
	description: String,
	empty_text: String,
	theme: TaskReminderTheme,
	page_size := 6,
	default_collapsed := false
) -> void:
	_title = title
	_empty_text = empty_text
	_theme = theme
	_page_size = page_size
	_visible_count = page_size
	_collapsed = default_collapsed
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build(description)


func set_items(items: Array[Dictionary]) -> void:
	_items = items
	_visible_count = maxi(_page_size, mini(_visible_count, _items.size()))
	_render()


func focus_reminder(reminder_id: String) -> bool:
	for index: int in _items.size():
		if String(_items[index].get("id", "")) != reminder_id:
			continue
		_collapsed = false
		_visible_count = maxi(_visible_count, index + 1)
		_render()
		for child: Node in _list.get_children():
			if child is TaskReminderItem and String(child.reminder.get("id", "")) == reminder_id:
				child.expand()
				child.grab_focus()
			return true
	return false


func _build(description: String) -> void:
	_header_button = Button.new()
	_header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_button.custom_minimum_size.y = 38
	_header_button.tooltip_text = "展開或收合這個區塊"
	_theme.style_disclosure_header(_header_button)
	_header_button.pressed.connect(func() -> void:
		_collapsed = not _collapsed
		_render()
	)
	var header_margin := MarginContainer.new()
	header_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 10)
	var header_content := HBoxContainer.new()
	header_content.add_theme_constant_override("separation", 6)
	header_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_margin.add_child(header_content)
	_header_title = Label.new()
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_title.add_theme_font_size_override("font_size", 17)
	_header_title.add_theme_color_override("font_color", _theme.color("text"))
	_header_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_content.add_child(_header_title)
	_header_state = Label.new()
	_header_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_state.add_theme_font_size_override("font_size", 14)
	_header_state.add_theme_color_override("font_color", _theme.color("text_muted"))
	_header_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_content.add_child(_header_state)
	_header_chevron = Label.new()
	_header_chevron.custom_minimum_size.x = 18
	_header_chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_chevron.add_theme_font_size_override("font_size", 16)
	_header_chevron.add_theme_color_override("font_color", _theme.color("text_faint"))
	_header_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_content.add_child(_header_chevron)
	_header_button.add_child(header_margin)
	add_child(_header_button)

	_description_label = Label.new()
	_description_label.text = description
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.add_theme_font_size_override("font_size", 12)
	_description_label.add_theme_color_override("font_color", _theme.color("text_muted"))
	add_child(_description_label)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 7)
	add_child(_list)

	_more_button = Button.new()
	_more_button.custom_minimum_size.y = 36
	_theme.style_button(_more_button, "secondary")
	_more_button.pressed.connect(func() -> void:
		_visible_count += _page_size
		_render()
	)
	add_child(_more_button)


func _render() -> void:
	if not is_instance_valid(_list):
		return
	_header_title.text = "%s　%d 件" % [_title, _items.size()]
	_header_state.text = "展開" if _collapsed else "收合"
	_header_chevron.text = "▾" if _collapsed else "▴"
	_description_label.visible = not _collapsed and not _description_label.text.is_empty()
	_list.visible = not _collapsed
	_more_button.visible = not _collapsed and _items.size() > _visible_count
	_more_button.text = "再顯示 %d 件" % mini(_page_size, _items.size() - _visible_count)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _collapsed:
		return
	if _items.is_empty():
		var empty := Label.new()
		empty.text = _empty_text
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", _theme.color("text_muted"))
		_list.add_child(empty)
		return
	for reminder: Dictionary in _items.slice(0, mini(_visible_count, _items.size())):
		var item := TaskReminderItemScript.new()
		item.configure(reminder, _theme, Time.get_date_string_from_system(false))
		item.edit_requested.connect(func(value: Dictionary) -> void: edit_requested.emit(value))
		item.status_requested.connect(func(id: String, status: String) -> void: status_requested.emit(id, status))
		item.delete_requested.connect(func(id: String) -> void: delete_requested.emit(id))
		item.move_to_today_requested.connect(func(id: String) -> void: move_to_today_requested.emit(id))
		_list.add_child(item)
