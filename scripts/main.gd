extends Node2D

const CharacterPackManagerScript = preload("res://scripts/character_pack_manager.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_STATS_SIZE := Vector2i(400, 720)
const MIN_STATS_SIZE := Vector2i(360, 480)
const DEFAULT_TARGET_FPS := 30
const TARGET_FPS_OPTIONS := [15, 30, 60]
const DRAG_HOLD_THRESHOLD_MS := 140
const DRAG_DISTANCE_THRESHOLD_PX := 3.0
const AUTOSTART_REGISTRY_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const AUTOSTART_VALUE_NAME := "Open Desktop Pet"
const STATUS_ICON = preload("res://assets/branding/birthmark_app_icon.png")

@onready var state: Node = $PetState
@onready var pet: Node2D = $PetVisual
@onready var bubble: PanelContainer = $SpeechBubble
@onready var bubble_label: Label = $SpeechBubble/Margin/Label
@onready var bubble_tail: Polygon2D = $SpeechTail
@onready var context_menu: PopupMenu = $ContextMenu
var _stats_window: Window
var _stats_status: Label
var _wish_status: Label
var _unlock_status: Label
var _last_message_status: Label
var _fps_option_button: OptionButton
var _autostart_check_box: CheckBox
var _settings_feedback: Label
var _character_list: ItemList
var _character_feedback: Label
var _character_use_button: Button
var _character_delete_button: Button
var _character_tab_index := -1
var _character_tab_loaded := false
var _character_entries: Array[Dictionary] = []
var _character_import_dialog: FileDialog
var _character_update_dialog: ConfirmationDialog
var _character_delete_dialog: ConfirmationDialog
var _pending_character_archive := ""
var _stats_bars: Dictionary = {}
var _care_action_buttons: Dictionary = {}
var _autostart_threads: Dictionary = {}
var _autostart_operation_serial := 0
var _latest_autostart_operation_id := 0
var _dragging := false
var _left_press_pending := false
var _left_press_started_ms := 0
var _drag_offset := Vector2i.ZERO
var _drag_origin := Vector2i.ZERO
var _bubble_token := 0
var _shutting_down := false
var _idle_count := 0
var _last_global_mouse := Vector2i.ZERO
var _last_drag_mouse := Vector2i.ZERO
var _last_user_activity_ms := 0
var _auto_move_tween: Tween
var _known_unlocked_actions: Dictionary = {}
var _unlock_tracking_ready := false
var _last_state_message := "尚無紀錄"
var _pet_interaction_polygon := PackedVector2Array()
var _cursor_shape := Input.CURSOR_ARROW
var _status_indicator: StatusIndicator
var _tray_exit_menu: PopupMenu


func _ready() -> void:
	get_tree().auto_accept_quit = false
	# PetVisual is ready before this parent node. Keep its first loaded frame
	# hidden until the native transparent window has been positioned and shaped.
	pet.visible = false
	state.configure_profile(pet.get_character_id())
	_load_runtime_settings()
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	_style_bubble()
	_connect_signals()
	_refresh_ui(state.get_snapshot())
	_setup_context_menu()
	_setup_status_indicator()
	_setup_idle_behavior()
	_last_global_mouse = DisplayServer.mouse_get_position()
	_last_user_activity_ms = Time.get_ticks_msec()
	call_deferred("_finish_window_setup")


func _process(_delta: float) -> void:
	_restore_from_system_minimize()
	var mouse := DisplayServer.mouse_get_position()
	if mouse.distance_to(_last_global_mouse) > 1.0:
		_last_user_activity_ms = Time.get_ticks_msec()
		if is_instance_valid(_auto_move_tween):
			_auto_move_tween.kill()
			_auto_move_tween = null
			pet.cancel_roll()
	_last_global_mouse = mouse
	_update_cursor(mouse)
	if _left_press_pending and not _dragging:
		var held_ms := Time.get_ticks_msec() - _left_press_started_ms
		if (mouse.distance_to(_drag_origin) >= DRAG_DISTANCE_THRESHOLD_PX \
				or held_ms >= DRAG_HOLD_THRESHOLD_MS) \
				and _can_begin_drag():
			_begin_drag(mouse)
	if not _dragging:
		return
	if mouse.distance_to(_last_drag_mouse) > 1.0:
		pet.set_facing_direction(1 if mouse.x > _last_drag_mouse.x else -1)
		pet.set_drag_motion(true)
	else:
		pet.set_drag_motion(false)
	_last_drag_mouse = mouse
	DisplayServer.window_set_position(_clamp_window_position(mouse - _drag_offset))


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and event.pressed:
			_left_press_pending = false
			_dragging = false
			pet.set_dragging(false)
			_run_care_action(3)
			return
		if event.pressed:
			_left_press_pending = true
			_left_press_started_ms = Time.get_ticks_msec()
			_drag_origin = DisplayServer.mouse_get_position()
			_last_drag_mouse = _drag_origin
			_drag_offset = _drag_origin - DisplayServer.window_get_position()
		else:
			var was_dragging := _dragging
			_left_press_pending = false
			if was_dragging:
				_dragging = false
				pet.set_dragging(false)
				_set_cursor_shape(Input.CURSOR_POINTING_HAND)
			else:
				_single_click_reaction()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_left_press_pending = false
		_dragging = false
		pet.set_dragging(false)
		_show_context_menu(Vector2i(event.position))


func _begin_drag(mouse: Vector2i) -> void:
	if not _interrupt_autonomous_action():
		return
	_left_press_pending = false
	_dragging = true
	_last_drag_mouse = mouse
	pet.set_dragging(true)
	pet.set_drag_motion(true)
	_set_cursor_shape(Input.CURSOR_DRAG)


func _can_begin_drag() -> bool:
	return not state.is_action_busy()


func _interrupt_autonomous_action() -> bool:
	if state.is_action_busy():
		return false
	if is_instance_valid(_auto_move_tween):
		_auto_move_tween.kill()
		_auto_move_tween = null
	return pet.cancel_autonomous_action()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("_request_shutdown")


func say(text: String, seconds := 6.0) -> void:
	_bubble_token += 1
	var token := _bubble_token
	# Container layout and the native Windows hit-test region are both applied
	# asynchronously. Keep the bubble hidden until one layout frame has passed
	# so the compositor never displays the temporary polygon-shaped state.
	bubble.visible = false
	bubble_tail.visible = false
	_refresh_interaction_polygon()
	bubble_label.text = text
	bubble_label.add_theme_font_size_override(
		"font_size", 20 if text in ["🥕", "💧", "💤", "🪙", "✋"] else 13
	)
	_layout_speech_bubble(text)
	await get_tree().process_frame
	if token != _bubble_token:
		return
	_layout_speech_bubble(text)
	bubble.visible = true
	bubble_tail.visible = true
	_refresh_interaction_polygon()
	await get_tree().create_timer(seconds).timeout
	if token == _bubble_token:
		bubble.visible = false
		bubble_tail.visible = false
		_refresh_interaction_polygon()


func _restore_from_system_minimize() -> void:
	# This borderless desktop pet has no user-facing minimize command. Check on
	# every rendered frame so short Show Desktop minimize transitions are not
	# missed between slower timer ticks.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _layout_speech_bubble(text: String) -> void:
	const BUBBLE_WIDTH := 200.0
	const TEXT_WIDTH := 170.0
	const BUBBLE_BOTTOM := 124.0
	var font := bubble_label.get_theme_font("font")
	var font_size := bubble_label.get_theme_font_size("font_size")
	var line_count := 0
	for paragraph: String in text.split("\n"):
		var text_width := font.get_string_size(
			paragraph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		line_count += maxi(ceili(text_width / TEXT_WIDTH), 1)
	var bubble_height := clampf(20.0 + line_count * 20.0, 50.0, 120.0)
	var bubble_left := (280.0 - BUBBLE_WIDTH) / 2.0
	# Explicit offsets are required here. PanelContainer recalculates `size`
	# from its original offsets after child layout, which previously stretched
	# short messages down over the pet.
	bubble.offset_left = bubble_left
	bubble.offset_top = BUBBLE_BOTTOM - bubble_height
	bubble.offset_right = bubble_left + BUBBLE_WIDTH
	bubble.offset_bottom = BUBBLE_BOTTOM
	bubble_tail.polygon = PackedVector2Array([
		Vector2(132, BUBBLE_BOTTOM - 3),
		Vector2(148, BUBBLE_BOTTOM - 3),
		Vector2(140, BUBBLE_BOTTOM + 11),
	])


func _finish_window_setup() -> void:
	_place_bottom_right()
	# Rendering remains a normal transparent rectangle. Mouse input alone is
	# toggled as the pointer enters or leaves the pet, so speech is never clipped.
	_apply_interaction_polygon(pet.get_interaction_polygon())
	# Give Windows one compositor frame to apply the final position and native
	# transparency, then reveal the already-loaded sprite in one complete frame.
	await get_tree().process_frame
	pet.visible = true
	_say_dialogue("startup", "右鍵操作・雙擊摸摸", 5.0)


func _update_cursor(global_mouse: Vector2i) -> void:
	if _dragging:
		_set_cursor_shape(Input.CURSOR_DRAG)
		return
	var local_mouse := Vector2(global_mouse - DisplayServer.window_get_position())
	var over_pet := _is_pet_interactive_at(local_mouse)
	_set_cursor_shape(Input.CURSOR_POINTING_HAND if over_pet else Input.CURSOR_ARROW)


func _is_pet_interactive_at(local_point: Vector2) -> bool:
	if _is_speech_overlay_at(local_point):
		return true
	return pet.contains_point(local_point)


func _is_speech_overlay_at(local_point: Vector2) -> bool:
	if bubble.visible and bubble.get_global_rect().has_point(local_point):
		return true
	if bubble_tail.visible:
		return Geometry2D.is_point_in_polygon(
			bubble_tail.to_local(local_point),
			bubble_tail.polygon
		)
	return false


func _apply_interaction_polygon(polygon: PackedVector2Array) -> void:
	_pet_interaction_polygon = polygon
	_refresh_interaction_polygon()


func _refresh_interaction_polygon() -> void:
	get_window().mouse_passthrough = false
	if not bubble.visible:
		get_window().mouse_passthrough_polygon = _pet_interaction_polygon
		return
	var combined_points := PackedVector2Array(_pet_interaction_polygon)
	var bubble_rect := bubble.get_global_rect()
	combined_points.append_array(PackedVector2Array([
		bubble_rect.position,
		Vector2(bubble_rect.end.x, bubble_rect.position.y),
		bubble_rect.end,
		Vector2(bubble_rect.position.x, bubble_rect.end.y),
	]))
	for point: Vector2 in bubble_tail.polygon:
		combined_points.append(bubble_tail.to_global(point))
	get_window().mouse_passthrough_polygon = Geometry2D.convex_hull(combined_points)


func _set_cursor_shape(shape: Input.CursorShape) -> void:
	if shape == _cursor_shape:
		return
	_cursor_shape = shape
	Input.set_default_cursor_shape(shape)


func _connect_signals() -> void:
	state.changed.connect(_refresh_ui)
	state.message_requested.connect(_show_state_message)
	state.action_requested.connect(pet.play_action)
	pet.action_completed.connect(state.receive_action_completed)
	pet.interaction_region_changed.connect(_apply_interaction_polygon)
	state.wish_started.connect(_show_wish_notice)
	# PetState becomes ready before its parent, so its first `changed` signal is
	# emitted before this node can connect. Ask it for a complete snapshot here
	# instead of passing the raw dictionary, which does not contain `wish_text`.
	var snapshot: Dictionary = state.get_snapshot()
	_refresh_ui(snapshot)
	var active_wish := String(snapshot.get("wish_action", ""))
	if not active_wish.is_empty() \
			and int(snapshot.get("wish_expires_at", 0)) > int(Time.get_unix_time_from_system()):
		call_deferred("_show_wish_notice", active_wish)


func _show_state_message(key: String, fallback: String) -> void:
	var newline_at := fallback.find("\n")
	var base_text := fallback if newline_at < 0 else fallback.left(newline_at)
	var suffix := "" if newline_at < 0 else fallback.substr(newline_at)
	var text: String = pet.get_dialogue(key, base_text) + suffix
	_last_state_message = text.replace("\n", "　")
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % _last_state_message
	say(text, 6.0)


func _say_dialogue(key: String, fallback: String, seconds: float) -> void:
	say(pet.get_dialogue(key, fallback), seconds)


func _show_wish_notice(action: String) -> void:
	say(_wish_icon(action), 6.0)


func _setup_context_menu() -> void:
	context_menu.add_item("Lv.1  ·  20 金幣", 100)
	context_menu.set_item_disabled(0, true)
	context_menu.add_separator()
	context_menu.add_item("%s  %s（2 金幣）" % [
		_interaction_icon("feed"), _interaction_label("feed")
	], 1)
	context_menu.add_item("%s  %s（1 金幣）" % [
		_interaction_icon("water"), _interaction_label("water")
	], 2)
	context_menu.add_item("%s  %s" % [
		_interaction_icon("pet"), _interaction_label("pet")
	], 3)
	context_menu.add_item("%s  %s（賺 7 金幣）" % [
		_interaction_icon("work"), _interaction_label("work")
	], 4)
	context_menu.add_item("%s  %s" % [
		_interaction_icon("sleep"), _interaction_label("sleep")
	], 5)
	context_menu.add_separator()
	context_menu.add_item("📊  開啟詳細面板", 6)
	context_menu.add_item("🔎  角色縮小", 20)
	context_menu.add_item("🔍  角色放大", 21)
	context_menu.add_item("🏠  找回桌寵", 22)
	context_menu.add_separator()
	context_menu.add_item("❌  儲存並離開", 7)
	context_menu.id_pressed.connect(_on_context_action)
	_refresh_ui(state.get_snapshot())


func _show_context_menu(at: Vector2i) -> void:
	context_menu.position = DisplayServer.window_get_position() + at
	context_menu.popup()


func _setup_status_indicator() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_tray_exit_menu = PopupMenu.new()
	_tray_exit_menu.add_item("❌  儲存並離開", 7)
	_tray_exit_menu.id_pressed.connect(_on_context_action)
	add_child(_tray_exit_menu)
	_status_indicator = StatusIndicator.new()
	_status_indicator.icon = STATUS_ICON
	_status_indicator.tooltip = "Open Desktop Pet"
	add_child(_status_indicator)
	_status_indicator.menu = _status_indicator.get_path_to(_tray_exit_menu)
	_status_indicator.pressed.connect(_on_status_indicator_pressed)


func _on_status_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		call_deferred("_show_stats_window")


func _remove_status_indicator() -> void:
	if is_instance_valid(_status_indicator):
		_status_indicator.queue_free()
	_status_indicator = null
	if is_instance_valid(_tray_exit_menu):
		_tray_exit_menu.queue_free()
	_tray_exit_menu = null


func _on_context_action(id: int) -> void:
	match id:
		1, 2, 3, 4, 5:
			_run_care_action(id)
		6:
			call_deferred("_show_stats_window")
		7:
			# Let the native PopupMenu finish dispatching `id_pressed` before
			# destroying either native window.
			call_deferred("_request_shutdown")
		20:
			state.change_visual_size(-0.1)
			_say_dialogue("size_smaller", "這個大小比較不擋路。", 2.0)
		21:
			state.change_visual_size(0.1)
			_say_dialogue("size_larger", "放大一點點。", 2.0)
		22:
			_recover_pet()


func _single_click_reaction() -> void:
	var lines := [
		"有事嗎？",
		"我有在聽。",
		"右鍵有快捷操作喔。",
		"再點一下就要收費了。"
	]
	_say_dialogue("single_click", lines.pick_random(), 2.0)
	pet.play_action("wiggle")


func _setup_idle_behavior() -> void:
	var timer := Timer.new()
	timer.wait_time = randf_range(10.0, 16.0)
	timer.one_shot = true
	timer.timeout.connect(func() -> void:
		_idle_count += 1
		if _can_act_autonomously():
			_run_autonomous_action()
			if _idle_count % 3 == 0:
				_say_dialogue(
					"idle",
					["我在這裡。", "滾一下好了。", "今天也要照顧我。"].pick_random(),
					2.5
				)
		timer.wait_time = randf_range(11.0, 19.0)
		timer.start()
	)
	add_child(timer)
	timer.start()


func _can_act_autonomously(require_mouse_idle := false) -> bool:
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	return (not require_mouse_idle or mouse_is_idle) \
		and not context_menu.visible \
		and not _is_stats_window_open() \
		and not _dragging \
		and not pet.is_busy() \
		and not state.is_action_busy()


func _run_autonomous_action() -> void:
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	var action: String = pet.pick_autonomous_action(mouse_is_idle)
	if action == "move":
		_autonomous_small_roll()
	elif not action.is_empty():
		pet.play_action(action)


func _autonomous_small_roll() -> void:
	if not _can_act_autonomously(true):
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var window_size := DisplayServer.window_get_size()
	var start := DisplayServer.window_get_position()
	var distance := randi_range(72, 128) * (-1 if randf() < 0.5 else 1)
	var target_x := clampi(start.x + distance, usable.position.x, usable.end.x - window_size.x)
	if target_x == start.x:
		target_x = clampi(start.x - distance, usable.position.x, usable.end.x - window_size.x)
	var target := Vector2i(target_x, start.y)
	var move_duration: float = pet.get_action_duration("move")
	pet.set_facing_direction(1 if target_x > start.x else -1)
	pet.play_action("move")
	_auto_move_tween = create_tween()
	_auto_move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_auto_move_tween.tween_method(
		func(weight: float) -> void:
			DisplayServer.window_set_position(Vector2i(Vector2(start).lerp(Vector2(target), weight))),
		0.0, 1.0, move_duration
	)
	await _auto_move_tween.finished
	_auto_move_tween = null


func _build_stats_window() -> void:
	_stats_bars.clear()
	_care_action_buttons.clear()
	_stats_window = Window.new()
	_stats_window.title = "桌寵詳細狀態"
	_stats_window.size = DEFAULT_STATS_SIZE
	_stats_window.min_size = MIN_STATS_SIZE
	_stats_window.unresizable = false
	_stats_window.transient = false
	_stats_window.always_on_top = false
	_stats_window.visible = false
	_stats_window.close_requested.connect(_destroy_stats_window)
	add_child(_stats_window)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#14242d")
	panel_style.border_color = Color("#55b6cc")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", panel_style)
	_stats_window.add_child(panel)

	var tabs := TabContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tab_bar := tabs.get_tab_bar()
	tab_bar.add_theme_font_size_override("font_size", 16)
	tab_bar.add_theme_constant_override("h_separation", 6)
	var selected_tab_style := StyleBoxFlat.new()
	selected_tab_style.bg_color = Color("#203c48")
	selected_tab_style.border_color = Color("#55c8e5")
	selected_tab_style.border_width_top = 2
	selected_tab_style.content_margin_left = 18
	selected_tab_style.content_margin_right = 18
	selected_tab_style.content_margin_top = 9
	selected_tab_style.content_margin_bottom = 9
	var unselected_tab_style := selected_tab_style.duplicate() as StyleBoxFlat
	unselected_tab_style.bg_color = Color("#101a1f")
	unselected_tab_style.border_color = Color("#263b44")
	var hovered_tab_style := selected_tab_style.duplicate() as StyleBoxFlat
	hovered_tab_style.bg_color = Color("#284b59")
	tab_bar.add_theme_stylebox_override("tab_selected", selected_tab_style)
	tab_bar.add_theme_stylebox_override("tab_unselected", unselected_tab_style)
	tab_bar.add_theme_stylebox_override("tab_hovered", hovered_tab_style)
	panel.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.name = "狀態"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := _new_label("養成狀態", 24, Color("#e9fbff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	_stats_status = _new_label("", 15, Color("#8ed9e8"))
	_stats_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_stats_status)

	_wish_status = _new_label("", 15, Color("#ffd98e"))
	_wish_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wish_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_wish_status)

	content.add_child(HSeparator.new())
	_add_stat_row(content, "飽食", "hunger", Color("#ffbd69"))
	_add_stat_row(content, "水分", "thirst", Color("#65c9ff"))
	_add_stat_row(content, "體力", "energy", Color("#8de28d"))
	_add_stat_row(content, "心情", "mood", Color("#ff91bd"))
	_add_stat_row(content, "親密", "affection", Color("#c5a3ff"))

	_unlock_status = _new_label("", 14, Color("#c5a3ff"))
	_unlock_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_unlock_status)

	_last_message_status = _new_label("最近訊息：%s" % _last_state_message, 13, Color("#b9ced5"))
	_last_message_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_last_message_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_last_message_status)
	content.add_child(HSeparator.new())

	var action_title := _new_label("照顧操作", 16, Color("#e9fbff"))
	action_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(action_title)

	var action_grid := HFlowContainer.new()
	action_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	action_grid.add_theme_constant_override("h_separation", 7)
	action_grid.add_theme_constant_override("v_separation", 7)
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
		var action_id := int(definition.id)
		action_button.pressed.connect(func() -> void: _run_care_action(action_id))
		action_grid.add_child(action_button)
		_care_action_buttons[action] = action_button
	content.add_child(action_grid)
	content.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "關閉詳細狀態"
	close_button.custom_minimum_size.y = 42
	close_button.pressed.connect(_destroy_stats_window)
	content.add_child(close_button)

	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "設定"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(settings_scroll)

	var settings_margin := MarginContainer.new()
	settings_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_margin.add_theme_constant_override("margin_left", 24)
	settings_margin.add_theme_constant_override("margin_top", 20)
	settings_margin.add_theme_constant_override("margin_right", 24)
	settings_margin.add_theme_constant_override("margin_bottom", 20)
	settings_scroll.add_child(settings_margin)

	var settings_content := VBoxContainer.new()
	settings_content.add_theme_constant_override("separation", 16)
	settings_margin.add_child(settings_content)

	var settings_title := _new_label("桌寵設定", 24, Color("#e9fbff"))
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(settings_title)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label := _new_label("桌寵幀率（FPS）", 16, Color("#e9fbff"))
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	_fps_option_button = OptionButton.new()
	for fps: int in TARGET_FPS_OPTIONS:
		_fps_option_button.add_item("%d FPS" % fps, fps)
	_fps_option_button.select(
		_fps_option_button.get_item_index(Engine.max_fps)
	)
	_fps_option_button.custom_minimum_size = Vector2(120, 40)
	_fps_option_button.item_selected.connect(_on_target_fps_selected)
	fps_row.add_child(_fps_option_button)
	settings_content.add_child(fps_row)

	var fps_hint := _new_label(
		"控制整個桌寵的更新率（15–60）；30 FPS 適合日常使用，降低可省電。",
		13,
		Color("#b9ced5")
	)
	fps_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(fps_hint)
	settings_content.add_child(HSeparator.new())

	_autostart_check_box = CheckBox.new()
	_autostart_check_box.text = "登入 Windows 時自動開啟桌寵"
	_autostart_check_box.add_theme_font_size_override("font_size", 16)
	_autostart_check_box.button_pressed = false
	_autostart_check_box.disabled = true
	_autostart_check_box.toggled.connect(_on_autostart_toggled)
	settings_content.add_child(_autostart_check_box)

	_settings_feedback = _new_label(
		"請使用打包版設定開機啟動。"
		if OS.has_feature("editor")
		else "正在讀取 Windows 開機啟動設定…",
		13,
		Color("#b9ced5")
	)
	_settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(_settings_feedback)
	if _is_autostart_supported():
		call_deferred("_start_autostart_operation", "query", false)
	elif not OS.has_feature("editor"):
		_settings_feedback.text = "目前平台不支援 Windows 開機啟動設定。"

	var settings_close_button := Button.new()
	settings_close_button.text = "關閉詳細面板"
	settings_close_button.custom_minimum_size.y = 42
	settings_close_button.pressed.connect(_destroy_stats_window)
	settings_content.add_child(settings_close_button)

	_build_character_tab(tabs)
	tabs.tab_changed.connect(_on_stats_tab_changed)


func _build_character_tab(tabs: TabContainer) -> void:
	var character_scroll := ScrollContainer.new()
	character_scroll.name = "角色"
	character_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_tab_index = tabs.get_tab_count()
	tabs.add_child(character_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	character_scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := _new_label("角色管理", 24, Color("#e9fbff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var hint := _new_label(
		"角色清單只會在開啟這個頁面時讀取，不會增加平常常駐耗能。",
		13,
		Color("#b9ced5")
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

	_character_list = ItemList.new()
	_character_list.custom_minimum_size = Vector2(0, 260)
	_character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_list.item_selected.connect(_on_character_selected)
	content.add_child(_character_list)

	var action_row := HFlowContainer.new()
	action_row.alignment = FlowContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("h_separation", 8)
	_character_use_button = Button.new()
	_character_use_button.text = "使用選取角色"
	_character_use_button.custom_minimum_size = Vector2(145, 40)
	_character_use_button.disabled = true
	_character_use_button.pressed.connect(_use_selected_character)
	action_row.add_child(_character_use_button)
	_character_delete_button = Button.new()
	_character_delete_button.text = "刪除角色包"
	_character_delete_button.custom_minimum_size = Vector2(125, 40)
	_character_delete_button.disabled = true
	_character_delete_button.pressed.connect(_confirm_delete_selected_character)
	action_row.add_child(_character_delete_button)
	content.add_child(action_row)

	var import_row := HFlowContainer.new()
	import_row.alignment = FlowContainer.ALIGNMENT_CENTER
	import_row.add_theme_constant_override("h_separation", 8)
	var import_button := Button.new()
	import_button.text = "匯入角色包"
	import_button.custom_minimum_size = Vector2(135, 40)
	import_button.pressed.connect(_open_character_import_dialog)
	import_row.add_child(import_button)
	var open_folder_button := Button.new()
	open_folder_button.text = "開啟角色資料夾"
	open_folder_button.custom_minimum_size = Vector2(145, 40)
	open_folder_button.pressed.connect(_open_character_packs_folder)
	import_row.add_child(open_folder_button)
	content.add_child(import_row)

	_character_feedback = _new_label(
		"切換角色會儲存目前進度，並直接在目前視窗載入。",
		13,
		Color("#8ed9e8")
	)
	_character_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_character_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_character_feedback)

	_character_import_dialog = FileDialog.new()
	_character_import_dialog.title = "匯入角色包"
	_character_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_character_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_character_import_dialog.use_native_dialog = true
	_character_import_dialog.add_filter("*.petpack, *.zip", "桌寵角色包")
	_character_import_dialog.file_selected.connect(_install_character_archive)
	_stats_window.add_child(_character_import_dialog)

	_character_update_dialog = ConfirmationDialog.new()
	_character_update_dialog.title = "更新角色包"
	_character_update_dialog.confirmed.connect(_install_pending_character_archive)
	_stats_window.add_child(_character_update_dialog)

	_character_delete_dialog = ConfirmationDialog.new()
	_character_delete_dialog.title = "刪除角色包"
	_character_delete_dialog.confirmed.connect(_delete_selected_character)
	_stats_window.add_child(_character_delete_dialog)


func _on_stats_tab_changed(tab_index: int) -> void:
	if tab_index != _character_tab_index or _character_tab_loaded:
		return
	_refresh_character_list()


func _refresh_character_list(message := "") -> void:
	if not is_instance_valid(_character_list):
		return
	_character_tab_loaded = true
	_character_entries.clear()
	_character_list.clear()
	_character_entries.append({
		"id": "open_desktop_pet_default",
		"name": "預設桌寵",
		"version": "內建",
		"installed": false,
		"builtin": true,
	})
	for entry: Dictionary in CharacterPackManagerScript.list_installed():
		var installed_entry := entry.duplicate()
		installed_entry.installed = true
		installed_entry.builtin = false
		_character_entries.append(installed_entry)
	var active_id: String = pet.get_character_id()
	var active_found := false
	for entry: Dictionary in _character_entries:
		if String(entry.id) == active_id:
			active_found = true
			break
	if not active_found:
		_character_entries.append({
			"id": active_id,
			"name": pet.get_character_name(),
			"version": pet.get_character_version(),
			"installed": false,
			"builtin": true,
		})
	for index in _character_entries.size():
		var entry: Dictionary = _character_entries[index]
		var active_marker := " 〔使用中〕" if String(entry.id) == active_id else ""
		_character_list.add_item("%s  v%s%s\nID: %s" % [
			String(entry.name),
			String(entry.version),
			active_marker,
			String(entry.id),
		])
		if String(entry.id) == active_id:
			_character_list.select(index)
	if not message.is_empty():
		_character_feedback.text = message
	_update_character_buttons()


func _on_character_selected(_index: int) -> void:
	_update_character_buttons()


func _selected_character_entry() -> Dictionary:
	if not is_instance_valid(_character_list):
		return {}
	var selected := _character_list.get_selected_items()
	if selected.is_empty():
		return {}
	var index := int(selected[0])
	if index < 0 or index >= _character_entries.size():
		return {}
	return _character_entries[index]


func _update_character_buttons() -> void:
	var entry := _selected_character_entry()
	var has_entry := not entry.is_empty()
	if is_instance_valid(_character_use_button):
		var is_active: bool = has_entry \
			and String(entry.id) == pet.get_character_id()
		_character_use_button.text = "重新載入角色" if is_active \
			else "使用選取角色"
		_character_use_button.disabled = not has_entry
	if is_instance_valid(_character_delete_button):
		_character_delete_button.disabled = not has_entry \
			or not bool(entry.get("installed", false))


func _open_character_import_dialog() -> void:
	if is_instance_valid(_character_import_dialog):
		_character_import_dialog.popup_centered_ratio(0.75)


func _install_character_archive(path: String) -> void:
	var inspection: Dictionary = CharacterPackManagerScript.inspect_archive(path)
	if not bool(inspection.get("ok", false)):
		_character_feedback.text = "匯入失敗：%s" % String(inspection.get(
			"message", "未知錯誤"
		))
		return
	for entry: Dictionary in CharacterPackManagerScript.list_installed():
		if String(entry.id) != String(inspection.id):
			continue
		_pending_character_archive = path
		_character_update_dialog.dialog_text = (
			"已安裝「%s」v%s。\n準備匯入同一角色ID的v%s。\n\n"
			+ "更新會替換角色圖片與設定，但保留遊戲進度。"
		) % [
			String(entry.name),
			String(entry.version),
			String(inspection.version),
		]
		_character_update_dialog.popup_centered()
		return
	_install_character_archive_now(path)


func _install_pending_character_archive() -> void:
	if _pending_character_archive.is_empty():
		return
	var path := _pending_character_archive
	_pending_character_archive = ""
	_install_character_archive_now(path)


func _install_character_archive_now(path: String) -> void:
	_character_feedback.text = "正在驗證並安裝角色包…"
	var result: Dictionary = CharacterPackManagerScript.install_archive(path)
	if not bool(result.get("ok", false)):
		_character_feedback.text = "匯入失敗：%s" % String(result.get(
			"message", "未知錯誤"
		))
		return
	var verb := "更新" if bool(result.get("updated", false)) else "安裝"
	_refresh_character_list("已%s「%s」v%s；角色進度保持不變。" % [
		verb,
		String(result.name),
		String(result.version),
	])


func _use_selected_character() -> void:
	var entry := _selected_character_entry()
	if entry.is_empty():
		return
	var is_reload: bool = String(entry.id) == pet.get_character_id()
	state.save_state()
	_apply_character_without_restart(String(entry.id), is_reload)


func _apply_character_without_restart(character_id: String, is_reload: bool) -> bool:
	var previous_character_id: String = pet.get_character_id()
	_set_selected_character_id(character_id)
	if not pet.reload_character() or pet.get_character_id() != character_id:
		_set_selected_character_id(previous_character_id)
		pet.reload_character()
		state.configure_profile(pet.get_character_id())
		_character_feedback.text = "角色載入失敗，已恢復原本角色。"
		_refresh_interaction_polygon()
		return false
	_known_unlocked_actions.clear()
	_unlock_tracking_ready = false
	# configure_profile() emits changed immediately. Reset tracking first so
	# actions already unlocked in the newly selected profile establish the
	# baseline instead of being mistaken for fresh unlocks.
	state.configure_profile(character_id)
	_refresh_json_driven_ui()
	_refresh_ui(state.get_snapshot())
	_refresh_interaction_polygon()
	_refresh_character_list(
		"已重新載入「%s」。" % pet.get_character_name()
		if is_reload
		else "已切換為「%s」。" % pet.get_character_name()
	)
	return true


func _refresh_json_driven_ui() -> void:
	var labels := {
		1: "%s  %s（2 金幣）" % [
			_interaction_icon("feed"), _interaction_label("feed")
		],
		2: "%s  %s（1 金幣）" % [
			_interaction_icon("water"), _interaction_label("water")
		],
		3: "%s  %s" % [
			_interaction_icon("pet"), _interaction_label("pet")
		],
		4: "%s  %s（賺 7 金幣）" % [
			_interaction_icon("work"), _interaction_label("work")
		],
		5: "%s  %s" % [
			_interaction_icon("sleep"), _interaction_label("sleep")
		],
	}
	for id: int in labels:
		var index := context_menu.get_item_index(id)
		if index >= 0:
			context_menu.set_item_text(index, String(labels[id]))
	for action: String in _care_action_buttons:
		var button: Button = _care_action_buttons[action]
		if is_instance_valid(button):
			button.text = "%s %s" % [
				_interaction_icon(action), _interaction_label(action)
			]
	_bubble_token += 1
	bubble.visible = false
	bubble_tail.visible = false
	_last_state_message = pet.get_dialogue(
		"startup", "右鍵操作・雙擊摸摸"
	)
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % _last_state_message


func _set_selected_character_id(character_id: String) -> void:
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("character", "selected_id", character_id)
	config.save(UI_SETTINGS_PATH)


func _confirm_delete_selected_character() -> void:
	var entry := _selected_character_entry()
	if entry.is_empty() or not bool(entry.get("installed", false)):
		return
	_character_delete_dialog.dialog_text = (
		"確定要刪除「%s」嗎？\n\n角色包會被移除，但遊戲進度會保留。"
		% String(entry.name)
	)
	_character_delete_dialog.popup_centered()


func _delete_selected_character() -> void:
	var entry := _selected_character_entry()
	if entry.is_empty() or not bool(entry.get("installed", false)):
		return
	var character_id := String(entry.id)
	var was_active: bool = character_id == pet.get_character_id()
	if was_active:
		_set_selected_character_id("open_desktop_pet_default")
		state.save_state()
	var result: Dictionary = CharacterPackManagerScript.remove_pack(character_id)
	if not bool(result.get("ok", false)):
		_character_feedback.text = "刪除失敗：%s" % String(result.get(
			"message", "未知錯誤"
		))
		return
	_refresh_character_list("已刪除角色包；遊戲進度仍保留。")
	if was_active:
		_apply_character_without_restart("open_desktop_pet_default", false)


func _open_character_packs_folder() -> void:
	if CharacterPackManagerScript.ensure_packs_root() != OK:
		_character_feedback.text = "無法建立角色包資料夾。"
		return
	OS.shell_open(ProjectSettings.globalize_path(
		CharacterPackManagerScript.PACKS_ROOT
	))


func _run_care_action(id: int) -> void:
	if state.is_action_busy() or not _interrupt_autonomous_action():
		_say_dialogue("action_busy", "先等目前的動作完成～", 1.5)
		return
	match id:
		1:
			state.feed()
		2:
			state.water()
		3:
			state.pet()
		4:
			state.work()
		5:
			state.sleep()


func _add_stat_row(parent: VBoxContainer, label_text: String, key: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _new_label(label_text, 15, Color("#e9fbff"))
	label.custom_minimum_size.x = 48
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 22
	bar.show_percentage = true
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#263b45")
	background.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_color_override("font_color", Color("#ffffff"))
	bar.add_theme_color_override("font_outline_color", Color("#102028"))
	bar.add_theme_constant_override("outline_size", 3)
	row.add_child(bar)
	_stats_bars[key] = bar
	parent.add_child(row)


func _new_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_stats_window() -> void:
	if is_instance_valid(_stats_window):
		_refresh_ui(state.get_snapshot())
		call_deferred("_bring_stats_window_forward")
		return
	_build_stats_window()
	_refresh_ui(state.get_snapshot())
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var preferred_size := _load_stats_window_size()
	_stats_window.size = Vector2i(
		clampi(preferred_size.x, MIN_STATS_SIZE.x, usable.size.x - 24),
		clampi(preferred_size.y, MIN_STATS_SIZE.y, usable.size.y - 24)
	)
	var target := Vector2i(pet_position.x - _stats_window.size.x - 14, pet_position.y - 60)
	if target.x < usable.position.x:
		target.x = pet_position.x + pet_size.x + 14
	target.y = clampi(target.y, usable.position.y + 12, usable.end.y - _stats_window.size.y - 12)
	_stats_window.position = target
	_stats_window.show()
	call_deferred("_bring_stats_window_forward")


func _bring_stats_window_forward() -> void:
	if not is_instance_valid(_stats_window):
		return
	if _stats_window.mode == Window.MODE_MINIMIZED:
		_stats_window.mode = Window.MODE_WINDOWED
	if not _stats_window.visible:
		_stats_window.show()
	_stats_window.grab_focus()
	DisplayServer.window_move_to_foreground(_stats_window.get_window_id())


func _is_stats_window_open() -> bool:
	return is_instance_valid(_stats_window) and _stats_window.visible


func _destroy_stats_window() -> void:
	_save_stats_window_size()
	if is_instance_valid(_stats_window):
		_stats_window.queue_free()
	_stats_window = null
	_stats_status = null
	_wish_status = null
	_unlock_status = null
	_last_message_status = null
	_fps_option_button = null
	_autostart_check_box = null
	_settings_feedback = null
	_character_list = null
	_character_feedback = null
	_character_use_button = null
	_character_delete_button = null
	_character_import_dialog = null
	_character_update_dialog = null
	_character_delete_dialog = null
	_pending_character_archive = ""
	_character_entries.clear()
	_character_tab_index = -1
	_character_tab_loaded = false
	_stats_bars.clear()
	_care_action_buttons.clear()


func _load_stats_window_size() -> Vector2i:
	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) != OK:
		return DEFAULT_STATS_SIZE
	var saved_width := int(config.get_value(
		"details_window", "width", DEFAULT_STATS_SIZE.x
	))
	var saved_height := int(config.get_value(
		"details_window", "height", DEFAULT_STATS_SIZE.y
	))
	return Vector2i(
		maxi(saved_width, MIN_STATS_SIZE.x),
		maxi(saved_height, MIN_STATS_SIZE.y)
	)


func _load_runtime_settings() -> void:
	var config := ConfigFile.new()
	var target_fps := DEFAULT_TARGET_FPS
	if config.load(UI_SETTINGS_PATH) == OK:
		target_fps = int(config.get_value(
			"performance", "target_fps", DEFAULT_TARGET_FPS
		))
	Engine.max_fps = _normalize_target_fps(target_fps)


func _normalize_target_fps(value: int) -> int:
	var nearest: int = TARGET_FPS_OPTIONS[0]
	for candidate: int in TARGET_FPS_OPTIONS:
		if absi(candidate - value) < absi(nearest - value):
			nearest = candidate
	return nearest


func _on_target_fps_selected(index: int) -> void:
	_set_target_fps(_fps_option_button.get_item_id(index))


func _set_target_fps(value: int) -> void:
	var target_fps := _normalize_target_fps(value)
	Engine.max_fps = target_fps
	if is_instance_valid(_fps_option_button):
		var target_index := _fps_option_button.get_item_index(target_fps)
		if target_index >= 0 and _fps_option_button.selected != target_index:
			_fps_option_button.select(target_index)
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("performance", "target_fps", target_fps)
	config.save(UI_SETTINGS_PATH)


func _is_autostart_supported() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


func _autostart_command(executable_path := OS.get_executable_path()) -> String:
	return "\"%s\"" % _native_windows_path(executable_path)


func _native_windows_path(path: String) -> String:
	return path.replace("/", "\\")


func _registry_executable() -> String:
	var windows_root := OS.get_environment("SystemRoot")
	if windows_root.is_empty():
		windows_root = "C:\\Windows"
	return windows_root.path_join("System32").path_join("reg.exe")


func _query_registry_value_blocking(
	registry_key: String,
	value_name: String,
	expected_executable_path: String
) -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(
		_registry_executable(),
		PackedStringArray([
			"query", registry_key, "/v", value_name
		]),
		output,
		true,
		false
	)
	var exists := exit_code == 0
	var expected_command := _autostart_command(expected_executable_path)
	var legacy_command := "\"%s\"" % expected_executable_path.replace("\\", "/")
	var output_text := "\n".join(PackedStringArray(output)).strip_edges()
	return {
		"exists": exists,
		"matches": exists and output_text.to_lower().contains(
			expected_command.to_lower()
		),
		"legacy_matches": exists and output_text.to_lower().contains(
			legacy_command.to_lower()
		),
		"output": output_text,
	}


func _query_autostart_state_blocking() -> Dictionary:
	return _query_registry_value_blocking(
		AUTOSTART_REGISTRY_KEY,
		AUTOSTART_VALUE_NAME,
		OS.get_executable_path()
	)


func _on_autostart_toggled(enabled: bool) -> void:
	if not _is_autostart_supported():
		return
	_start_autostart_operation("set", enabled)


func _write_registry_autostart_blocking(
	registry_key: String,
	value_name: String,
	enabled: bool,
	executable_path: String
) -> bool:
	var arguments := PackedStringArray()
	if enabled:
		arguments = PackedStringArray([
			"add",
			registry_key,
			"/v",
			value_name,
			"/t",
			"REG_SZ",
			"/d",
			# reg.exe is a native Windows command-line program. The literal
			# quotes required by Run values must survive its argv parser.
			"\\\"%s\\\"" % _native_windows_path(executable_path),
			"/f",
		])
	else:
		arguments = PackedStringArray([
			"delete",
			registry_key,
			"/v",
			value_name,
			"/f",
		])
	var output: Array = []
	var exit_code := OS.execute(
		_registry_executable(), arguments, output, true, false
	)
	if exit_code != 0:
		push_warning(
			"Windows autostart registry command failed (%d): %s" % [
				exit_code,
				"\n".join(PackedStringArray(output)).strip_edges(),
			]
		)
	return exit_code == 0


func _set_autostart_enabled_blocking(enabled: bool) -> bool:
	return _write_registry_autostart_blocking(
		AUTOSTART_REGISTRY_KEY,
		AUTOSTART_VALUE_NAME,
		enabled,
		OS.get_executable_path()
	)


func _start_autostart_operation(operation: String, enabled: bool) -> void:
	if is_instance_valid(_autostart_check_box):
		_autostart_check_box.disabled = true
	if is_instance_valid(_settings_feedback):
		_settings_feedback.text = (
			"正在讀取 Windows 開機啟動設定…"
			if operation == "query"
			else "正在套用開機啟動設定…"
		)
	_autostart_operation_serial += 1
	var operation_id := _autostart_operation_serial
	_latest_autostart_operation_id = operation_id
	var operation_thread := Thread.new()
	_autostart_threads[operation_id] = operation_thread
	var start_error := operation_thread.start(
		Callable(self, "_run_autostart_operation").bind(
			operation_id, operation, enabled
		)
	)
	if start_error != OK:
		_autostart_threads.erase(operation_id)
		_finish_autostart_operation(
			operation_id,
			operation,
			enabled,
			{"exists": false, "matches": false}
			if operation == "query"
			else {"success": false}
		)


func _run_autostart_operation(
	operation_id: int, operation: String, enabled: bool
) -> void:
	var result: Variant
	if operation == "query":
		result = _query_autostart_state_blocking()
	else:
		result = {"success": _set_autostart_enabled_blocking(enabled)}
	call_deferred(
		"_finish_autostart_operation",
		operation_id,
		operation,
		enabled,
		result
	)


func _finish_autostart_operation(
	operation_id: int,
	operation: String,
	enabled: bool,
	result: Dictionary
) -> void:
	_finish_autostart_thread(operation_id)
	# A panel can be closed and recreated while an older registry request is
	# finishing. Only the newest request may update the current controls.
	if operation_id != _latest_autostart_operation_id:
		return
	if not is_instance_valid(_autostart_check_box) \
			or _autostart_check_box.is_queued_for_deletion():
		return
	_autostart_check_box.disabled = false
	if operation == "query":
		var matches := bool(result.get("matches", false))
		var exists := bool(result.get("exists", false))
		var legacy_matches := bool(result.get("legacy_matches", false))
		_autostart_check_box.set_pressed_no_signal(matches)
		if matches:
			_settings_feedback.text = "已設定由目前這個 EXE 隨 Windows 登入啟動。"
		elif legacy_matches:
			# Older builds stored Godot's forward-slash executable path. The
			# entry already expresses the user's autostart preference, so
			# migrate it to a native Windows command automatically.
			_settings_feedback.text = "正在更新舊的開機啟動路徑…"
			_start_autostart_operation("set", true)
		elif exists:
			_settings_feedback.text = "偵測到其他位置的舊設定；重新勾選即可更新。"
		else:
			_settings_feedback.text = "這項設定只套用到目前的 Windows 使用者。"
	elif bool(result.get("success", false)):
		_autostart_check_box.set_pressed_no_signal(enabled)
		_settings_feedback.text = (
			"已啟用開機自動啟動。" if enabled else "已關閉開機自動啟動。"
		)
	else:
		_autostart_check_box.set_pressed_no_signal(not enabled)
		_settings_feedback.text = "設定失敗，請稍後再試。"


func _finish_autostart_thread(operation_id: int) -> void:
	var operation_thread: Thread = _autostart_threads.get(operation_id)
	if is_instance_valid(operation_thread) and operation_thread.is_started():
		operation_thread.wait_to_finish()
	_autostart_threads.erase(operation_id)


func _finish_all_autostart_threads() -> void:
	for operation_id: int in _autostart_threads.keys():
		_finish_autostart_thread(operation_id)


func _request_shutdown() -> void:
	if _shutting_down:
		return
	_prepare_shutdown()
	get_tree().quit()


func _prepare_shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	set_process(false)
	set_process_unhandled_input(false)
	_left_press_pending = false
	_dragging = false
	pet.set_dragging(false)
	context_menu.hide()
	_bubble_token += 1
	bubble.visible = false
	bubble_tail.visible = false
	_save_stats_window_size()
	state.save_state()
	_finish_all_autostart_threads()
	_remove_status_indicator()
	_destroy_stats_window()


func _save_stats_window_size() -> void:
	if not is_instance_valid(_stats_window):
		return
	var current_size := _stats_window.size
	if current_size.x < MIN_STATS_SIZE.x or current_size.y < MIN_STATS_SIZE.y:
		return
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("details_window", "width", current_size.x)
	config.set_value("details_window", "height", current_size.y)
	config.save(UI_SETTINGS_PATH)

func _refresh_ui(snapshot: Dictionary) -> void:
	pet.set_progression(snapshot)
	pet.set_visual_size(float(snapshot.get("visual_scale", 1.0)))
	_update_unlock_tracking()
	var level_text := "Lv.%d  ·  %d 金幣  ·  XP %d/%d" % [
		snapshot.level, snapshot.coins, snapshot.xp, snapshot.level * 20
	]
	if is_instance_valid(_stats_status):
		_stats_status.text = level_text
		_wish_status.text = "願望：%s" % _formatted_wish_text(snapshot)
		var next_unlock: Dictionary = pet.get_next_unlock()
		if next_unlock.is_empty():
			_unlock_status.text = "目前已解鎖所有角色動作"
		else:
			_unlock_status.text = "下一動作：%s　需要 Lv.%d、親密度 %d" % [
				next_unlock.name, next_unlock.level, next_unlock.affection
			]
		for key: String in _stats_bars:
			(_stats_bars[key] as ProgressBar).value = float(snapshot[key])
	if context_menu.item_count > 0:
		context_menu.set_item_text(0, level_text)


func _wish_icon(action: String) -> String:
	return pet.get_interaction_icon(action, _default_interaction_icon(action))


func _interaction_label(action: String) -> String:
	return pet.get_interaction_label(action, _default_interaction_label(action))


func _interaction_icon(action: String) -> String:
	return pet.get_interaction_icon(action, _default_interaction_icon(action))


func _default_interaction_label(action: String) -> String:
	match action:
		"feed":
			return "餵食"
		"water":
			return "喝水"
		"pet":
			return "摸摸"
		"work":
			return "工作"
		"sleep":
			return "睡覺"
		_:
			return action


func _default_interaction_icon(action: String) -> String:
	match action:
		"feed":
			return "🥕"
		"water":
			return "💧"
		"sleep":
			return "💤"
		"work":
			return "🪙"
		"pet":
			return "✋"
		_:
			return ""


func _formatted_wish_text(snapshot: Dictionary) -> String:
	var action := String(snapshot.get("wish_action", ""))
	if action.is_empty() or not bool(snapshot.get("has_active_wish", false)):
		return "目前沒有願望"
	var remaining := maxi(
		int(snapshot.get("wish_expires_at", 0)) - int(Time.get_unix_time_from_system()),
		0
	)
	var minutes := maxi(ceili(remaining / 60.0), 1)
	var fallback := String(snapshot.get("wish_text", "目前沒有願望"))
	return pet.get_interaction_wish(action, fallback, minutes)


func _update_unlock_tracking() -> void:
	var unlocked: Array[String] = pet.get_unlocked_action_ids()
	if not _unlock_tracking_ready:
		for action: String in unlocked:
			_known_unlocked_actions[action] = true
		_unlock_tracking_ready = true
		return
	for action: String in unlocked:
		if _known_unlocked_actions.has(action):
			continue
		_known_unlocked_actions[action] = true
		call_deferred("_celebrate_unlock", action)


func _celebrate_unlock(action: String) -> void:
	await get_tree().create_timer(0.4).timeout
	var unlock_fallback := "解鎖了新的動作：%s！" % action
	say(pet.get_dialogue("action_unlocked", unlock_fallback).replace("{action}", action), 4.0)
	if not pet.is_busy() and not state.is_action_busy():
		pet.play_action(action)


func _place_bottom_right() -> void:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	DisplayServer.window_set_position(Vector2i(
		usable.end.x - ceili(visual_bounds.end.x) - 24,
		usable.end.y - ceili(visual_bounds.end.y)
	))


func _recover_pet() -> void:
	_left_press_pending = false
	_dragging = false
	pet.set_dragging(false)
	if is_instance_valid(_auto_move_tween):
		_auto_move_tween.kill()
		_auto_move_tween = null
		pet.cancel_roll()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var screen := DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	DisplayServer.window_set_position(Vector2i(
		usable.end.x - ceili(visual_bounds.end.x) - 24,
		usable.end.y - ceili(visual_bounds.end.y)
	))


func _clamp_window_position(requested: Vector2i) -> Vector2i:
	var window_size := DisplayServer.window_get_size()
	var screen := DisplayServer.get_screen_from_rect(Rect2i(requested, window_size))
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	return Vector2i(
		clampi(
			requested.x,
			usable.position.x - floori(visual_bounds.position.x),
			usable.end.x - ceili(visual_bounds.end.x)
		),
		clampi(
			requested.y,
			usable.position.y - floori(visual_bounds.position.y),
			usable.end.y - ceili(visual_bounds.end.y)
		)
	)


func _style_bubble() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.953, 0.988, 0.996, 0.82)
	style.border_color = Color(0.204, 0.498, 0.6, 0.82)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 1)
	bubble.add_theme_stylebox_override("panel", style)
	bubble_tail.color = style.bg_color
	bubble_label.add_theme_color_override("font_color", Color("#183247"))
	bubble_label.add_theme_color_override("font_outline_color", Color("#ffffff"))
	bubble_label.add_theme_constant_override("outline_size", 1)
