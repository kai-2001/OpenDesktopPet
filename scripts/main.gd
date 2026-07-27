extends Node2D

@onready var state: Node = $PetState
@onready var pet: Node2D = $PetVisual
@onready var bubble: PanelContainer = $SpeechBubble
@onready var bubble_label: Label = $SpeechBubble/Margin/Label
@onready var bubble_tail: Polygon2D = $SpeechTail
@onready var wish_badge: Label = $WishBadge
@onready var context_menu: PopupMenu = $ContextMenu
var _stats_window: Window
var _stats_status: Label
var _wish_status: Label
var _unlock_status: Label
var _last_message_status: Label
var _stats_bars: Dictionary = {}
var _dragging := false
var _drag_moved := false
var _left_press_pending := false
var _left_press_started_ms := 0
var _drag_offset := Vector2i.ZERO
var _drag_origin := Vector2i.ZERO
var _bubble_token := 0
var _idle_count := 0
var _stats_open_timer: Timer
var _last_global_mouse := Vector2i.ZERO
var _last_drag_mouse := Vector2i.ZERO
var _last_user_activity_ms := 0
var _auto_move_tween: Tween
var _known_unlocked_actions: Dictionary = {}
var _unlock_tracking_ready := false
var _last_state_message := "尚無紀錄"

var _pet_hit_polygon := PackedVector2Array([
	Vector2(70, 100), Vector2(210, 100), Vector2(245, 170),
	Vector2(220, 310), Vector2(60, 310), Vector2(35, 170)
])


func _ready() -> void:
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	_style_bubble()
	_build_stats_window()
	_setup_stats_open_timer()
	_connect_signals()
	_setup_context_menu()
	_setup_idle_behavior()
	_last_global_mouse = DisplayServer.mouse_get_position()
	_last_user_activity_ms = Time.get_ticks_msec()
	call_deferred("_finish_window_setup")
	call_deferred("_prime_stats_window")
	say("雙擊摸摸我，右鍵可以直接操作！", 8.0)


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
				and not pet.is_busy() and not state.is_action_busy():
			_begin_drag(mouse)
	if not _dragging:
		return
	if mouse.distance_to(_drag_origin) > 4.0:
		_drag_moved = true
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
			_drag_moved = false
			_drag_origin = DisplayServer.mouse_get_position()
			_last_drag_mouse = _drag_origin
			_drag_offset = _drag_origin - DisplayServer.window_get_position()
		else:
			var was_dragging := _dragging
			_left_press_pending = false
			if was_dragging:
				_dragging = false
				pet.set_dragging(false)
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			else:
				_single_click_reaction()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_left_press_pending = false
		_dragging = false
		pet.set_dragging(false)
		if not _stats_window.visible:
			_show_context_menu(Vector2i(event.position))


func _begin_drag(mouse: Vector2i) -> void:
	_left_press_pending = false
	_dragging = true
	_drag_moved = true
	_last_drag_mouse = mouse
	pet.set_dragging(true)
	pet.set_drag_motion(true)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		state.save_state()
		get_tree().quit()


func say(text: String, seconds := 8.0) -> void:
	_bubble_token += 1
	var token := _bubble_token
	bubble_label.text = text
	bubble.visible = true
	bubble_tail.visible = true
	_layout_speech_bubble(text)
	await get_tree().create_timer(seconds).timeout
	if token == _bubble_token:
		bubble.visible = false
		bubble_tail.visible = false


func _layout_speech_bubble(text: String) -> void:
	const BUBBLE_WIDTH := 220.0
	const TEXT_WIDTH := 190.0
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
	bubble.position = Vector2((280.0 - BUBBLE_WIDTH) / 2.0, BUBBLE_BOTTOM - bubble_height)
	bubble.size = Vector2(BUBBLE_WIDTH, bubble_height)
	bubble_tail.polygon = PackedVector2Array([
		Vector2(132, BUBBLE_BOTTOM - 2),
		Vector2(148, BUBBLE_BOTTOM - 2),
		Vector2(140, BUBBLE_BOTTOM + 11),
	])


func _finish_window_setup() -> void:
	_place_bottom_right()
	# Only the visible pet region captures the mouse; transparent corners click through.
	_set_pet_passthrough()


func _set_pet_passthrough() -> void:
	get_window().mouse_passthrough_polygon = _pet_hit_polygon


func _update_cursor(global_mouse: Vector2i) -> void:
	if _dragging:
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		return
	var local_mouse := Vector2(global_mouse - DisplayServer.window_get_position())
	var over_pet := Geometry2D.is_point_in_polygon(local_mouse, _pet_hit_polygon)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over_pet else Input.CURSOR_ARROW)


func _connect_signals() -> void:
	state.changed.connect(_refresh_ui)
	state.message_requested.connect(_show_state_message)
	state.action_requested.connect(pet.play_action)
	_refresh_ui(state.data)


func _show_state_message(text: String) -> void:
	_last_state_message = text.replace("\n", "　")
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % _last_state_message
	say(text, 8.0)


func _setup_context_menu() -> void:
	context_menu.add_item("Lv.1  ·  20 金幣", 100)
	context_menu.set_item_disabled(0, true)
	context_menu.add_separator()
	context_menu.add_item("🥕  餵食（2 金幣）", 1)
	context_menu.add_item("💧  喝水（1 金幣）", 2)
	context_menu.add_item("✋  摸摸", 3)
	context_menu.add_item("🪙  工作（賺 7 金幣）", 4)
	context_menu.add_item("💤  睡覺", 5)
	context_menu.add_separator()
	context_menu.add_item("📊  開啟詳細面板", 6)
	context_menu.add_item("🔎  角色縮小", 20)
	context_menu.add_item("🔍  角色放大", 21)
	context_menu.add_separator()
	context_menu.add_item("❌  儲存並離開", 7)
	context_menu.id_pressed.connect(_on_context_action)
	_refresh_ui(state.data)


func _show_context_menu(at: Vector2i) -> void:
	context_menu.position = DisplayServer.window_get_position() + at
	context_menu.popup()


func _on_context_action(id: int) -> void:
	match id:
		1, 2, 3, 4, 5:
			_run_care_action(id)
		6:
			_stats_open_timer.start()
		7:
			state.save_state()
			get_tree().quit()
		20:
			pet.change_visual_size(-0.1)
			say("這個大小比較不擋路。", 2.0)
		21:
			pet.change_visual_size(0.1)
			say("放大一點點。", 2.0)


func _single_click_reaction() -> void:
	var lines := [
		"有事嗎？",
		"我有在聽。",
		"右鍵有快捷操作喔。",
		"再點一下就要收費了。"
	]
	say(lines.pick_random(), 2.0)
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
				say(["我在這裡。", "滾一下好了。", "今天也要照顧我。"].pick_random(), 2.5)
		timer.wait_time = randf_range(11.0, 19.0)
		timer.start()
	)
	add_child(timer)
	timer.start()


func _can_act_autonomously(require_mouse_idle := false) -> bool:
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	return (not require_mouse_idle or mouse_is_idle) \
		and not context_menu.visible \
		and not _stats_window.visible \
		and not _dragging \
		and not pet.is_busy()


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
	_stats_window.size = Vector2i(400, 720)
	_stats_window.min_size = Vector2i(400, 720)
	_stats_window.unresizable = true
	# A child Window is already transient to the desktop-pet window. Marking it
	# always-on-top as well is invalid on Windows and prevents reliable popup.
	_stats_window.always_on_top = false
	_stats_window.visible = false
	_stats_window.close_requested.connect(func() -> void: _stats_window.hide())
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

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

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
	var panel_actions := {
		"🥕 餵食": 1, "💧 喝水": 2, "✋ 摸摸": 3,
		"🪙 工作": 4, "💤 睡覺": 5
	}
	for button_text: String in panel_actions:
		var action_button := Button.new()
		action_button.text = button_text
		action_button.custom_minimum_size = Vector2(100, 38)
		var action_id: int = panel_actions[button_text]
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
	close_button.pressed.connect(func() -> void: _stats_window.hide())
	content.add_child(close_button)


func _run_care_action(id: int) -> void:
	if state.is_action_busy() or pet.is_busy():
		say("先等目前的動作完成～", 1.5)
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
	_refresh_ui(state.data)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var target := Vector2i(pet_position.x - _stats_window.size.x - 14, pet_position.y - 60)
	if target.x < usable.position.x:
		target.x = pet_position.x + pet_size.x + 14
	target.y = clampi(target.y, usable.position.y + 12, usable.end.y - _stats_window.size.y - 12)
	_stats_window.position = target
	_stats_window.show()
	_stats_window.grab_focus()
	_stats_window.move_to_foreground()


func _setup_stats_open_timer() -> void:
	_stats_open_timer = Timer.new()
	_stats_open_timer.one_shot = true
	_stats_open_timer.wait_time = 0.35
	_stats_open_timer.timeout.connect(_show_stats_window)
	add_child(_stats_open_timer)


func _prime_stats_window() -> void:
	_stats_window.position = Vector2i(-10000, -10000)
	_stats_window.popup()
	await get_tree().process_frame
	await get_tree().process_frame
	_stats_window.hide()


func _refresh_ui(snapshot: Dictionary) -> void:
	pet.set_progression(snapshot)
	_update_unlock_tracking()
	var wish_action := String(snapshot.get("wish_action", ""))
	wish_badge.visible = not wish_action.is_empty()
	wish_badge.text = _wish_icon(wish_action)
	var level_text := "Lv.%d  ·  %d 金幣  ·  XP %d/%d" % [
		snapshot.level, snapshot.coins, snapshot.xp, snapshot.level * 20
	]
	if is_instance_valid(_stats_status):
		_stats_status.text = level_text
		_wish_status.text = "願望：%s" % String(snapshot.get("wish_text", "目前沒有願望"))
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
	say("解鎖了新的動作：%s！" % action, 4.0)
	if not pet.is_busy() and not state.is_action_busy():
		pet.play_action(action)


func _place_bottom_right() -> void:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(usable.position + usable.size - size - Vector2i(24, 24))


func _clamp_window_position(requested: Vector2i) -> Vector2i:
	var window_size := DisplayServer.window_get_size()
	var screen := DisplayServer.get_screen_from_rect(Rect2i(requested, window_size))
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	return Vector2i(
		clampi(requested.x, usable.position.x, usable.end.x - window_size.x),
		clampi(requested.y, usable.position.y, usable.end.y - window_size.y)
	)


func _style_bubble() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#f3fcfd")
	style.border_color = Color("#347f99")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.32)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	bubble.add_theme_stylebox_override("panel", style)
	bubble_tail.color = style.bg_color
	bubble_label.add_theme_color_override("font_color", Color("#183247"))
	bubble_label.add_theme_color_override("font_outline_color", Color("#ffffff"))
	bubble_label.add_theme_constant_override("outline_size", 1)
