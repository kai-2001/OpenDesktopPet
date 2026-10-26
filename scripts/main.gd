extends Node2D

const CharacterPackCoordinatorScript = preload("res://scripts/character_pack_coordinator.gd")
const AgentIntegrationControllerScript = preload("res://scripts/agent_integration_controller.gd")
const AgentSettingsPanelControllerScript = preload(
	"res://scripts/agent_settings_panel_controller.gd"
)
const DesktopWindowServiceScript = preload("res://scripts/desktop_window_service.gd")
const PetGameplayCoordinatorScript = preload("res://scripts/pet_gameplay_coordinator.gd")
const PetInputControllerScript = preload("res://scripts/pet_input_controller.gd")
const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const PetVisualScaleScript = preload("res://scripts/pet_visual_scale.gd")
const StatsWindowCoordinatorScript = preload("res://scripts/stats_window_coordinator.gd")
const StatusTabPresenterScript = preload("res://scripts/status_tab_presenter.gd")
const SettingsTabControllerScript = preload("res://scripts/settings_tab_controller.gd")
const CharacterTabControllerScript = preload("res://scripts/character_tab_controller.gd")
const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderPresentationCoordinatorScript = preload(
	"res://scripts/task_reminder_presentation_coordinator.gd"
)
const WindowsAutostartServiceScript = preload("res://scripts/windows_autostart_service.gd")
const DisplayRecoveryControllerScript = preload("res://scripts/display_recovery_controller.gd")
const UpdateCheckCoordinatorScript = preload("res://scripts/update_check_coordinator.gd")
const CjkLineBreaksScript = preload("res://scripts/cjk_line_breaks.gd")
const CharacterEffectPreferencesScript = preload(
	"res://scripts/character_effect_preferences.gd"
)
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_STATS_SIZE := StatsWindowCoordinatorScript.DEFAULT_WINDOW_SIZE
const MIN_STATS_SIZE := StatsWindowCoordinatorScript.MIN_WINDOW_SIZE
const AGENT_NOTIFICATION_DURATION_SECONDS := 60.0
const AGENT_FOREGROUND_NOTIFICATION_DURATION_SECONDS := 3.0
const WINDOW_REVEAL_FRAMES := 3
const STARTUP_DIALOGUE_DURATION_SECONDS := 5.0
const STARTUP_REMINDER_DURATION_SECONDS := 8.0
const TASK_REMINDER_NOTIFICATION_DURATION_SECONDS := 8.0
const REMINDERS_TAB_INDEX := 1
const AGENT_TAB_INDEX := 3
const DRAG_DISTANCE_THRESHOLD_PX := 1.0
const STATUS_ICON = preload("res://assets/branding/birthmark_app_icon.png")

@onready var state: Node = $PetState
@onready var pet: Node2D = $PetVisual
@onready var bubble: PanelContainer = $SpeechBubble
@onready var bubble_label: Label = $SpeechBubble/Margin/Label
@onready var bubble_tail: Polygon2D = $SpeechTail
@onready var task_reminder_badge: TaskReminderBadge = $TaskReminderBadge
@onready var context_menu: PopupMenu = $ContextMenu
var _stats_window: Window
var _stats_tabs: TabContainer
var _stats_tab_buttons: Array[Button] = []
var _autostart_service
var _window_service
var _window_reveal_token := 0
var _gameplay_coordinator
var _character_coordinator
var _input_controller
var _stats_window_coordinator
var _task_reminder_coordinator
var _task_reminder_presentation
var _bubble_token := 0
var _shutting_down := false
var _idle_count := 0
var _idle_behavior_timer: Timer
var _last_user_activity_ms := 0
var _known_unlocked_actions: Dictionary = {}
var _unlock_tracking_ready := false
var _last_state_message := "尚無紀錄"
var _pet_interaction_polygon := PackedVector2Array()
var _status_indicator: StatusIndicator
var _tray_menu: PopupMenu
var _today_reminder_ids: Dictionary = {}
var _agent_controller: AgentIntegrationController
var _agent_settings_panel
# Tests swap in a recording subclass before the node enters the tree.
var agent_controller_script: Script = AgentIntegrationControllerScript
var _update_check_coordinator
var _reminders_tab_view
var _status_tab
var _settings_tab
var _character_tab
var _agent_notification_active := false
var _active_agent_target_app := AgentIntegrationControllerScript.TARGET_VSCODE
var _active_agent := "codex"


func _ready() -> void:
	_window_service = DesktopWindowServiceScript.new()
	_gameplay_coordinator = PetGameplayCoordinatorScript.new()
	_gameplay_coordinator.configure(self, state, pet, _window_service)
	_character_coordinator = CharacterPackCoordinatorScript.new()
	_character_coordinator.configure(state, pet)
	_input_controller = PetInputControllerScript.new()
	_input_controller.configure(
		self,
		state,
		pet,
		_window_service,
		Callable(self, "_is_interactive_overlay_at"),
		Callable(self, "_is_agent_notification_active"),
		Callable(self, "_interrupt_autonomous_action")
	)
	_input_controller.user_activity.connect(_on_user_activity)
	_input_controller.single_click_requested.connect(_single_click_reaction)
	_input_controller.care_double_click_requested.connect(
		func() -> void: _run_care_action(3)
	)
	_input_controller.context_menu_requested.connect(_show_context_menu)
	_input_controller.agent_focus_requested.connect(_focus_agent_interface)
	_input_controller.interaction_region_refresh_requested.connect(
		_refresh_interaction_polygon
	)
	get_tree().auto_accept_quit = false
	# PetVisual is ready before this parent node. Keep its first loaded frame
	# hidden until the native transparent window has been positioned and shaped.
	pet.visible = false
	state.configure_profile(pet.get_character_id())
	_task_reminder_coordinator = TaskReminderCoordinatorScript.new()
	_task_reminder_coordinator.initialize()
	_task_reminder_presentation = TaskReminderPresentationCoordinatorScript.new()
	_task_reminder_presentation.configure(_task_reminder_coordinator)
	_task_reminder_coordinator.reminders_changed.connect(_on_reminders_changed)
	_task_reminder_coordinator.reminders_due.connect(_on_reminders_due)
	task_reminder_badge.pressed.connect(_open_task_reminders_from_badge)
	task_reminder_badge.visibility_changed.connect(_refresh_interaction_polygon)
	task_reminder_badge.resized.connect(_on_task_reminder_badge_resized)
	_status_tab = StatusTabPresenterScript.new()
	_status_tab.configure(
		state, pet, Callable(self, "_interaction_label"), Callable(self, "_interaction_icon")
	)
	_status_tab.care_action_requested.connect(_run_care_action)
	_status_tab.dialogue_requested.connect(_say_dialogue)
	_settings_tab = SettingsTabControllerScript.new()
	_settings_tab.configure(state, pet, _gameplay_coordinator)
	_settings_tab.theme_changed.connect(_on_details_theme_changed)
	_settings_tab.load_runtime_settings()
	_character_tab = CharacterTabControllerScript.new()
	_character_tab.configure(
		_character_coordinator, pet, state, Callable(self, "_apply_character_without_restart")
	)
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	_style_bubble()
	_connect_signals()
	_refresh_ui(state.get_snapshot())
	_setup_context_menu()
	_setup_status_indicator()
	_setup_agent_integration()
	_setup_update_check()
	_setup_autostart_service()
	_setup_idle_behavior()
	var display_recovery_controller: Node = DisplayRecoveryControllerScript.new()
	display_recovery_controller.name = "DisplayRecoveryController"
	add_child(display_recovery_controller)
	_last_user_activity_ms = Time.get_ticks_msec()
	call_deferred("_finish_window_setup")


func _process(_delta: float) -> void:
	if _task_reminder_coordinator != null:
		_task_reminder_coordinator.process(_delta)
	if _agent_controller != null:
		_agent_controller.poll()
	_restore_from_system_minimize()
	_input_controller.process()


func _on_user_activity(timestamp: int) -> void:
	_last_user_activity_ms = timestamp
	_gameplay_coordinator.cancel_autonomous_action()


func _is_agent_notification_active() -> bool:
	return _agent_notification_active


func _unhandled_input(event: InputEvent) -> void:
	_input_controller.handle_input(event)


func _on_stats_window_input(event: InputEvent) -> void:
	_input_controller.handle_secondary_window_input(event)


func _can_begin_drag() -> bool:
	return _gameplay_coordinator.can_begin_drag()


func _interrupt_autonomous_action() -> bool:
	if state.is_action_busy():
		return false
	return _gameplay_coordinator.cancel_autonomous_action()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("_request_shutdown")


func _exit_tree() -> void:
	if _agent_controller != null:
		_agent_controller.shutdown()


func say(text: String, seconds := 6.0, agent_priority := false) -> void:
	if not agent_priority and _agent_notification_active:
		return
	_bubble_token += 1
	var token := _bubble_token
	_style_bubble(agent_priority)
	# Container layout and the native Windows hit-test region are both applied
	# asynchronously. Keep the bubble hidden until one layout frame has passed
	# so the compositor never displays the temporary polygon-shaped state.
	bubble.visible = false
	bubble_tail.visible = false
	_refresh_interaction_polygon()
	# Exported builds cannot wrap Chinese without break hints; see CjkLineBreaks.
	bubble_label.text = CjkLineBreaksScript.insert_break_opportunities(text)
	bubble_label.add_theme_font_size_override(
		"font_size", 20 if text in ["🥕", "💧", "💤", "🪙", "✋"] else 13
	)
	_layout_speech_bubble(text)
	await get_tree().process_frame
	if token != _bubble_token:
		return
	_layout_speech_bubble(text)
	bubble.visible = true
	bubble_tail.visible = not agent_priority
	_refresh_interaction_polygon()
	await get_tree().create_timer(seconds).timeout
	if token == _bubble_token:
		bubble.visible = false
		bubble_tail.visible = false
		_refresh_interaction_polygon()
		if agent_priority:
			_agent_notification_active = false
			_say_deferred_due_reminders()


func _restore_from_system_minimize() -> void:
	# This borderless desktop pet has no user-facing minimize command. Check on
	# every rendered frame so short Show Desktop minimize transitions are not
	# missed between slower timer ticks.
	_window_service.restore_if_minimized()

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
	# With the native extension, rendering remains a whole transparent rectangle
	# and mouse input alone is toggled as the pointer enters or leaves the pet.
	# Without it, the polygon fallback clips rendering to the hit region.
	# Native mode also sizes the window once for every action, before the pet
	# is shown, because runtime resizes can flash a blank frame.
	if _window_service.enable_native_click_through():
		pet.fixed_window_resizing.connect(_hide_window_while_resizing)
		pet.use_fixed_window(true)
	_place_bottom_right()
	_apply_interaction_polygon(pet.get_interaction_polygon())
	# Give Windows one compositor frame to apply the final position and native
	# transparency, then reveal the already-loaded sprite in one complete frame.
	await get_tree().process_frame
	pet.visible = true
	_show_startup_message()
	_refresh_task_reminder_badge(true)


func _hide_window_while_resizing() -> void:
	# A resized window shows one blank frame before Godot presents at the new
	# size. Keep the whole window invisible until a few frames have rendered.
	_window_reveal_token += 1
	var token := _window_reveal_token
	_window_service.set_window_opacity(0)
	for _i in WINDOW_REVEAL_FRAMES:
		await get_tree().process_frame
	if token == _window_reveal_token:
		_window_service.set_window_opacity(255)


func _is_pet_interactive_at(local_point: Vector2) -> bool:
	if _is_interactive_overlay_at(local_point):
		return true
	return pet.contains_point(local_point)


func _is_interactive_overlay_at(local_point: Vector2) -> bool:
	if task_reminder_badge.visible \
			and task_reminder_badge.get_global_rect().has_point(local_point):
		return true
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
	_position_task_reminder_badge()
	_refresh_interaction_polygon()


func _refresh_interaction_polygon() -> void:
	var overlay_points := PackedVector2Array()
	if bubble.visible:
		var bubble_rect := bubble.get_global_rect()
		overlay_points.append_array(PackedVector2Array([
			bubble_rect.position,
			Vector2(bubble_rect.end.x, bubble_rect.position.y),
			bubble_rect.end,
			Vector2(bubble_rect.position.x, bubble_rect.end.y),
		]))
	if bubble_tail.visible:
		for point: Vector2 in bubble_tail.polygon:
			overlay_points.append(bubble_tail.to_global(point))
	if task_reminder_badge.visible:
		var badge_rect := task_reminder_badge.get_global_rect()
		overlay_points.append_array(PackedVector2Array([
			badge_rect.position,
			Vector2(badge_rect.end.x, badge_rect.position.y),
			badge_rect.end,
			Vector2(badge_rect.position.x, badge_rect.end.y),
		]))
	_window_service.apply_interaction_polygon(
		get_window(),
		_pet_interaction_polygon,
		overlay_points
	)


func _connect_signals() -> void:
	state.changed.connect(_refresh_ui)
	state.message_requested.connect(_show_state_message)
	state.action_requested.connect(_on_action_requested)
	state.action_requested.connect(pet.play_action)
	pet.action_completed.connect(state.receive_action_completed)
	state.sleep_started.connect(pet.start_sleep_loop)
	state.sleep_started.connect(pet.start_sleep_effect)
	state.sleep_ended.connect(pet.stop_sleep_loop)
	state.sleep_ended.connect(pet.stop_sleep_effect)
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


func _on_action_requested(action: String, _request_id: int) -> void:
	pet.play_effect_for_action(action)


func _setup_agent_integration() -> void:
	_agent_controller = agent_controller_script.new()
	_agent_controller.notification_received.connect(_handle_agent_notification)
	_agent_settings_panel = AgentSettingsPanelControllerScript.new()
	_agent_settings_panel.configure(_agent_controller)
	_agent_settings_panel.speech_requested.connect(
		func(text: String, seconds: float) -> void: say(text, seconds)
	)
	_agent_settings_panel.agent_status_requested.connect(_enqueue_agent_status)
	_agent_controller.load_settings()


func _setup_update_check() -> void:
	_update_check_coordinator = UpdateCheckCoordinatorScript.new()
	_update_check_coordinator.name = "UpdateCheckCoordinator"
	_settings_tab.set_update_check(_update_check_coordinator)
	_update_check_coordinator.update_found.connect(_on_update_found)
	add_child(_update_check_coordinator)


func _on_update_found(version: String) -> void:
	say("有新版本 v%s，可以到詳細面板的「設定」頁前往下載。" % version, 8.0)


func _setup_autostart_service() -> void:
	_autostart_service = WindowsAutostartServiceScript.new()
	_settings_tab.set_autostart_service(_autostart_service)


func _handle_agent_notification(
	message: String, reaction_action: String, target_app: String, agent: String
) -> void:
	_enqueue_agent_status(message, reaction_action, target_app, agent)


func _enqueue_agent_status(
	message: String,
	reaction_action: String,
	target_app := AgentIntegrationControllerScript.TARGET_VSCODE,
	agent := "codex"
) -> void:
	_agent_notification_active = true
	_active_agent_target_app = target_app
	_active_agent = agent
	_last_state_message = message
	_status_tab.set_last_message(message)
	var target_is_foreground := (
		_agent_controller != null
		and _agent_controller.is_target_foreground(target_app)
	)
	say(message, _agent_notification_duration(target_is_foreground), true)
	if not state.is_sleeping() and not state.is_action_busy():
		pet.play_action(_resolve_reaction_action(reaction_action))


## Codex pets have dedicated reaction rows; other character packs keep the
## original pet / idle reactions.
func _resolve_reaction_action(reaction_action: String) -> String:
	if pet.has_action(reaction_action):
		return reaction_action
	match reaction_action:
		AgentIntegrationControllerScript.REACTION_DONE:
			return "pet"
		AgentIntegrationControllerScript.REACTION_WAITING, \
				AgentIntegrationControllerScript.REACTION_ERROR:
			return "idle"
	return reaction_action


func _agent_notification_duration(vscode_is_foreground: bool) -> float:
	return (
		AGENT_FOREGROUND_NOTIFICATION_DURATION_SECONDS
		if vscode_is_foreground
		else AGENT_NOTIFICATION_DURATION_SECONDS
	)


func _focus_agent_interface() -> void:
	if _agent_controller != null and _agent_controller.focus_target(
			_active_agent_target_app, _active_agent
	):
		_dismiss_active_agent_notification()


func _dismiss_active_agent_notification() -> void:
	if not _agent_notification_active:
		return
	_bubble_token += 1
	bubble.visible = false
	bubble_tail.visible = false
	_agent_notification_active = false
	_refresh_interaction_polygon()
	_say_deferred_due_reminders()


func _show_state_message(key: String, fallback: String) -> void:
	var newline_at := fallback.find("\n")
	var base_text := fallback if newline_at < 0 else fallback.left(newline_at)
	var suffix := "" if newline_at < 0 else fallback.substr(newline_at)
	var text: String = pet.get_dialogue(key, base_text) + suffix
	_last_state_message = text.replace("\n", "　")
	_status_tab.set_last_message(_last_state_message)
	say(text, 6.0)


func _on_reminders_changed() -> void:
	_refresh_reminder_menus()
	_refresh_task_reminder_badge()


func _on_reminders_due(reminders: Array[Dictionary]) -> void:
	_refresh_task_reminder_badge(true)
	if _task_reminder_presentation == null:
		return
	# An Agent notification owns the bubble; say these once it closes.
	if _agent_notification_active:
		_task_reminder_presentation.defer_due(reminders)
		return
	_say_due_reminders(reminders)


func _say_deferred_due_reminders() -> void:
	if _task_reminder_presentation != null and not _agent_notification_active:
		_say_due_reminders(_task_reminder_presentation.take_deferred_due())


func _say_due_reminders(reminders: Array[Dictionary]) -> void:
	var message: String = _task_reminder_presentation.due_message(reminders)
	if not message.is_empty():
		say(message, TASK_REMINDER_NOTIFICATION_DURATION_SECONDS)


func _refresh_task_reminder_badge(pulse_overdue := false) -> void:
	if _task_reminder_presentation == null:
		task_reminder_badge.clear()
		_refresh_interaction_polygon()
		return
	task_reminder_badge.present(
		_task_reminder_presentation.badge_state(), pulse_overdue
	)
	_position_task_reminder_badge()
	_refresh_interaction_polygon()


func _position_task_reminder_badge() -> void:
	if not task_reminder_badge.visible:
		return
	if _task_reminder_presentation == null:
		return
	# badge_position works in window coordinates; the badge is a child of this
	# canvas, which is offset inside a window sized for every action.
	task_reminder_badge.position = _task_reminder_presentation.badge_position(
		pet.get_visual_bounds_in_canvas(),
		get_viewport_rect().size,
		task_reminder_badge.size
	) - position


func _open_task_reminders_from_badge() -> void:
	call_deferred("_show_stats_window", REMINDERS_TAB_INDEX)


func _on_task_reminder_badge_resized() -> void:
	_position_task_reminder_badge()
	_refresh_interaction_polygon()


func _show_startup_message() -> void:
	if _task_reminder_presentation != null:
		var today_notice: String = _task_reminder_presentation.startup_message()
		if not today_notice.is_empty():
			say(today_notice, STARTUP_REMINDER_DURATION_SECONDS)
			return
	_say_dialogue(
		"startup", "右鍵操作・雙擊摸摸", STARTUP_DIALOGUE_DURATION_SECONDS
	)


func _say_dialogue(key: String, fallback: String, seconds: float) -> void:
	say(pet.get_dialogue(key, fallback), seconds)


func _say_configured_dialogue(key: String, seconds: float) -> void:
	var text: String = pet.get_dialogue(key, "")
	if text.strip_edges().is_empty():
		return
	say(text, seconds)


func _show_wish_notice(action: String) -> void:
	say(_wish_icon(action), 6.0)


func _setup_context_menu() -> void:
	context_menu.id_pressed.connect(_on_context_action)
	_rebuild_action_menu(context_menu)


func _show_context_menu(at: Vector2i) -> void:
	context_menu.position = _window_service.window_position() + at
	context_menu.popup()


func _setup_status_indicator() -> void:
	if not _window_service.has_status_indicator():
		return
	_tray_menu = PopupMenu.new()
	_rebuild_action_menu(_tray_menu)
	_tray_menu.id_pressed.connect(_on_context_action)
	add_child(_tray_menu)
	_status_indicator = StatusIndicator.new()
	_status_indicator.icon = STATUS_ICON
	_status_indicator.tooltip = "Open Desktop Pet"
	add_child(_status_indicator)
	_status_indicator.menu = _status_indicator.get_path_to(_tray_menu)
	_status_indicator.pressed.connect(_on_status_indicator_pressed)


func _on_status_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		call_deferred("_show_stats_window")


func _remove_status_indicator() -> void:
	if is_instance_valid(_status_indicator):
		_status_indicator.queue_free()
	_status_indicator = null
	if is_instance_valid(_tray_menu):
		_tray_menu.queue_free()
		_tray_menu = null


func _on_context_action(id: int) -> void:
	match id:
		1, 2, 3, 4, 5:
			_run_care_action(id)
		6:
			call_deferred("_show_stats_window")
		PetMenuBuilderScript.REMINDER_VIEW_ALL_ITEM_ID:
			call_deferred("_show_stats_window", REMINDERS_TAB_INDEX)
		7:
			# Let the native PopupMenu finish dispatching `id_pressed` before
			# destroying either native window.
			call_deferred("_request_shutdown")
		22:
			_recover_pet()
		_:
			if id < PetMenuBuilderScript.REMINDER_ITEM_ID_BASE:
				return
			var reminder_id: String = String(_today_reminder_ids.get(id, ""))
			if not reminder_id.is_empty():
				call_deferred(
					"_show_stats_window", REMINDERS_TAB_INDEX, reminder_id
				)


func _rebuild_action_menu(menu: PopupMenu) -> void:
	if not is_instance_valid(menu):
		return
	menu.clear()
	PetMenuBuilderScript.populate(
		menu,
		Callable(self, "_interaction_icon"),
		Callable(self, "_interaction_label"),
		Callable(state, "care_cost_text")
	)
	var reminders: Array[Dictionary] = []
	if _task_reminder_coordinator != null:
		reminders = _task_reminder_coordinator.get_open_today_reminders()
	PetMenuBuilderScript.populate_today_reminders(menu, reminders)
	PetMenuBuilderScript.append_exit(menu)
	_set_action_menu_level(menu)
	for index: int in mini(reminders.size(), 4):
		_today_reminder_ids[PetMenuBuilderScript.REMINDER_ITEM_ID_BASE + index] = (
			String(reminders[index].get("id", ""))
		)


func _refresh_reminder_menus() -> void:
	_today_reminder_ids.clear()
	_rebuild_action_menu(context_menu)
	if is_instance_valid(_tray_menu):
		_rebuild_action_menu(_tray_menu)


func _set_action_menu_level(menu: PopupMenu) -> void:
	if not is_instance_valid(menu) or menu.item_count == 0:
		return
	var snapshot: Dictionary = state.get_snapshot()
	menu.set_item_text(0, "Lv.%d  ·  %d 金幣  ·  XP %d/%d" % [
		snapshot.level, snapshot.coins, snapshot.xp, snapshot.level * 20
	])


func _single_click_reaction() -> void:
	if state.wake_sleep("click"):
		_last_user_activity_ms = Time.get_ticks_msec()
		return
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
	timer.name = "IdleBehaviorTimer"
	timer.wait_time = randf_range(10.0, 16.0)
	timer.one_shot = true
	timer.timeout.connect(func() -> void:
		_idle_count += 1
		if _can_act_autonomously():
			_run_autonomous_action()
			if _idle_count % 3 == 0:
				_say_configured_dialogue("idle", 2.5)
		timer.wait_time = randf_range(11.0, 19.0)
		timer.start()
	)
	add_child(timer)
	_idle_behavior_timer = timer
	timer.start()


func _can_act_autonomously(require_mouse_idle := false) -> bool:
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	return (not require_mouse_idle or mouse_is_idle) \
		and not _settings_tab.focus_mode \
		and not context_menu.visible \
		and not _is_stats_window_open() \
		and not _input_controller.is_dragging() \
		and not state.is_sleeping() \
		and _gameplay_coordinator.can_start_action()


func _run_autonomous_action() -> void:
	if _settings_tab.focus_mode:
		return
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	_gameplay_coordinator.run_autonomous_action(mouse_is_idle)


func _autonomous_small_roll() -> void:
	_gameplay_coordinator.start_autonomous_move(_can_act_autonomously(true))


func _build_stats_window() -> void:
	_stats_window_coordinator = StatsWindowCoordinatorScript.new()
	_stats_window_coordinator.theme_mode = _settings_tab.theme_mode
	_stats_window_coordinator.reminder_coordinator = _task_reminder_coordinator
	_stats_window_coordinator.last_state_message = _last_state_message
	_stats_window_coordinator.agent_settings = (
		_agent_controller.get_settings_snapshot() if _agent_controller != null else {}
	)
	_stats_window_coordinator.autostart_supported = _settings_tab.is_autostart_supported()
	_stats_window_coordinator.keep_screen_on = _settings_tab.keep_screen_on
	_stats_window_coordinator.focus_mode = _settings_tab.focus_mode
	_stats_window_coordinator.visual_scale = float(
		state.get_snapshot().get("visual_scale", PetVisualScaleScript.DEFAULT_VALUE)
	)
	_stats_window_coordinator.interaction_label = Callable(self, "_interaction_label")
	_stats_window_coordinator.interaction_icon = Callable(self, "_interaction_icon")
	var refs: Dictionary = _stats_window_coordinator.build(self)
	_stats_window = refs["window"] as Window
	_stats_tabs = refs["tabs"] as TabContainer
	_stats_tab_buttons = refs["tab_buttons"] as Array[Button]
	_reminders_tab_view = refs["reminders_tab"]
	_stats_window_coordinator.close_requested.connect(_destroy_stats_window)
	_stats_window_coordinator.window_input.connect(_on_stats_window_input)
	_stats_window_coordinator.tab_selected.connect(_select_stats_tab)
	_stats_window_coordinator.tab_changed.connect(_on_stats_tab_changed)
	_status_tab.bind(refs["status_tab"], refs["status_refs"])
	_settings_tab.bind(refs["settings_tab"], refs["settings_refs"])
	_agent_settings_panel.bind(
		refs["agent_tab"], refs["agent_refs"], _settings_tab.theme_mode
	)
	_settings_tab.query_autostart()
	_character_tab.bind(refs["character_tab"], refs["character_refs"])
	_select_stats_tab(0)


func _on_stats_tab_changed(tab_index: int) -> void:
	_stats_window_coordinator.refresh_tab_buttons(tab_index)
	_character_tab.on_tab_changed(tab_index)
	if tab_index == AGENT_TAB_INDEX and _agent_controller != null:
		_agent_controller.refresh_enabled_executable_paths_if_invalid()


func _select_stats_tab(tab_index: int) -> void:
	if not is_instance_valid(_stats_tabs):
		return
	_stats_tabs.current_tab = clampi(tab_index, 0, _stats_tabs.get_tab_count() - 1)
	_stats_window_coordinator.refresh_tab_buttons(_stats_tabs.current_tab)


func _apply_character_without_restart(character_id: String, is_reload: bool) -> bool:
	var switch_result: Dictionary = _character_coordinator.switch_character(character_id)
	if not bool(switch_result.get("ok", false)):
		_character_tab.set_feedback("角色載入失敗，已恢復原本角色。")
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
	call_deferred("_reposition_after_character_switch", character_id)
	_character_tab.refresh_list(
		"已重新載入「%s」。" % pet.get_character_name()
		if is_reload
		else "已切換為「%s」。" % pet.get_character_name()
	)
	return true


func _reposition_after_character_switch(expected_character_id: String) -> void:
	# Character frames can resize the native transparent window. Wait until that
	# geometry is committed, then place the newly loaded character independently
	# of the previous character's sprite bounds and offsets.
	await get_tree().process_frame
	if pet.get_character_id() != expected_character_id:
		return
	_place_bottom_right()


func _refresh_json_driven_ui() -> void:
	_apply_care_menu_labels()
	_status_tab.refresh_care_labels()
	_bubble_token += 1
	bubble.visible = false
	bubble_tail.visible = false
	_last_state_message = pet.get_dialogue(
		"startup", "右鍵操作・雙擊摸摸"
	)
	_status_tab.set_last_message(_last_state_message)


func _run_care_action(id: int) -> void:
	_character_tab.cancel_mask_editing()
	var result: String = _gameplay_coordinator.request_care_action(id)
	if result == "woke":
		_last_user_activity_ms = Time.get_ticks_msec()
		return
	if result == "busy":
		_say_dialogue("action_busy", "先等目前的動作完成～", 1.5)


func _show_stats_window(
	select_tab := -1, reminder_id := "", create_reminder := false
) -> void:
	if is_instance_valid(_stats_window):
		_refresh_ui(state.get_snapshot())
		if select_tab >= 0:
			_select_stats_tab(select_tab)
		if not reminder_id.is_empty() and _reminders_tab_view != null:
			_reminders_tab_view.focus_reminder(reminder_id)
		elif create_reminder and _reminders_tab_view != null:
			_reminders_tab_view.start_new_reminder()
		call_deferred("_bring_stats_window_forward")
		return
	_build_stats_window()
	_refresh_ui(state.get_snapshot())
	# Place beside the pet's base canvas rather than the native window, which
	# may be larger and offset so it never resizes during actions.
	var pet_position: Vector2i = _window_service.window_position() + Vector2i(position.round())
	var pet_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	var screen: int = _window_service.current_screen()
	var usable: Rect2i = _window_service.usable_rect(screen)
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
	if select_tab >= 0:
		_select_stats_tab(select_tab)
	if not reminder_id.is_empty() and _reminders_tab_view != null:
		_reminders_tab_view.focus_reminder(reminder_id)
	elif create_reminder and _reminders_tab_view != null:
		_reminders_tab_view.start_new_reminder()
	call_deferred("_bring_stats_window_forward")


func _bring_stats_window_forward() -> void:
	if not is_instance_valid(_stats_window):
		return
	if _stats_window.mode == Window.MODE_MINIMIZED:
		_stats_window.mode = Window.MODE_WINDOWED
	if not _stats_window.visible:
		_stats_window.show()
	_stats_window.grab_focus()
	_window_service.bring_to_front(_stats_window.get_window_id())


func _is_stats_window_open() -> bool:
	return is_instance_valid(_stats_window) and _stats_window.visible


func _destroy_stats_window() -> void:
	_save_stats_window_size()
	_character_tab.cancel_mask_editing()
	if _stats_window_coordinator != null:
		_stats_window_coordinator.destroy()
		_stats_window_coordinator = null
	_reminders_tab_view = null
	_agent_settings_panel.unbind()
	_status_tab.unbind()
	_settings_tab.unbind()
	_character_tab.unbind()
	_stats_window = null
	_stats_tabs = null
	_stats_tab_buttons.clear()


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


func _on_details_theme_changed() -> void:
	if not is_instance_valid(_stats_window):
		return
	var previous_position := _stats_window.position
	var previous_size := _stats_window.size
	_destroy_stats_window()
	call_deferred(
		"_rebuild_stats_window_after_theme_change",
		previous_position,
		previous_size
	)


func _rebuild_stats_window_after_theme_change(
	previous_position: Vector2i,
	previous_size: Vector2i
) -> void:
	_build_stats_window()
	_stats_window.position = previous_position
	_stats_window.size = previous_size
	_select_stats_tab(2)
	_stats_window.show()
	_refresh_ui(state.get_snapshot())
	call_deferred("_bring_stats_window_forward")


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
	_input_controller.cancel()
	context_menu.hide()
	_bubble_token += 1
	bubble.visible = false
	bubble_tail.visible = false
	_save_stats_window_size()
	state.save_state()
	if _autostart_service != null:
		_autostart_service.shutdown()
	if _agent_controller != null:
		_agent_controller.shutdown()
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
	var current_visual_scale := float(snapshot.get(
		"visual_scale", PetVisualScaleScript.DEFAULT_VALUE
	))
	pet.set_visual_size(current_visual_scale)
	_settings_tab.refresh_visual_scale(current_visual_scale)
	_update_unlock_tracking()
	var level_text := "Lv.%d  ·  %d 金幣  ·  XP %d/%d" % [
		snapshot.level, snapshot.coins, snapshot.xp, snapshot.level * 20
	]
	_status_tab.refresh(snapshot, level_text)
	if context_menu.item_count > 0:
		context_menu.set_item_text(0, level_text)
	if is_instance_valid(_tray_menu) and _tray_menu.item_count > 0:
		_tray_menu.set_item_text(0, level_text)
	# Prices switch to the free emergency ration when the pet would be stuck.
	_apply_care_menu_labels()


func _apply_care_menu_labels() -> void:
	for menu: PopupMenu in [context_menu, _tray_menu]:
		PetMenuBuilderScript.apply_care_labels(
			menu,
			Callable(self, "_interaction_icon"),
			Callable(self, "_interaction_label"),
			Callable(state, "care_cost_text")
		)


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
	if not _settings_tab.focus_mode and not pet.is_busy() and not state.is_action_busy():
		pet.play_action(action)


func _place_bottom_right() -> void:
	var usable: Rect2i = _window_service.usable_rect()
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	_window_service.set_window_position(Vector2i(
		usable.end.x - ceili(visual_bounds.end.x) - 24,
		usable.end.y - ceili(visual_bounds.end.y)
	))


func _recover_pet() -> void:
	_input_controller.cancel()
	_gameplay_coordinator.cancel_autonomous_action()
	_window_service.restore_if_minimized()
	_window_service.set_always_on_top(true)
	var screen: int = _window_service.current_screen()
	var usable: Rect2i = _window_service.usable_rect(screen)
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	_window_service.set_window_position(Vector2i(
		usable.end.x - ceili(visual_bounds.end.x) - 24,
		usable.end.y - ceili(visual_bounds.end.y)
	))


func _clamp_window_position(requested: Vector2i) -> Vector2i:
	var visual_bounds: Rect2 = pet.get_visual_bounds_in_canvas()
	return _window_service.clamp_window_position(
		requested,
		_window_service.window_size(),
		visual_bounds
	)


func _style_bubble(agent_notification := false) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.886, 0.957, 0.973, 0.92)
		if agent_notification
		else Color(0.953, 0.988, 0.996, 0.82)
	)
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
