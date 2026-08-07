extends SceneTree

const WindowsAutostartServiceScript = preload("res://scripts/windows_autostart_service.gd")

var _failures := 0


func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame

	_assert_true(
		not bool(ProjectSettings.get_setting("display/window/size/no_focus", true)),
		"desktop pet window accepts focus so native popup menus dismiss on outside clicks"
	)
	_assert_true(main.pet.visible, "pet is revealed after native window setup")
	_assert_equal(
		main.state.save_path,
		"user://profiles/%s/save_v2.json" % (
			main.pet.get_character_id().to_lower().validate_filename().replace(" ", "_")
		),
		"active character ID selects the gameplay save profile"
	)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var recovery_deadline := Time.get_ticks_msec() + 1500
	while DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED \
			and Time.get_ticks_msec() < recovery_deadline:
		await create_timer(0.05).timeout
	_assert_equal(
		DisplayServer.window_get_mode(),
		DisplayServer.WINDOW_MODE_WINDOWED,
		"per-frame check restores a natively minimized pet window"
	)
	_assert_true(
		main.pet.get_dialogue("startup", "__fallback__") != "__fallback__",
		"active character pack supplies dialogue"
	)
	_assert_equal(
		main.pet.get_dialogue("__missing_dialogue__", "fallback"),
		"fallback",
		"missing character dialogue uses the built-in fallback"
	)
	if DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		_assert_true(
			is_instance_valid(main._status_indicator)
				and is_instance_valid(main._tray_exit_menu)
				and main._status_indicator.menu != NodePath(),
			"status indicator uses a dedicated native exit menu"
		)
		_assert_equal(
			main._tray_exit_menu.item_count,
			1,
			"status indicator menu contains only the exit command"
		)
		_assert_equal(
			main._tray_exit_menu.get_item_id(0),
			7,
			"status indicator exit command uses the shutdown action"
		)
	_assert_equal(
		main.pet.get_interaction_label("feed", "__fallback__"),
		"餵食",
		"active character pack supplies interaction labels"
	)
	_assert_true(
		"3" in main.pet.get_interaction_wish(
			"feed", "fallback {minutes}", 3
		),
		"character wish template replaces the minutes placeholder"
	)
	_assert_true(main.pet.contains_point(Vector2(140, 190)), "pet center is interactive")
	_assert_true(not main.pet.contains_point(Vector2(5, 5)), "transparent corner is not interactive")
	main.pet.play_action("pet")
	await process_frame
	_assert_true(
		main.pet.is_busy() and main.pet._active_request_id == 0,
		"autonomous action runs without a care request ID"
	)
	main._run_care_action(3)
	await process_frame
	_assert_true(
		main.state.is_action_busy() and main.pet._active_request_id > 0,
		"care action safely replaces an autonomous action with the same animation ID"
	)
	var care_interrupt_deadline := Time.get_ticks_msec() + 3000
	while main.state.is_action_busy() \
			and Time.get_ticks_msec() < care_interrupt_deadline:
		await create_timer(0.05).timeout
	_assert_true(
		not main.state.is_action_busy(),
		"care action completes after interrupting autonomous animation"
	)
	main.pet.play_action("move")
	await process_frame
	_assert_true(main.pet.is_busy(), "autonomous animation starts for drag interruption test")
	_assert_true(main._can_begin_drag(), "autonomous animation does not block dragging")
	main.pet.set_dragging(true)
	_assert_true(not main.pet.is_busy() or main.pet._dragging, "dragging interrupts autonomous animation")
	var first_drag_region: Rect2 = main.pet._sprite.region_rect
	main.pet.set_drag_motion(true)
	await create_timer(0.14).timeout
	var drag_sequence: Array = main.pet._sequence_for(
		main.pet._action_definition("drag")
	)
	if drag_sequence.size() > 1:
		_assert_true(
			main.pet._sprite.region_rect != first_drag_region,
			"drag motion advances through the configured frame sequence"
		)
	main.pet.set_dragging(false)
	main.pet.set_facing_direction(-1)
	_assert_true(
		not main.pet._sprite.flip_h and main.pet._sprite.scale.x > 0.0,
		"left-facing movement uses the source artwork"
	)
	main.pet.set_facing_direction(1)
	_assert_true(
		main.pet._sprite.flip_h and main.pet._sprite.scale.x > 0.0,
		"right-facing movement mirrors without a negative transform"
	)
	main.pet._facing_direction = 1
	main.pet._apply_sprite_scale({"scale": 1.0, "source_facing": "right"})
	_assert_true(
		not main.pet._sprite.flip_h and main.pet._sprite.scale.x > 0.0,
		"right-facing source artwork is not mirrored when moving right"
	)
	main.pet.set_facing_direction(-1)
	main.bubble.visible = true
	main.bubble_tail.visible = true
	main._refresh_interaction_polygon()
	var bubble_pet_overlap := Vector2(-1, -1)
	var bubble_rect: Rect2 = main.bubble.get_global_rect()
	for y in range(floori(bubble_rect.position.y), ceili(bubble_rect.end.y), 2):
		for x in range(floori(bubble_rect.position.x), ceili(bubble_rect.end.x), 2):
			var candidate := Vector2(x, y)
			if main.pet.contains_point(candidate):
				bubble_pet_overlap = candidate
				break
		if bubble_pet_overlap.x >= 0:
			break
	if bubble_pet_overlap.x < 0:
		bubble_pet_overlap = bubble_rect.get_center()
	_assert_true(
		main._is_speech_overlay_at(bubble_pet_overlap),
		"speech pass-through test uses the visible bubble area"
	)
	_assert_true(
		main._is_pet_interactive_at(bubble_pet_overlap),
		"visible speech bubble is handled as part of the pet"
	)
	var native_hit_polygon: PackedVector2Array = \
		main.get_window().mouse_passthrough_polygon
	_assert_true(
		Geometry2D.is_point_in_polygon(bubble_pet_overlap, native_hit_polygon),
		"native desktop hit region includes the visible speech bubble"
	)
	_assert_true(
		main._is_pet_interactive_at(Vector2(140, 128)),
		"visible speech tail is handled as part of the pet"
	)
	main.bubble.visible = false
	main.bubble_tail.visible = false
	main._refresh_interaction_polygon()
	await process_frame
	native_hit_polygon = main.get_window().mouse_passthrough_polygon
	var hidden_speech_point := bubble_rect.position + Vector2(10, 10)
	_assert_true(
		not Geometry2D.is_point_in_polygon(hidden_speech_point, native_hit_polygon),
		"hidden speech area is removed from the native hit region"
	)
	_assert_true(
		Geometry2D.is_point_in_polygon(Vector2(140, 190), native_hit_polygon),
		"native desktop hit region includes the visible pet"
	)

	var screen_for_drag := DisplayServer.window_get_current_screen()
	if screen_for_drag < 0:
		screen_for_drag = DisplayServer.get_primary_screen()
	var drag_usable := DisplayServer.screen_get_usable_rect(screen_for_drag)
	var visual_bounds: Rect2 = main.pet.get_visual_bounds_in_canvas()
	var clamped_top_left: Vector2i = main._clamp_window_position(
		drag_usable.position - Vector2i(10000, 10000)
	)
	var visible_at_top_left := Rect2(
		Vector2(clamped_top_left) + visual_bounds.position,
		visual_bounds.size
	)
	_assert_true(
		visible_at_top_left.position.x >= drag_usable.position.x - 1
			and visible_at_top_left.position.y >= drag_usable.position.y - 1,
		"drag clamp uses visible pet bounds at the top-left"
	)
	var clamped_bottom_right: Vector2i = main._clamp_window_position(
		drag_usable.end + Vector2i(10000, 10000)
	)
	var visible_at_bottom_right := Rect2(
		Vector2(clamped_bottom_right) + visual_bounds.position,
		visual_bounds.size
	)
	_assert_true(
		absf(visible_at_bottom_right.end.y - drag_usable.end.y) <= 1.0,
		"pet bottom can reach the taskbar edge without entering it"
	)

	main._show_context_menu(Vector2i(140, 190))
	await process_frame
	main.context_menu.id_pressed.emit(6)
	main.context_menu.hide()
	await process_frame
	await process_frame
	await process_frame
	_assert_true(main._stats_window.visible, "details window opens on first request")
	_assert_true(not main._stats_window.unresizable, "details window can be resized")
	_assert_true(not main._stats_window.transient, "details window is an independent native window")
	_assert_true(not main._stats_window.always_on_top, "details window behaves like a normal window")
	var stats_open_right_click := InputEventMouseButton.new()
	stats_open_right_click.button_index = MOUSE_BUTTON_RIGHT
	stats_open_right_click.position = Vector2(140, 190)
	stats_open_right_click.pressed = true
	main._unhandled_input(stats_open_right_click)
	await process_frame
	_assert_true(
		main.context_menu.visible,
		"pet right-click menu remains available while details are open"
	)
	main.context_menu.hide()
	_assert_true(
		not main._character_tab_loaded,
		"character packs are not scanned when the details window first opens"
	)
	main._on_stats_tab_changed(main._character_tab_index)
	_assert_true(main._character_tab_loaded, "character tab scans only when selected")
	_assert_true(
		main._character_entries.size() >= 1,
		"character tab always lists the built-in public character"
	)
	_assert_equal(
		main._character_use_button.text,
		"重新載入角色",
		"active character selection offers an explicit reload"
	)
	_assert_true(
		not main._character_use_button.disabled,
		"active character reload remains available"
	)
	for character_index in main._character_entries.size():
		if String(main._character_entries[character_index].id) \
				== main.pet.get_character_id():
			continue
		main._character_list.select(character_index)
		main._update_character_buttons()
		_assert_equal(
			main._character_use_button.text,
			"使用選取角色",
			"inactive character selection keeps the switch action"
		)
		break
	main._stats_window.mode = Window.MODE_MINIMIZED
	await process_frame
	_assert_equal(
		main._stats_window.mode,
		Window.MODE_MINIMIZED,
		"details window remains minimized until explicitly opened"
	)
	var minimized_stats_window_id: int = main._stats_window.get_instance_id()
	main._show_stats_window()
	await process_frame
	await process_frame
	_assert_equal(main._stats_window.mode, Window.MODE_WINDOWED, "opening restores a minimized details window")
	_assert_equal(
		main._stats_window.get_instance_id(),
		minimized_stats_window_id,
		"opening focuses the existing details window instead of recreating it"
	)
	_assert_true(
		is_instance_valid(main._fps_option_button),
		"details window includes an FPS preset selector"
	)
	_assert_true(
		is_instance_valid(main._autostart_check_box),
		"details window includes a Windows autostart setting"
	)
	var autostart_pressed_style := (
		main._autostart_check_box.get_theme_stylebox("pressed") as StyleBoxFlat
	)
	var autostart_hover_pressed_style := (
		main._autostart_check_box.get_theme_stylebox("hover_pressed")
		as StyleBoxFlat
	)
	_assert_true(
		autostart_pressed_style != null
			and autostart_hover_pressed_style != null,
		"autostart checkbox defines checked and checked-hover styles"
	)
	_assert_equal(
		autostart_hover_pressed_style.bg_color,
		autostart_pressed_style.bg_color,
		"hovering a checked autostart option preserves its selected background"
	)
	_assert_equal(
		autostart_hover_pressed_style.content_margin_left,
		autostart_pressed_style.content_margin_left,
		"hovering a checked autostart option preserves its text alignment"
	)
	_assert_equal(
		main._autostart_check_box.get_theme_constant(
			"align_to_largest_stylebox"
		),
		1,
		"autostart checkbox keeps one layout across interaction states"
	)
	var original_target_fps := Engine.max_fps
	main._set_target_fps(47)
	_assert_equal(
		Engine.max_fps,
		60,
		"unsupported FPS values normalize to the nearest preset"
	)
	var settings_config := ConfigFile.new()
	_assert_equal(
		settings_config.load(main.UI_SETTINGS_PATH),
		OK,
		"FPS setting is persisted"
	)
	_assert_equal(
		int(settings_config.get_value("performance", "target_fps", 0)),
		60,
		"persisted FPS setting matches the normalized preset"
	)
	main._set_target_fps(original_target_fps)
	if OS.has_feature("editor"):
		_assert_true(
			main._autostart_check_box.disabled,
			"development runs cannot register the editor for autostart"
		)
	if OS.get_name() == "Windows":
		var autostart_service = WindowsAutostartServiceScript.new()
		_assert_equal(
			autostart_service.build_command(
				"C:/Program Files/Open Desktop Pet/Pet.exe"
			),
			"\"C:\\Program Files\\Open Desktop Pet\\Pet.exe\"",
			"autostart commands normalize Godot paths for Windows"
		)
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var stats_rect := Rect2i(main._stats_window.position, main._stats_window.size)
	_assert_true(usable.encloses(stats_rect), "details window remains inside usable screen")
	main._bring_stats_window_forward()
	await process_frame
	_assert_true(main._stats_window.visible, "an existing details window can be brought forward")
	var remembered_stats_size := Vector2i(380, 520)
	main._stats_window.size = remembered_stats_size
	await process_frame
	var first_stats_window_id: int = main._stats_window.get_instance_id()
	main._destroy_stats_window()
	await process_frame
	main._show_stats_window()
	await process_frame
	await process_frame
	_assert_true(main._stats_window.visible, "details window is visible after native recreation")
	_assert_true(
		main._stats_window.get_instance_id() != first_stats_window_id,
		"details window recreation uses a fresh native window"
	)
	_assert_equal(
		main._stats_window.size,
		remembered_stats_size,
		"details window remembers the user-selected size"
	)
	main._destroy_stats_window()

	main.say("快速訊息一", 0.1)
	main.say("💤", 0.1)
	await process_frame
	_assert_true(main.bubble.visible, "latest speech is visible")
	_assert_equal(main.bubble_label.text, "💤", "latest speech replaces earlier speech")
	await create_timer(0.2).timeout
	_assert_true(not main.bubble.visible, "speech hides after its duration")
	_assert_equal(
		main.CODEX_NOTIFICATION_DURATION_SECONDS,
		60.0,
		"Codex notification remains available for one minute"
	)
	_assert_equal(
		main.bubble.mouse_default_cursor_shape,
		Control.CURSOR_POINTING_HAND,
		"speech bubble advertises a pointing-hand cursor"
	)
	var regular_bubble_color: Color = (
		main.bubble.get_theme_stylebox("panel") as StyleBoxFlat
	).bg_color
	main._enqueue_codex_status("Codex 測試通知", "idle")
	await process_frame
	await process_frame
	_assert_true(
		main._codex_notification_active and main.bubble.visible,
		"Codex notification displays as an active speech bubble"
	)
	_assert_true(
		not main.bubble_tail.visible,
		"Codex notification uses a rectangular bubble without a speech tail"
	)
	var codex_bubble_color: Color = (
		main.bubble.get_theme_stylebox("panel") as StyleBoxFlat
	).bg_color
	_assert_true(
		not codex_bubble_color.is_equal_approx(regular_bubble_color),
		"Codex notification background differs from regular speech"
	)
	_assert_equal(
		main._codex_notification_duration(true),
		3.0,
		"Codex notification lasts three seconds when VS Code is foreground"
	)
	_assert_equal(
		main._codex_notification_duration(false),
		60.0,
		"Codex notification keeps the normal duration outside VS Code"
	)
	var first_codex_bubble_token: int = main._bubble_token
	main._enqueue_codex_status("Codex 最新通知", "idle")
	await process_frame
	await process_frame
	_assert_true(
		main._codex_notification_active and main.bubble.visible,
		"replacement Codex notification remains active"
	)
	_assert_equal(
		main.bubble_label.text,
		"Codex 最新通知",
		"latest Codex notification replaces the previous bubble"
	)
	_assert_true(
		main._bubble_token > first_codex_bubble_token,
		"replacing a Codex notification invalidates the previous timer"
	)
	main._dismiss_active_codex_notification()
	await process_frame
	_assert_true(
		not main._codex_notification_active and not main.bubble.visible,
		"click acknowledgement dismisses the active Codex notification"
	)

	_assert_true(
		not main.has_method("_schedule_restart_after_exit")
			and not main.has_method("_restart_wait_script"),
		"character changes do not use an external restart helper"
	)
	var main_process_id := OS.get_process_id()
	var active_character_id: String = main.pet.get_character_id()
	_assert_true(
		main._apply_character_without_restart(active_character_id, true),
		"active character reload succeeds in the current process"
	)
	_assert_equal(
		OS.get_process_id(),
		main_process_id,
		"active character reload keeps the same process"
	)
	_assert_equal(
		main.pet.get_character_id(),
		active_character_id,
		"active character reload preserves the selected character"
	)
	main._build_stats_window()
	main._known_unlocked_actions = {"idle": true}
	main._unlock_tracking_ready = true
	_assert_true(
		main._apply_character_without_restart("open_desktop_pet_default", false),
		"switching to the public character succeeds without restarting"
	)
	await create_timer(0.5).timeout
	_assert_true(
		not main.bubble.visible,
		"switching profiles does not celebrate actions that were already unlocked"
	)
	for action: String in ["feed", "water", "pet", "work", "sleep"]:
		var button: Button = main._care_action_buttons[action]
		_assert_equal(
			button.text,
			"%s %s" % [
				main._interaction_icon(action),
				main._interaction_label(action),
			],
			"details-panel %s text refreshes from the active character JSON" % action
		)
	var feed_menu_index: int = main.context_menu.get_item_index(1)
	_assert_true(
		main.context_menu.get_item_text(feed_menu_index).contains(
			main._interaction_icon("feed")
		) and main.context_menu.get_item_text(feed_menu_index).contains(
			main._interaction_label("feed")
		),
		"context-menu care text refreshes from the active character JSON"
	)
	_assert_equal(
		main._last_state_message,
		main.pet.get_dialogue("startup", "右鍵操作・雙擊摸摸"),
		"cached character dialogue refreshes from the active character JSON"
	)
	_assert_true(
		main._apply_character_without_restart(active_character_id, false),
		"switching back to the original character succeeds without restarting"
	)
	main._destroy_stats_window()

	var energy_before := float(main.state.data.energy)
	main._show_context_menu(Vector2i(140, 190))
	main.context_menu.id_pressed.emit(5)
	main.context_menu.hide()
	var sleep_start_deadline := Time.get_ticks_msec() + 4000
	while not main.state.is_sleeping() \
			and Time.get_ticks_msec() < sleep_start_deadline:
		await process_frame
	_assert_true(main.state.is_sleeping(), "sleep enters its persistent recovery state")
	_assert_true(main.pet.is_busy(), "sleep animation keeps looping while asleep")
	_assert_true(
		not main._can_act_autonomously(),
		"autonomous actions cannot interrupt active sleep"
	)
	var sleeping_energy := float(main.state.data.energy)
	main.state._process_sleep(main.state.SLEEP_RECOVERY_INTERVAL_SECONDS)
	_assert_true(
		float(main.state.data.energy) > sleeping_energy,
		"sleep restores energy progressively"
	)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	main._unhandled_input(right_click)
	main.context_menu.hide()
	_assert_true(main.state.wake_sleep("test"), "sleep supports an explicit wake-up")
	await process_frame
	_assert_true(
		not main.state.is_action_busy() and not main.pet.is_busy(),
		"waking releases both gameplay and visual action locks"
	)
	_assert_true(float(main.state.data.energy) >= energy_before, "waking keeps recovered energy")
	# Allow startup/action speech SceneTreeTimers to finish before teardown so
	# the integration run also verifies clean resource ownership.
	await create_timer(6.3).timeout
	main.bubble.visible = true
	var shutdown_bubble_token: int = main._bubble_token
	main._prepare_shutdown()
	_assert_true(main._shutting_down, "shutdown preparation is idempotently guarded")
	_assert_true(not main.bubble.visible, "shutdown hides an active speech bubble")
	_assert_true(
		main._bubble_token > shutdown_bubble_token,
		"shutdown invalidates pending speech timers"
	)
	main.queue_free()
	await process_frame
	await process_frame

	if _failures > 0:
		push_error("WINDOW_INTEGRATION_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("WINDOW_INTEGRATION_TEST_OK")
		quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("Assertion failed: %s (actual=%s expected=%s)" % [label, actual, expected])
