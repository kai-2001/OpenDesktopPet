class_name StatusTabView
extends "res://scripts/details_tab_view.gd"

const SettingsToggleSwitchScript = preload("res://scripts/settings_toggle_switch.gd")
const PetStateScript = preload("res://scripts/pet_state.gd")

signal care_action_requested(action: String)
signal auto_feeder_buy_requested
signal auto_feeder_toggled(enabled: bool)

var last_state_message := "尚無紀錄"
var interaction_label: Callable
var interaction_icon: Callable
var stats_bars: Dictionary = {}


func build(tabs: TabContainer) -> Dictionary:
	stats_bars.clear()
	var scroll := ScrollContainer.new()
	scroll.name = "狀態"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title: Label = _new_label(
		"養成狀態", 24, _details_color("#20272b", "#f0f0f0")
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var stats_status: Label = _new_label(
		"", 15, _details_color("#238b9d", "#4fc1ff")
	)
	stats_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(stats_status)

	var companion_status: Label = _new_label(
		"", 14, _details_color("#6f65a8", "#c8a7ff")
	)
	companion_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	companion_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(companion_status)

	var wish_status: Label = _new_label(
		"", 15, _details_color("#a66b16", "#dcdcaa")
	)
	wish_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wish_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(wish_status)

	content.add_child(HSeparator.new())
	_add_stat_row(content, "飽食", "hunger", Color("#efa64a"))
	_add_stat_row(content, "水分", "thirst", Color("#55b7df"))
	_add_stat_row(content, "體力", "energy", Color("#69c986"))
	_add_stat_row(content, "心情", "mood", Color("#e97ca6"))
	_add_stat_row(content, "親密", "affection", Color("#9a83d2"))

	var unlock_status: Label = _new_label(
		"", 14, _details_color("#6f65a8", "#c8a7ff")
	)
	unlock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(unlock_status)

	var last_message_status: Label = _new_label(
		"最近訊息：%s" % last_state_message,
		13,
		_details_color("#68747a", "#9da1a6")
	)
	last_message_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_message_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(last_message_status)
	content.add_child(HSeparator.new())

	var action_title: Label = _new_label(
		"照顧操作", 16, _details_color("#30383c", "#d4d4d4")
	)
	action_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var auto_feeder_refs := _build_auto_feeder_row()
	content.add_child(_build_care_header(action_title, auto_feeder_refs["row"]))

	var action_grid := HFlowContainer.new()
	action_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	action_grid.add_theme_constant_override("h_separation", 7)
	action_grid.add_theme_constant_override("v_separation", 7)
	var care_action_buttons: Dictionary = {}
	var panel_actions: Array[Dictionary] = [
		{"action": "feed", "id": 1},
		{"action": "water", "id": 2},
		{"action": "pet", "id": 3},
		{"action": "work", "id": 4},
		{"action": "sleep", "id": 5},
	]
	for definition: Dictionary in panel_actions:
		var action := String(definition.action)
		var action_button := Button.new()
		action_button.text = "%s %s" % [
			_interaction_icon(action), _interaction_label(action)
		]
		action_button.custom_minimum_size = Vector2(100, 38)
		action_button.pressed.connect(
			func() -> void: care_action_requested.emit(action)
		)
		action_grid.add_child(action_button)
		care_action_buttons[action] = action_button
	content.add_child(action_grid)

	return {
		"stats_status": stats_status,
		"companion_status": companion_status,
		"wish_status": wish_status,
		"unlock_status": unlock_status,
		"last_message_status": last_message_status,
		"care_action_buttons": care_action_buttons,
		"stats_bars": stats_bars,
		"auto_feeder_buy_button": auto_feeder_refs["buy_button"],
		"auto_feeder_toggle": auto_feeder_refs["toggle"],
		"auto_feeder_status": auto_feeder_refs["status"],
	}


## Centered title with the auto feeder on the right of the same line. A blank
## spacer as wide as the feeder balances the left side so the title stays truly
## centered. When the panel is too narrow for both, the feeder moves to its own
## centered line under the title.
func _build_care_header(title: Label, feeder_row: Control) -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_FILL
	top_row.add_child(spacer)
	top_row.add_child(title)
	top_row.add_child(feeder_row)
	header.add_child(top_row)
	var bottom_row := CenterContainer.new()
	bottom_row.visible = false
	header.add_child(bottom_row)
	var layout := func() -> void:
		var feeder_width := feeder_row.get_combined_minimum_size().x
		var needed := title.get_combined_minimum_size().x + feeder_width * 2.0 + 24.0
		var single_line := header.size.x >= needed
		spacer.custom_minimum_size.x = feeder_width
		spacer.visible = single_line
		bottom_row.visible = not single_line
		var target: Control = top_row if single_line else bottom_row
		if feeder_row.get_parent() != target:
			feeder_row.reparent(target, false)
	# Defer so reparenting never happens inside the container's own sort pass.
	header.resized.connect(func() -> void: layout.call_deferred())
	# The row changes width when the feeder is bought or switches state.
	feeder_row.minimum_size_changed.connect(func() -> void: layout.call_deferred())
	return header


func _build_auto_feeder_row() -> Dictionary:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(_new_label(
		"🍽 自動餵食器", 15, _details_color("#30383c", "#d4d4d4")
	))
	var help: Label = _new_label("(?)", 14, _details_color("#238b9d", "#4fc1ff"))
	help.tooltip_text = PetStateScript.AUTO_FEEDER_TOOLTIP
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	help.mouse_default_cursor_shape = Control.CURSOR_HELP
	row.add_child(help)
	var buy_button := Button.new()
	buy_button.custom_minimum_size = Vector2(110, 34)
	_apply_secondary_button_style(buy_button)
	buy_button.pressed.connect(func() -> void: auto_feeder_buy_requested.emit())
	row.add_child(buy_button)
	var toggle := SettingsToggleSwitchScript.new()
	toggle.name = "AutoFeederToggle"
	toggle.configure(theme_mode, false)
	# Narrower than the settings default so owning the feeder does not make the
	# header wrap sooner than the buy button did.
	toggle.custom_minimum_size = Vector2(80, 34)
	toggle.visible = false
	toggle.toggled.connect(func(value: bool) -> void: auto_feeder_toggled.emit(value))
	row.add_child(toggle)
	# A short state word sits in the row; the full explanation is its tooltip,
	# so the feeder never adds an extra line under the care buttons.
	var status: Label = _new_label("", 13, _details_color("#68747a", "#9da1a6"))
	status.mouse_filter = Control.MOUSE_FILTER_STOP
	status.visible = false
	row.add_child(status)
	return {"row": row, "buy_button": buy_button, "toggle": toggle, "status": status}


func _add_stat_row(parent: VBoxContainer, label_text: String, key: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _new_label(label_text, 15, _details_color("#445057", "#cccccc"))
	label.custom_minimum_size.x = 48
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 22
	bar.show_percentage = true
	var background := StyleBoxFlat.new()
	background.bg_color = _details_color("#e8edef", "#333333")
	background.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_color_override("font_color", _details_color("#263238", "#f0f0f0"))
	bar.add_theme_color_override("font_outline_color", _details_color("#ffffff", "#1e1e1e"))
	bar.add_theme_constant_override("outline_size", 1)
	row.add_child(bar)
	stats_bars[key] = bar
	parent.add_child(row)


func _interaction_label(action: String) -> String:
	if interaction_label.is_valid():
		return String(interaction_label.call(action))
	return action


func _interaction_icon(action: String) -> String:
	if interaction_icon.is_valid():
		return String(interaction_icon.call(action))
	return ""
