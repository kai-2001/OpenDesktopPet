extends Node2D

const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_STATS_SIZE := Vector2i(400, 720)
const MIN_STATS_SIZE := Vector2i(360, 480)
const VISIBILITY_CHECK_INTERVAL := 0.10

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
var _stats_bars: Dictionary = {}
var _dragging := false
var _left_press_pending := false
var _left_press_started_ms := 0
var _drag_offset := Vector2i.ZERO
var _drag_origin := Vector2i.ZERO
var _bubble_token := 0
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
var _visibility_watchdog: Timer

func _ready() -> void:
	# PetVisual is ready before this parent node. Keep its first loaded frame
	# hidden until the native transparent window has been positioned and shaped.
	pet.visible = false
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	_style_bubble()
	_connect_signals()
	_setup_context_menu()
	_setup_idle_behavior()
	_setup_visibility_watchdog()
	_last_global_mouse = DisplayServer.mouse_get_position()
	_last_user_activity_ms = Time.get_ticks_msec()
	call_deferred("_finish_window_setup")


func _process(_delta: float) -> void:
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
		if (mouse.distance_to(_drag_origin) >= 6.0 or held_ms >= 220) \
				and _can_begin_drag():
			_begin_drag(mouse)
	if not _dragging:
		return
	if mouse.distance_to(_last_drag_mouse) > 1.0:
		pet.set_drag_motion(true)
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
		if _is_stats_window_open():
			# Do not trust a stale native `visible` flag. Recreate the native
			# window so a panel lost by Windows is always recoverable.
			_destroy_stats_window()
			call_deferred("_show_stats_window")
		else:
			_show_context_menu(Vector2i(event.position))


func _begin_drag(mouse: Vector2i) -> void:
	_left_press_pending = false
	_dragging = true
	_last_drag_mouse = mouse
	pet.set_dragging(true)
	pet.set_drag_motion(true)
	_set_cursor_shape(Input.CURSOR_DRAG)


func _can_begin_drag() -> bool:
	# PetVisual.set_dragging() deliberately cancels its current animation.
	# PetState stays busy only for user-requested care actions whose result must
	# settle, so those remain protected while autonomous animations can yield.
	return not state.is_action_busy()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_stats_window_size()
		state.save_state()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Godot does not expose Win32's foreground hook directly. These
		# notifications provide the event-driven fast path; the lightweight
		# watchdog remains the fallback for Show Desktop transitions that do
		# not deliver a focus notification.
		call_deferred("_check_window_visibility")


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


func _setup_visibility_watchdog() -> void:
	_visibility_watchdog = Timer.new()
	_visibility_watchdog.name = "WindowVisibilityWatchdog"
	_visibility_watchdog.one_shot = false
	_visibility_watchdog.wait_time = VISIBILITY_CHECK_INTERVAL
	_visibility_watchdog.timeout.connect(_check_window_visibility)
	add_child(_visibility_watchdog)
	_visibility_watchdog.start()


func _check_window_visibility() -> bool:
	# Show Desktop can minimize an always-on-top Godot window without a useful
	# application event. Poll the cheap window mode at 10 Hz so recovery is
	# effectively immediate without tying the check to every rendered frame.
	var recovered := false
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(
			DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true
		)
		recovered = true

	if is_instance_valid(_stats_window) \
			and _stats_window.visible \
			and _stats_window.mode == Window.MODE_MINIMIZED:
		_stats_window.mode = Window.MODE_WINDOWED
		_stats_window.always_on_top = true
		recovered = true

	return recovered


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
	context_menu.add_separator()
	context_menu.add_item("❌  儲存並離開", 7)
	context_menu.id_pressed.connect(_on_context_action)
	_refresh_ui(state.get_snapshot())


func _show_context_menu(at: Vector2i) -> void:
	context_menu.position = DisplayServer.window_get_position() + at
	context_menu.popup()


func _on_context_action(id: int) -> void:
	match id:
		1, 2, 3, 4, 5:
			_run_care_action(id)
		6:
			call_deferred("_show_stats_window")
		7:
			state.save_state()
			get_tree().quit()
		20:
			state.change_visual_size(-0.1)
			_say_dialogue("size_smaller", "這個大小比較不擋路。", 2.0)
		21:
			state.change_visual_size(0.1)
			_say_dialogue("size_larger", "放大一點點。", 2.0)


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
	pet.play_action("move")
	_auto_move_tween = create_tween()
	_auto_move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_auto_move_tween.tween_method(
		func(weight: float) -> void:
			DisplayServer.window_set_position(Vector2i(Vector2(start).lerp(Vector2(target), weight))),
		0.0, 1.0, 0.9
	)
	await _auto_move_tween.finished
	_auto_move_tween = null


func _build_stats_window() -> void:
	_stats_bars.clear()
	_stats_window = Window.new()
	_stats_window.title = "桌寵詳細狀態"
	_stats_window.size = DEFAULT_STATS_SIZE
	_stats_window.min_size = MIN_STATS_SIZE
	_stats_window.unresizable = false
	# A transient child of the tiny borderless always-on-top pet window can be
	# reported visible while remaining behind other windows on Windows.
	_stats_window.transient = false
	_stats_window.always_on_top = true
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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

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
	content.add_child(action_grid)
	content.add_child(HSeparator.new())

	var hint := _new_label("詳細面板開啟時，角色右鍵選單暫停。\n關閉面板後會自動恢復。", 14, Color("#b9ced5"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	var close_button := Button.new()
	close_button.text = "關閉詳細狀態"
	close_button.custom_minimum_size.y = 42
	close_button.pressed.connect(_destroy_stats_window)
	content.add_child(close_button)


func _run_care_action(id: int) -> void:
	if state.is_action_busy() or pet.is_busy():
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
	if not is_instance_valid(_stats_window):
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
	_stats_bars.clear()


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
