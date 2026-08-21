extends Node2D

const CharacterPackCoordinatorScript = preload("res://scripts/character_pack_coordinator.gd")
const AgentIntegrationControllerScript = preload("res://scripts/agent_integration_controller.gd")
const CodexHookTrustService = preload("res://scripts/codex_hook_trust_service.gd")
const DesktopWindowServiceScript = preload("res://scripts/desktop_window_service.gd")
const PetGameplayCoordinatorScript = preload("res://scripts/pet_gameplay_coordinator.gd")
const PetInputControllerScript = preload("res://scripts/pet_input_controller.gd")
const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const PetVisualScaleScript = preload("res://scripts/pet_visual_scale.gd")
const StatsWindowCoordinatorScript = preload("res://scripts/stats_window_coordinator.gd")
const TaskReminderCoordinatorScript = preload("res://scripts/task_reminder_coordinator.gd")
const TaskReminderPresentationCoordinatorScript = preload(
	"res://scripts/task_reminder_presentation_coordinator.gd"
)
const WindowsAutostartServiceScript = preload("res://scripts/windows_autostart_service.gd")
const CharacterEffectPreferencesScript = preload(
	"res://scripts/character_effect_preferences.gd"
)
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_STATS_SIZE := StatsWindowCoordinatorScript.DEFAULT_WINDOW_SIZE
const MIN_STATS_SIZE := StatsWindowCoordinatorScript.MIN_WINDOW_SIZE
const DEFAULT_TARGET_FPS := 30
const TARGET_FPS_OPTIONS := [15, 30, 60]
const DEFAULT_KEEP_SCREEN_ON := false
const DEFAULT_FOCUS_MODE := false
const AGENT_NOTIFICATION_DURATION_SECONDS := 60.0
const AGENT_FOREGROUND_NOTIFICATION_DURATION_SECONDS := 3.0
const STARTUP_DIALOGUE_DURATION_SECONDS := 5.0
const STARTUP_REMINDER_DURATION_SECONDS := 8.0
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
var _stats_status: Label
var _companion_status: Label
var _wish_status: Label
var _unlock_status: Label
var _last_message_status: Label
var _fps_option_button: OptionButton
var _details_theme_option_button: OptionButton
var _visual_scale_slider: HSlider
var _visual_scale_value_label: Label
var _focus_mode_check_box: CheckBox
var _keep_screen_on_check_box: CheckBox
var _autostart_check_box: CheckBox
var _settings_feedback: Label
var _agent_codex_enabled_toggle: Button
var _agent_codex_app_enabled_toggle: Button
var _agent_terminal_codex_enabled_toggle: Button
var _agent_terminal_opencode_enabled_toggle: Button
var _agent_vscode_opencode_enabled_toggle: Button
var _agent_opencode_app_enabled_toggle: Button
var _agent_copilot_enabled_toggle: Button
var _agent_claude_vscode_enabled_toggle: Button
var _agent_claude_app_enabled_toggle: Button
var _agent_claude_terminal_enabled_toggle: Button
var _agent_gemini_terminal_enabled_toggle: Button
var _agent_agy_terminal_enabled_toggle: Button
var _agent_port_spin_box: SpinBox
var _agent_status_label: Label
var _codex_setup_progress_bar: ProgressBar
var _codex_trust_review_button: Button
var _codex_trust_recheck_button: Button
var _codex_trust_dialog: ConfirmationDialog
var _vscode_executable_line_edit: LineEdit
var _vscode_executable_hint: Label
var _vscode_executable_summary: Label
var _codex_app_executable_line_edit: LineEdit
var _codex_app_executable_hint: Label
var _codex_app_executable_summary: Label
var _terminal_executable_line_edit: LineEdit
var _terminal_executable_hint: Label
var _terminal_executable_summary: Label
var _opencode_app_executable_line_edit: LineEdit
var _opencode_app_executable_hint: Label
var _opencode_app_executable_summary: Label
var _claude_app_executable_line_edit: LineEdit
var _claude_app_executable_hint: Label
var _claude_app_executable_summary: Label
var _character_list: ItemList
var _character_feedback: Label
var _character_use_button: Button
var _character_delete_button: Button
var _mask_effect_panel: Control
var _mask_effect_hint: Control
var _mask_effect_values: Control
var _mask_effect_x_spin: SpinBox
var _mask_effect_y_spin: SpinBox
var _mask_effect_scale_spin: SpinBox
var _mask_effect_header_state: Label
var _mask_effect_header_chevron: Label
var _mask_effect_apply_button: Button
var _mask_effect_reset_button: Button
var _mask_effect_feedback_dialog: AcceptDialog
var _mask_effect_editing := false
var _pending_mask_anchor := Vector2.ZERO
var _pending_mask_scale := 0.38
var _character_tab_index := -1
var _character_tab_loaded := false
var _character_entries: Array[Dictionary] = []
var _character_import_dialog: FileDialog
var _character_update_dialog: ConfirmationDialog
var _character_delete_dialog: ConfirmationDialog
var _pending_character_archive := ""
var _stats_bars: Dictionary = {}
var _care_action_buttons: Dictionary = {}
var _autostart_service
var _window_service
var _gameplay_coordinator
var _character_coordinator
var _input_controller
var _stats_window_coordinator
var _task_reminder_coordinator
var _task_reminder_presentation
var _bubble_token := 0
var _shutting_down := false
var _idle_count := 0
var _last_user_activity_ms := 0
var _known_unlocked_actions: Dictionary = {}
var _unlock_tracking_ready := false
var _last_state_message := "尚無紀錄"
var _pet_interaction_polygon := PackedVector2Array()
var _status_indicator: StatusIndicator
var _tray_menu: PopupMenu
var _today_reminder_ids: Dictionary = {}
var _details_theme_mode := "light"
var _keep_screen_on := DEFAULT_KEEP_SCREEN_ON
var _focus_mode := DEFAULT_FOCUS_MODE
var _agent_controller: AgentIntegrationController
var _details_window_controller
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
	_task_reminder_coordinator.reminder_due.connect(_on_reminder_due)
	task_reminder_badge.pressed.connect(_open_task_reminders_from_badge)
	task_reminder_badge.visibility_changed.connect(_refresh_interaction_polygon)
	task_reminder_badge.resized.connect(_on_task_reminder_badge_resized)
	_load_runtime_settings()
	get_viewport().transparent_bg = true
	get_viewport().gui_embed_subwindows = false
	_style_bubble()
	_connect_signals()
	_refresh_ui(state.get_snapshot())
	_setup_context_menu()
	_setup_status_indicator()
	_setup_agent_integration()
	_setup_autostart_service()
	_setup_idle_behavior()
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
	bubble_tail.visible = not agent_priority
	_refresh_interaction_polygon()
	await get_tree().create_timer(seconds).timeout
	if token == _bubble_token:
		bubble.visible = false
		bubble_tail.visible = false
		_refresh_interaction_polygon()
		if agent_priority:
			_agent_notification_active = false


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
	_place_bottom_right()
	# Rendering remains a normal transparent rectangle. Mouse input alone is
	# toggled as the pointer enters or leaves the pet, so speech is never clipped.
	_apply_interaction_polygon(pet.get_interaction_polygon())
	# Give Windows one compositor frame to apply the final position and native
	# transparency, then reveal the already-loaded sprite in one complete frame.
	await get_tree().process_frame
	pet.visible = true
	_show_startup_message()
	_refresh_task_reminder_badge(true)


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
	_agent_controller = AgentIntegrationControllerScript.new()
	_agent_controller.notification_received.connect(_handle_agent_notification)
	_agent_controller.configuration_failed.connect(_handle_agent_configuration_failed)
	_agent_controller.codex_unavailable.connect(_handle_codex_unavailable)
	_agent_controller.codex_trust_required.connect(_handle_codex_trust_required)
	_agent_controller.codex_trust_ready.connect(_handle_codex_trust_ready)
	_agent_controller.state_changed.connect(_refresh_agent_settings_ui)
	_agent_controller.executable_path_detection_started.connect(
		_on_executable_path_detection_started
	)
	_agent_controller.executable_path_detection_finished.connect(
		_on_executable_path_detection_finished
	)
	_agent_controller.load_settings()


func _handle_agent_configuration_failed(target_name: String) -> void:
	say("%s 通知設定失敗，已自動關閉開關。請確認相關檔案與權限後再試。" % target_name, 8.0)


func _handle_codex_unavailable(target_name: String, _message: String) -> void:
	say(
		"%s 通知無法開啟：找不到支援 Hook 審查的 Codex。請先安裝或更新 "
		+ "Codex Desktop、VS Code Codex 擴充功能或 Codex CLI。" % target_name,
		8.0
	)


func _handle_codex_trust_required(
	target_name: String, status: String, message: String
) -> void:
	_apply_agent_control_state()
	if not is_instance_valid(_codex_trust_dialog):
		say("%s 的 Codex Hook 尚待信任，請開啟 Hook 審查。" % target_name, 8.0)
		return
	var status_hint := "目前狀態：%s" % message
	if status == CodexHookTrustService.STATUS_UNAVAILABLE:
		status_hint += "\n這台電腦找不到可用的 Codex 執行核心，請先安裝或更新 Codex。"
	_codex_trust_dialog.dialog_text = (
		"你正在開啟「%s Codex」通知。三種 Codex 共用同一份 Stop Hook 信任。"
		+ "\n\n%s\n\n"
		+ "不需另外安裝 CLI；桌寵會使用 Codex Desktop、VS Code 擴充功能或"
		+ "獨立 CLI 所提供的 Codex 核心。\n\n"
		+ "1. 按「開啟 Codex 信任畫面」。\n"
		+ "2. 在 PowerShell 選 1. Review hooks，再按 Enter；這一步只會開啟 Hook 清單。\n"
		+ "3. 在 Hook 清單選取 Stop，再按 Enter 開啟詳細內容。\n"
		+ "4. 找到 Open Desktop Pet 的 Hook，將核取狀態切換為 [x]。"
		+ "[ ] 表示尚未信任；顯示 [x] 才算完成信任。\n"
		+ "5. 按 Esc 返回 Hook 清單；若仍在審查畫面，再按一次 Esc 離開。\n"
		+ "6. 回到桌寵，按「我已信任，檢查通知」。\n\n"
		+ "選 2 會信任所有待審 Hook；選 3 不會信任，通知也不會啟用。"
	) % [target_name, status_hint]
	_codex_trust_dialog.popup_centered(Vector2i(700, 540))


func _handle_codex_trust_ready(target_name: String, target_app: String) -> void:
	if is_instance_valid(_codex_trust_dialog):
		_codex_trust_dialog.hide()
	_apply_agent_control_state()
	_enqueue_agent_status(
		"%s 的 Codex 通知已完成信任並啟用。" % target_name,
		"idle",
		target_app,
		"codex"
	)


func _open_codex_hook_review() -> void:
	if _agent_controller == null or not _agent_controller.open_codex_hook_review():
		if is_instance_valid(_codex_trust_dialog):
			_codex_trust_dialog.dialog_text = (
				"無法開啟 Codex Hook 審查。請確認 Codex Desktop、VS Code 的 Codex "
				+ "擴充功能或 Codex CLI 已安裝並更新，再重新嘗試。"
			)
			call_deferred("_show_codex_trust_dialog")
		return
	_apply_agent_control_state()


func _recheck_codex_hook_trust() -> void:
	if _agent_controller == null:
		say("Codex 通知服務尚未就緒，請關閉並重新開啟桌寵。", 6.0)
		return
	if _agent_controller.is_codex_setup_busy():
		say("正在檢查 Codex Hook，完成前不需要再按一次。", 6.0)
		return
	if not _agent_controller.has_pending_codex_trust():
		say(
			"尚未選擇要啟用哪一種 Codex 通知。請在下方找到你使用的程式"
			+ "（VS Code、ChatGPT 或終端機），把它的 Codex 開關打開。",
			8.0
		)
		return
	if not _agent_controller.recheck_pending_codex_trust():
		say("無法開始檢查，請重新開啟桌寵後再試。", 6.0)
		return
	_apply_agent_control_state()


func _show_codex_trust_dialog() -> void:
	if is_instance_valid(_codex_trust_dialog):
		_codex_trust_dialog.popup_centered(Vector2i(580, 330))


func _cancel_codex_hook_trust() -> void:
	if _agent_controller != null:
		_agent_controller.cancel_pending_codex_enable()
	_apply_agent_control_state()


func _on_executable_path_detection_started(targets: Array) -> void:
	if _details_window_controller != null:
		_details_window_controller.set_agent_executable_path_detection_state(
			targets, true
		)


func _on_executable_path_detection_finished(targets: Array) -> void:
	if _details_window_controller != null:
		_details_window_controller.set_agent_executable_path_detection_state(
			targets, false
		)
	_refresh_agent_settings_ui()


func _setup_autostart_service() -> void:
	_autostart_service = WindowsAutostartServiceScript.new()
	_autostart_service.operation_completed.connect(_finish_autostart_operation)


func _refresh_agent_settings_ui() -> void:
	_apply_agent_control_state()
	if _details_window_controller != null and _agent_controller != null:
		_details_window_controller.refresh_executable_path_control(
			_agent_controller.executable_path,
			_vscode_executable_line_edit,
			_vscode_executable_hint,
			_vscode_executable_summary,
			"VS Code",
			true
		)
		_details_window_controller.refresh_executable_path_control(
			_agent_controller.codex_app_executable_path,
			_codex_app_executable_line_edit,
			_codex_app_executable_hint,
			_codex_app_executable_summary,
			"ChatGPT",
			true
		)
		_details_window_controller.refresh_executable_path_control(
			_agent_controller.terminal_executable_path,
			_terminal_executable_line_edit,
			_terminal_executable_hint,
			_terminal_executable_summary,
			"終端機",
			false
		)
		_details_window_controller.refresh_executable_path_control(
			_agent_controller.opencode_app_executable_path,
			_opencode_app_executable_line_edit,
			_opencode_app_executable_hint,
			_opencode_app_executable_summary,
			"OpenCode",
			false
		)
		_details_window_controller.refresh_executable_path_control(
			_agent_controller.claude_app_executable_path,
			_claude_app_executable_line_edit,
			_claude_app_executable_hint,
			_claude_app_executable_summary,
			"Claude",
			false
		)
	if not is_instance_valid(_agent_status_label):
		return
	var codex_trust_pending := (
		_agent_controller != null and _agent_controller.has_pending_codex_trust()
	)
	var codex_setup_busy := (
		_agent_controller != null and _agent_controller.is_codex_setup_busy()
	)
	if is_instance_valid(_codex_setup_progress_bar):
		_codex_setup_progress_bar.visible = codex_setup_busy
	if is_instance_valid(_codex_trust_review_button):
		_codex_trust_review_button.visible = codex_trust_pending
		_codex_trust_review_button.disabled = codex_setup_busy
	if is_instance_valid(_codex_trust_recheck_button):
		_codex_trust_recheck_button.visible = codex_trust_pending
		_codex_trust_recheck_button.disabled = codex_setup_busy
	if codex_setup_busy:
		_agent_status_label.text = "狀態: 正在檢查 Codex 與通知設定…"
		_agent_status_label.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)
		return
	if codex_trust_pending:
		_agent_status_label.text = (
			"尚未啟用：請先在 Codex 信任桌寵 Hook，再按「我已信任，檢查通知」"
		)
		_agent_status_label.add_theme_color_override(
			"font_color", _details_color("#a66b16", "#dcdcaa")
		)
		return
	if _agent_controller == null or not _agent_controller.is_any_enabled():
		_agent_status_label.text = "狀態: 已關閉"
		_agent_status_label.add_theme_color_override(
			"font_color", _details_color("#68747a", "#9da1a6")
		)
		return
	if _agent_controller.is_running():
		_agent_status_label.text = "狀態: 監聽中  127.0.0.1:%d" % _agent_controller.port
		_agent_status_label.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)
	else:
		_agent_status_label.text = "狀態: 無法監聽，通訊埠可能被占用"
		_agent_status_label.add_theme_color_override(
			"font_color", _details_color("#b44949", "#ff8c8c")
		)


func _apply_agent_control_state() -> void:
	var enabled := _agent_controller != null and _agent_controller.is_any_enabled()
	var codex_busy := (
		_agent_controller != null and _agent_controller.is_codex_setup_busy()
	)
	_update_agent_enabled_toggles()
	for toggle: Button in [
		_agent_codex_enabled_toggle,
		_agent_codex_app_enabled_toggle,
		_agent_terminal_codex_enabled_toggle,
	]:
		if is_instance_valid(toggle):
			toggle.disabled = codex_busy
	if is_instance_valid(_agent_port_spin_box):
		_agent_port_spin_box.editable = not enabled
		_agent_port_spin_box.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		)
		var port_line_edit := _agent_port_spin_box.get_line_edit()
		port_line_edit.editable = not enabled
		port_line_edit.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		)
		_agent_port_spin_box.modulate = (
			Color("#8c979b") if enabled else Color.WHITE
		)


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
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % message
	var target_is_foreground := (
		_agent_controller != null
		and _agent_controller.is_target_foreground(target_app)
	)
	say(message, _agent_notification_duration(target_is_foreground), true)
	if not state.is_sleeping() and not state.is_action_busy():
		pet.play_action(reaction_action)


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


func _show_state_message(key: String, fallback: String) -> void:
	var newline_at := fallback.find("\n")
	var base_text := fallback if newline_at < 0 else fallback.left(newline_at)
	var suffix := "" if newline_at < 0 else fallback.substr(newline_at)
	var text: String = pet.get_dialogue(key, base_text) + suffix
	_last_state_message = text.replace("\n", "　")
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % _last_state_message
	say(text, 6.0)


func _on_reminders_changed() -> void:
	_refresh_reminder_menus()
	_refresh_task_reminder_badge()


func _on_reminder_due(reminder: Dictionary) -> void:
	if reminder.is_empty():
		return
	_refresh_task_reminder_badge(true)


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
	task_reminder_badge.position = _task_reminder_presentation.badge_position(
		pet.get_visual_bounds_in_canvas(),
		get_viewport_rect().size,
		task_reminder_badge.size
	)


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
		Callable(self, "_interaction_label")
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
	timer.start()


func _can_act_autonomously(require_mouse_idle := false) -> bool:
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	return (not require_mouse_idle or mouse_is_idle) \
		and not _focus_mode \
		and not context_menu.visible \
		and not _is_stats_window_open() \
		and not _input_controller.is_dragging() \
		and not state.is_sleeping() \
		and _gameplay_coordinator.can_start_action()


func _run_autonomous_action() -> void:
	if _focus_mode:
		return
	var mouse_is_idle := Time.get_ticks_msec() - _last_user_activity_ms >= 4500
	_gameplay_coordinator.run_autonomous_action(mouse_is_idle)


func _autonomous_small_roll() -> void:
	_gameplay_coordinator.start_autonomous_move(_can_act_autonomously(true))


func _build_stats_window() -> void:
	_stats_bars.clear()
	_care_action_buttons.clear()
	_stats_window_coordinator = StatsWindowCoordinatorScript.new()
	_stats_window_coordinator.theme_mode = _details_theme_mode
	_stats_window_coordinator.reminder_coordinator = _task_reminder_coordinator
	_stats_window_coordinator.last_state_message = _last_state_message
	_stats_window_coordinator.codex_enabled = (
		_agent_controller != null and _agent_controller.codex_enabled
	)
	_stats_window_coordinator.codex_app_enabled = (
		_agent_controller != null and _agent_controller.codex_app_enabled
	)
	_stats_window_coordinator.terminal_codex_enabled = (
		_agent_controller != null and _agent_controller.terminal_codex_enabled
	)
	_stats_window_coordinator.terminal_opencode_enabled = (
		_agent_controller != null and _agent_controller.terminal_opencode_enabled
	)
	_stats_window_coordinator.vscode_opencode_enabled = (
		_agent_controller != null and _agent_controller.vscode_opencode_enabled
	)
	_stats_window_coordinator.opencode_app_enabled = (
		_agent_controller != null and _agent_controller.opencode_app_enabled
	)
	_stats_window_coordinator.copilot_enabled = (
		_agent_controller != null and _agent_controller.copilot_enabled
	)
	_stats_window_coordinator.claude_vscode_enabled = (
		_agent_controller != null and _agent_controller.claude_vscode_enabled
	)
	_stats_window_coordinator.claude_app_enabled = (
		_agent_controller != null and _agent_controller.claude_app_enabled
	)
	_stats_window_coordinator.claude_terminal_enabled = (
		_agent_controller != null and _agent_controller.claude_terminal_enabled
	)
	_stats_window_coordinator.gemini_terminal_enabled = (
		_agent_controller != null and _agent_controller.gemini_terminal_enabled
	)
	_stats_window_coordinator.agy_terminal_enabled = (
		_agent_controller != null and _agent_controller.agy_terminal_enabled
	)
	_stats_window_coordinator.agent_port = (
		_agent_controller.port
		if _agent_controller != null
		else AgentIntegrationControllerScript.DEFAULT_PORT
	)
	_stats_window_coordinator.codex_executable_path = (
		_agent_controller.executable_path if _agent_controller != null else ""
	)
	_stats_window_coordinator.codex_app_executable_path = (
		_agent_controller.codex_app_executable_path
		if _agent_controller != null else ""
	)
	_stats_window_coordinator.terminal_executable_path = (
		_agent_controller.terminal_executable_path
		if _agent_controller != null else ""
	)
	_stats_window_coordinator.opencode_app_executable_path = (
		_agent_controller.opencode_app_executable_path
		if _agent_controller != null else ""
	)
	_stats_window_coordinator.claude_app_executable_path = (
		_agent_controller.claude_app_executable_path
		if _agent_controller != null else ""
	)
	_stats_window_coordinator.autostart_supported = _is_autostart_supported()
	_stats_window_coordinator.keep_screen_on = _keep_screen_on
	_stats_window_coordinator.focus_mode = _focus_mode
	_stats_window_coordinator.visual_scale = float(
		state.get_snapshot().get("visual_scale", PetVisualScaleScript.DEFAULT_VALUE)
	)
	_stats_window_coordinator.interaction_label = Callable(self, "_interaction_label")
	_stats_window_coordinator.interaction_icon = Callable(self, "_interaction_icon")
	var refs: Dictionary = _stats_window_coordinator.build(self)
	_stats_window = refs["window"] as Window
	_stats_tabs = refs["tabs"] as TabContainer
	_stats_tab_buttons = refs["tab_buttons"] as Array[Button]
	_details_window_controller = refs["details_controller"]
	_connect_details_window_signals()
	_stats_window_coordinator.close_requested.connect(_destroy_stats_window)
	_stats_window_coordinator.window_input.connect(_on_stats_window_input)
	_stats_window_coordinator.tab_selected.connect(_select_stats_tab)
	_stats_window_coordinator.tab_changed.connect(_on_stats_tab_changed)
	var status_refs: Dictionary = refs["status_refs"]
	_stats_status = status_refs["stats_status"] as Label
	_companion_status = status_refs["companion_status"] as Label
	_wish_status = status_refs["wish_status"] as Label
	_unlock_status = status_refs["unlock_status"] as Label
	_last_message_status = status_refs["last_message_status"] as Label
	_care_action_buttons = status_refs["care_action_buttons"] as Dictionary
	_stats_bars = status_refs["stats_bars"] as Dictionary

	var settings_refs: Dictionary = refs["settings_refs"]
	_fps_option_button = settings_refs["fps_option_button"] as OptionButton
	_details_theme_option_button = settings_refs["details_theme_option_button"] as OptionButton
	_visual_scale_slider = settings_refs["visual_scale_slider"] as HSlider
	_visual_scale_value_label = settings_refs["visual_scale_value_label"] as Label
	_focus_mode_check_box = settings_refs["focus_mode_check_box"] as CheckBox
	_keep_screen_on_check_box = settings_refs["keep_screen_on_check_box"] as CheckBox
	_autostart_check_box = settings_refs["autostart_check_box"] as CheckBox
	_settings_feedback = settings_refs["settings_feedback"] as Label
	var agent_refs: Dictionary = refs["agent_refs"]
	_agent_port_spin_box = agent_refs["agent_port_spin_box"] as SpinBox
	_agent_status_label = agent_refs["agent_status_label"] as Label
	_codex_setup_progress_bar = (
		agent_refs["codex_setup_progress_bar"] as ProgressBar
	)
	_codex_trust_review_button = (
		agent_refs["codex_trust_review_button"] as Button
	)
	_codex_trust_recheck_button = (
		agent_refs["codex_trust_recheck_button"] as Button
	)
	_codex_trust_dialog = agent_refs["codex_trust_dialog"] as ConfirmationDialog
	_codex_trust_dialog.confirmed.connect(_open_codex_hook_review)
	_codex_trust_dialog.canceled.connect(_cancel_codex_hook_trust)
	_agent_codex_enabled_toggle = agent_refs["codex_enabled_toggle"] as Button
	_agent_codex_app_enabled_toggle = (
		agent_refs["codex_app_enabled_toggle"] as Button
	)
	_agent_terminal_codex_enabled_toggle = (
		agent_refs["terminal_codex_enabled_toggle"] as Button
	)
	_agent_terminal_opencode_enabled_toggle = (
		agent_refs["terminal_opencode_enabled_toggle"] as Button
	)
	_agent_vscode_opencode_enabled_toggle = (
		agent_refs["vscode_opencode_enabled_toggle"] as Button
	)
	_agent_opencode_app_enabled_toggle = (
		agent_refs["opencode_app_enabled_toggle"] as Button
	)
	_agent_copilot_enabled_toggle = agent_refs["copilot_enabled_toggle"] as Button
	_agent_claude_vscode_enabled_toggle = (
		agent_refs["claude_vscode_enabled_toggle"] as Button
	)
	_agent_claude_app_enabled_toggle = (
		agent_refs["claude_app_enabled_toggle"] as Button
	)
	_agent_claude_terminal_enabled_toggle = (
		agent_refs["claude_terminal_enabled_toggle"] as Button
	)
	_agent_gemini_terminal_enabled_toggle = (
		agent_refs["gemini_terminal_enabled_toggle"] as Button
	)
	_agent_agy_terminal_enabled_toggle = (
		agent_refs["agy_terminal_enabled_toggle"] as Button
	)
	_vscode_executable_line_edit = (
		agent_refs["vscode_executable_line_edit"] as LineEdit
	)
	_vscode_executable_hint = agent_refs["vscode_executable_hint"] as Label
	_vscode_executable_summary = agent_refs["vscode_executable_summary"] as Label
	_codex_app_executable_line_edit = (
		agent_refs["codex_app_executable_line_edit"] as LineEdit
	)
	_codex_app_executable_hint = agent_refs["codex_app_executable_hint"] as Label
	_codex_app_executable_summary = agent_refs["codex_app_executable_summary"] as Label
	_terminal_executable_line_edit = (
		agent_refs["terminal_executable_line_edit"] as LineEdit
	)
	_terminal_executable_hint = agent_refs["terminal_executable_hint"] as Label
	_terminal_executable_summary = agent_refs["terminal_executable_summary"] as Label
	_opencode_app_executable_line_edit = (
		agent_refs["opencode_app_executable_line_edit"] as LineEdit
	)
	_opencode_app_executable_hint = agent_refs["opencode_app_executable_hint"] as Label
	_opencode_app_executable_summary = agent_refs["opencode_app_executable_summary"] as Label
	_claude_app_executable_line_edit = (
		agent_refs["claude_app_executable_line_edit"] as LineEdit
	)
	_claude_app_executable_hint = agent_refs["claude_app_executable_hint"] as Label
	_claude_app_executable_summary = (
		agent_refs["claude_app_executable_summary"] as Label
	)
	_refresh_agent_settings_ui()
	# The settings builder cannot request this before its signals and control
	# references exist. Queue the initial query only after initialization.
	if _is_autostart_supported():
		call_deferred("_start_autostart_operation", "query", false)

	var character_refs: Dictionary = refs["character_refs"]
	_character_tab_index = int(character_refs["character_tab_index"])
	_character_list = character_refs["character_list"] as ItemList
	_character_use_button = character_refs["character_use_button"] as Button
	_character_delete_button = character_refs["character_delete_button"] as Button
	_mask_effect_panel = character_refs["mask_effect_panel"] as Control
	_mask_effect_hint = character_refs["mask_effect_hint"] as Control
	_mask_effect_values = character_refs["mask_effect_values"] as Control
	_mask_effect_x_spin = character_refs["mask_effect_x"] as SpinBox
	_mask_effect_y_spin = character_refs["mask_effect_y"] as SpinBox
	_mask_effect_scale_spin = character_refs["mask_effect_scale"] as SpinBox
	_mask_effect_header_state = character_refs["mask_effect_header_state"] as Label
	_mask_effect_header_chevron = character_refs["mask_effect_header_chevron"] as Label
	_mask_effect_apply_button = character_refs["mask_effect_apply_button"] as Button
	_mask_effect_reset_button = character_refs["mask_effect_reset_button"] as Button
	_mask_effect_feedback_dialog = character_refs["mask_effect_feedback_dialog"] as AcceptDialog
	_refresh_mask_effect_editor()
	_character_feedback = character_refs["character_feedback"] as Label
	_character_import_dialog = character_refs["character_import_dialog"] as FileDialog
	_character_update_dialog = character_refs["character_update_dialog"] as ConfirmationDialog
	_character_delete_dialog = character_refs["character_delete_dialog"] as ConfirmationDialog
	_select_stats_tab(0)


func _connect_details_window_signals() -> void:
	_details_window_controller.care_action_requested.connect(
		_on_care_action_requested
	)
	_details_window_controller.close_requested.connect(_destroy_stats_window)
	_details_window_controller.target_fps_selected.connect(_on_target_fps_selected)
	_details_window_controller.details_theme_selected.connect(_on_details_theme_selected)
	_details_window_controller.agent_codex_enabled_toggled.connect(
		_on_codex_enabled_toggled
	)
	_details_window_controller.agent_codex_app_enabled_toggled.connect(
		_on_codex_app_enabled_toggled
	)
	_details_window_controller.agent_terminal_codex_enabled_toggled.connect(
		_on_terminal_codex_enabled_toggled
	)
	_details_window_controller.agent_terminal_opencode_enabled_toggled.connect(
		_on_terminal_opencode_enabled_toggled
	)
	_details_window_controller.agent_vscode_opencode_enabled_toggled.connect(
		_on_vscode_opencode_enabled_toggled
	)
	_details_window_controller.agent_opencode_app_enabled_toggled.connect(
		_on_opencode_app_enabled_toggled
	)
	_details_window_controller.agent_copilot_enabled_toggled.connect(
		_on_copilot_enabled_toggled
	)
	_details_window_controller.agent_claude_vscode_enabled_toggled.connect(
		_on_claude_vscode_enabled_toggled
	)
	_details_window_controller.agent_claude_app_enabled_toggled.connect(
		_on_claude_app_enabled_toggled
	)
	_details_window_controller.agent_claude_terminal_enabled_toggled.connect(
		_on_claude_terminal_enabled_toggled
	)
	_details_window_controller.agent_gemini_terminal_enabled_toggled.connect(
		_on_gemini_terminal_enabled_toggled
	)
	_details_window_controller.agent_agy_terminal_enabled_toggled.connect(
		_on_agy_terminal_enabled_toggled
	)
	_details_window_controller.agent_port_changed.connect(_on_agent_port_changed)
	_details_window_controller.codex_trust_review_requested.connect(
		_open_codex_hook_review
	)
	_details_window_controller.codex_trust_recheck_requested.connect(
		_recheck_codex_hook_trust
	)
	_details_window_controller.vscode_executable_path_changed.connect(
		_on_vscode_executable_path_changed
	)
	_details_window_controller.codex_app_executable_path_changed.connect(
		_on_codex_app_executable_path_changed
	)
	_details_window_controller.terminal_executable_path_changed.connect(
		_on_terminal_executable_path_changed
	)
	_details_window_controller.opencode_app_executable_path_changed.connect(
		_on_opencode_app_executable_path_changed
	)
	_details_window_controller.claude_app_executable_path_changed.connect(
		_on_claude_app_executable_path_changed
	)
	_details_window_controller.autostart_toggled.connect(_on_autostart_toggled)
	_details_window_controller.keep_screen_on_toggled.connect(_on_keep_screen_on_toggled)
	_details_window_controller.focus_mode_toggled.connect(_on_focus_mode_toggled)
	_details_window_controller.visual_scale_previewed.connect(_on_visual_scale_previewed)
	_details_window_controller.visual_scale_changed.connect(_on_visual_scale_changed)
	_details_window_controller.character_selected.connect(_on_character_selected)
	_details_window_controller.character_use_requested.connect(_use_selected_character)
	_details_window_controller.character_delete_requested.connect(
		_confirm_delete_selected_character
	)
	_details_window_controller.character_import_requested.connect(
		_open_character_import_dialog
	)
	_details_window_controller.open_character_packs_folder_requested.connect(
		_open_character_packs_folder
	)
	_details_window_controller.character_archive_selected.connect(
		_install_character_archive
	)
	_details_window_controller.character_update_confirmed.connect(
		_install_pending_character_archive
	)
	_details_window_controller.character_delete_confirmed.connect(
		_delete_selected_character
	)
	_details_window_controller.mask_effect_changed.connect(
		_on_mask_effect_changed
	)
	_details_window_controller.mask_effect_toggle_requested.connect(
		_on_mask_effect_toggle_requested
	)
	_details_window_controller.mask_effect_apply_requested.connect(
		_on_mask_effect_apply_requested
	)
	_details_window_controller.mask_effect_reset_requested.connect(
		_on_mask_effect_reset_requested
	)


func _on_care_action_requested(action: String) -> void:
	match action:
		"feed":
			_run_care_action(1)
		"water":
			_run_care_action(2)
		"pet":
			_run_care_action(3)
		"work":
			_run_care_action(4)
		"sleep":
			_run_care_action(5)


func _on_stats_tab_changed(tab_index: int) -> void:
	_refresh_stats_tab_buttons(tab_index)
	if tab_index != _character_tab_index and _mask_effect_editing:
		_cancel_mask_effect_editing()
	if tab_index == AGENT_TAB_INDEX and _agent_controller != null:
		_agent_controller.refresh_enabled_executable_paths_if_invalid()
	if tab_index != _character_tab_index or _character_tab_loaded:
		return
	_refresh_character_list()


func _select_stats_tab(tab_index: int) -> void:
	if not is_instance_valid(_stats_tabs):
		return
	_stats_tabs.current_tab = clampi(tab_index, 0, _stats_tabs.get_tab_count() - 1)
	_refresh_stats_tab_buttons(_stats_tabs.current_tab)


func _refresh_stats_tab_buttons(selected_index: int) -> void:
	for index: int in _stats_tab_buttons.size():
		_apply_stats_tab_button_style(
			_stats_tab_buttons[index], index == selected_index
		)


func _apply_stats_tab_button_style(button: Button, selected: bool) -> void:
	var normal_bg := _details_color("#0f0f0f", "#37373d") \
			if selected else _details_color("#e6e6e6", "#252526")
	var normal_border := _details_color("#0f0f0f", "#3794ff") \
			if selected else _details_color("#f2f2f2", "#333333")
	var hover_bg := normal_bg if selected \
			else _details_color("#e5e5e5", "#2a2d2e")
	var pressed_bg := _details_color("#272727", "#094771") \
			if selected else _details_color("#d9d9d9", "#333337")
	var normal_style := _details_style(normal_bg, normal_border, 8)
	var hover_style := _details_style(
		hover_bg,
		normal_border if selected else _details_color("#e5e5e5", "#4e4e4e"),
		8
	)
	var pressed_style := _details_style(pressed_bg, normal_border, 8)
	if _details_theme_mode == "dark" and selected:
		normal_style.border_width_bottom = 2
		hover_style.border_width_bottom = 2
		pressed_style.border_width_bottom = 2
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)
	button.add_theme_color_override(
		"font_color", Color("#ffffff") if selected \
		else _details_color("#0f0f0f", "#cccccc")
	)
	button.add_theme_color_override(
		"font_hover_color", Color("#ffffff") if selected \
		else _details_color("#0f0f0f", "#ffffff")
	)
	button.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	button.add_theme_font_size_override("font_size", 15)


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
	_character_entries.append_array(_character_coordinator.list_entries().slice(1))
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
	_refresh_mask_effect_editor()


func _on_character_selected(_index: int) -> void:
	_update_character_buttons()


func _refresh_mask_effect_editor() -> void:
	if not is_instance_valid(_mask_effect_x_spin) \
			or not is_instance_valid(_mask_effect_header_state):
		return
	var enabled: bool = bool(pet.is_codex_pet())
	_mask_effect_panel.visible = enabled
	if not enabled:
		_mask_effect_editing = false
		pet.set_effect_preview("mask", false)
		return
	_load_mask_effect_editor_values()
	_set_mask_effect_editing(false)


func _load_mask_effect_editor_values() -> void:
	var definition: Dictionary = pet.effect_editor_definition("mask")
	var raw_anchor: Variant = definition.get("anchor", [0.0, -20.0])
	var anchor := Vector2.ZERO
	if raw_anchor is Array and raw_anchor.size() >= 2:
		anchor = Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
	var scale := float(definition.get("scale", 0.38))
	_pending_mask_anchor = anchor
	_pending_mask_scale = scale
	_mask_effect_x_spin.set_value_no_signal(anchor.x)
	_mask_effect_y_spin.set_value_no_signal(anchor.y)
	_mask_effect_scale_spin.set_value_no_signal(scale)


func _set_mask_effect_editing(editing: bool) -> void:
	_mask_effect_editing = editing
	_mask_effect_hint.visible = editing
	_mask_effect_values.visible = editing
	_mask_effect_x_spin.editable = editing
	_mask_effect_y_spin.editable = editing
	_mask_effect_scale_spin.editable = editing
	_details_window_controller.configure_mask_effect_header(
		_mask_effect_header_state, _mask_effect_header_chevron, editing
	)
	_mask_effect_apply_button.visible = editing
	_mask_effect_reset_button.disabled = not editing
	pet.set_effect_preview("mask", editing)


func _cancel_mask_effect_editing() -> void:
	if not _mask_effect_editing:
		pet.set_effect_preview("mask", false)
		return
	pet.reload_effect_overrides()
	_load_mask_effect_editor_values()
	_set_mask_effect_editing(false)


func _on_mask_effect_changed(anchor: Vector2, scale: float) -> void:
	if not pet.is_codex_pet():
		return
	if not _mask_effect_editing:
		return
	_pending_mask_anchor = anchor
	_pending_mask_scale = clampf(scale, 0.05, 2.0)
	pet.apply_effect_override("mask", _pending_mask_effect_definition())


func _on_mask_effect_toggle_requested() -> void:
	if not pet.is_codex_pet():
		return
	if not _mask_effect_editing:
		_set_mask_effect_editing(true)
		return
	_cancel_mask_effect_editing()


func _on_mask_effect_apply_requested() -> void:
	if not pet.is_codex_pet() or not _mask_effect_editing:
		return
	var saved := CharacterEffectPreferencesScript.set_effect(
		pet.get_character_id(), "mask", _pending_mask_effect_definition()
	)
	if saved:
		pet.apply_effect_override("mask", _pending_mask_effect_definition())
		_set_mask_effect_editing(false)
		_show_mask_effect_feedback("眼罩位置與大小已保存。")
	else:
		_show_mask_effect_feedback("保存失敗，請稍後再試。")


func _on_mask_effect_reset_requested() -> void:
	if not pet.is_codex_pet():
		return
	CharacterEffectPreferencesScript.clear_effect(
		pet.get_character_id(), "mask"
	)
	pet.apply_effect_override("mask", {})
	_load_mask_effect_editor_values()
	_set_mask_effect_editing(true)


func _show_mask_effect_feedback(message: String) -> void:
	if not is_instance_valid(_mask_effect_feedback_dialog):
		return
	_mask_effect_feedback_dialog.dialog_text = message
	_mask_effect_feedback_dialog.popup_centered()


func _pending_mask_effect_definition() -> Dictionary:
	return {
		"anchor": [_pending_mask_anchor.x, _pending_mask_anchor.y],
		"scale": _pending_mask_scale,
	}


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
	_cancel_mask_effect_editing()
	if is_instance_valid(_character_import_dialog):
		_character_import_dialog.popup_centered_ratio(0.75)


func _install_character_archive(path: String) -> void:
	var inspection: Dictionary = _character_coordinator.inspect_archive(path)
	if not bool(inspection.get("ok", false)):
		_character_feedback.text = "匯入失敗：%s" % String(inspection.get(
			"message", "未知錯誤"
		))
		return
	for entry: Dictionary in _character_coordinator.list_entries():
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
	var result: Dictionary = _character_coordinator.install_archive(path)
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
	_cancel_mask_effect_editing()
	var entry := _selected_character_entry()
	if entry.is_empty():
		return
	var is_reload: bool = String(entry.id) == pet.get_character_id()
	state.save_state()
	_apply_character_without_restart(String(entry.id), is_reload)


func _apply_character_without_restart(character_id: String, is_reload: bool) -> bool:
	var switch_result: Dictionary = _character_coordinator.switch_character(character_id)
	if not bool(switch_result.get("ok", false)):
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
	call_deferred("_reposition_after_character_switch", character_id)
	_refresh_character_list(
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
		4: "%s  %s（賺取金幣）" % [
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
	_character_coordinator.save_selected_character_id(character_id)


func _confirm_delete_selected_character() -> void:
	_cancel_mask_effect_editing()
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
	var result: Dictionary = _character_coordinator.remove_pack(character_id)
	if not bool(result.get("ok", false)):
		_character_feedback.text = "刪除失敗：%s" % String(result.get(
			"message", "未知錯誤"
		))
		return
	_refresh_character_list("已刪除角色包；遊戲進度仍保留。")
	if was_active:
		_apply_character_without_restart("open_desktop_pet_default", false)


func _open_character_packs_folder() -> void:
	_cancel_mask_effect_editing()
	if _character_coordinator.ensure_packs_root() != OK:
		_character_feedback.text = "無法建立角色包資料夾。"
		return
	OS.shell_open(ProjectSettings.globalize_path(
		_character_coordinator.packs_root()
	))


func _run_care_action(id: int) -> void:
	_cancel_mask_effect_editing()
	var result: String = _gameplay_coordinator.request_care_action(id)
	if result == "woke":
		_last_user_activity_ms = Time.get_ticks_msec()
		return
	if result == "busy":
		_say_dialogue("action_busy", "先等目前的動作完成～", 1.5)


func _details_color(light: String, dark: String) -> Color:
	return Color(dark if _details_theme_mode == "dark" else light)


func _update_agent_enabled_toggles() -> void:
	if is_instance_valid(_agent_codex_enabled_toggle):
		_agent_codex_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.codex_enabled
		)
	if is_instance_valid(_agent_codex_app_enabled_toggle):
		_agent_codex_app_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.codex_app_enabled
		)
	if is_instance_valid(_agent_terminal_codex_enabled_toggle):
		_agent_terminal_codex_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.terminal_codex_enabled
		)
	if is_instance_valid(_agent_terminal_opencode_enabled_toggle):
		_agent_terminal_opencode_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.terminal_opencode_enabled
		)
	if is_instance_valid(_agent_vscode_opencode_enabled_toggle):
		_agent_vscode_opencode_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.vscode_opencode_enabled
		)
	if is_instance_valid(_agent_opencode_app_enabled_toggle):
		_agent_opencode_app_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.opencode_app_enabled
		)
	if is_instance_valid(_agent_copilot_enabled_toggle):
		_agent_copilot_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.copilot_enabled
		)
	if is_instance_valid(_agent_claude_vscode_enabled_toggle):
		_agent_claude_vscode_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.claude_vscode_enabled
		)
	if is_instance_valid(_agent_claude_app_enabled_toggle):
		_agent_claude_app_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.claude_app_enabled
		)
	if is_instance_valid(_agent_claude_terminal_enabled_toggle):
		_agent_claude_terminal_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.claude_terminal_enabled
		)
	if is_instance_valid(_agent_gemini_terminal_enabled_toggle):
		_agent_gemini_terminal_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.gemini_terminal_enabled
		)
	if is_instance_valid(_agent_agy_terminal_enabled_toggle):
		_agent_agy_terminal_enabled_toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.agy_terminal_enabled
		)


func _details_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _show_stats_window(
	select_tab := -1, reminder_id := "", create_reminder := false
) -> void:
	if is_instance_valid(_stats_window):
		_refresh_ui(state.get_snapshot())
		if select_tab >= 0:
			_select_stats_tab(select_tab)
		if not reminder_id.is_empty() and _details_window_controller != null:
			_details_window_controller.focus_reminder(reminder_id)
		elif create_reminder and _details_window_controller != null:
			_details_window_controller.start_new_reminder()
		call_deferred("_bring_stats_window_forward")
		return
	_build_stats_window()
	_refresh_ui(state.get_snapshot())
	var pet_position: Vector2i = _window_service.window_position()
	var pet_size: Vector2i = _window_service.window_size()
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
	if not reminder_id.is_empty() and _details_window_controller != null:
		_details_window_controller.focus_reminder(reminder_id)
	elif create_reminder and _details_window_controller != null:
		_details_window_controller.start_new_reminder()
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
	_cancel_mask_effect_editing()
	if _stats_window_coordinator != null:
		_stats_window_coordinator.destroy()
		_stats_window_coordinator = null
	_details_window_controller = null
	_stats_window = null
	_stats_tabs = null
	_stats_tab_buttons.clear()
	_stats_status = null
	_companion_status = null
	_wish_status = null
	_unlock_status = null
	_last_message_status = null
	_fps_option_button = null
	_details_theme_option_button = null
	_visual_scale_slider = null
	_visual_scale_value_label = null
	_focus_mode_check_box = null
	_keep_screen_on_check_box = null
	_agent_codex_enabled_toggle = null
	_agent_codex_app_enabled_toggle = null
	_agent_terminal_codex_enabled_toggle = null
	_agent_terminal_opencode_enabled_toggle = null
	_agent_vscode_opencode_enabled_toggle = null
	_agent_opencode_app_enabled_toggle = null
	_agent_copilot_enabled_toggle = null
	_agent_claude_vscode_enabled_toggle = null
	_agent_claude_app_enabled_toggle = null
	_agent_claude_terminal_enabled_toggle = null
	_agent_gemini_terminal_enabled_toggle = null
	_agent_agy_terminal_enabled_toggle = null
	_agent_port_spin_box = null
	_agent_status_label = null
	_codex_setup_progress_bar = null
	_codex_trust_review_button = null
	_codex_trust_recheck_button = null
	_codex_trust_dialog = null
	_vscode_executable_line_edit = null
	_vscode_executable_hint = null
	_vscode_executable_summary = null
	_codex_app_executable_line_edit = null
	_codex_app_executable_hint = null
	_codex_app_executable_summary = null
	_terminal_executable_line_edit = null
	_terminal_executable_hint = null
	_terminal_executable_summary = null
	_opencode_app_executable_line_edit = null
	_opencode_app_executable_hint = null
	_opencode_app_executable_summary = null
	_claude_app_executable_line_edit = null
	_claude_app_executable_hint = null
	_claude_app_executable_summary = null
	_autostart_check_box = null
	_settings_feedback = null
	_character_list = null
	_character_feedback = null
	_character_use_button = null
	_character_delete_button = null
	_mask_effect_panel = null
	_mask_effect_hint = null
	_mask_effect_values = null
	_mask_effect_x_spin = null
	_mask_effect_y_spin = null
	_mask_effect_scale_spin = null
	_mask_effect_header_state = null
	_mask_effect_header_chevron = null
	_mask_effect_apply_button = null
	_mask_effect_reset_button = null
	_mask_effect_feedback_dialog = null
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
	var keep_screen_on := DEFAULT_KEEP_SCREEN_ON
	var focus_mode := DEFAULT_FOCUS_MODE
	if config.load(UI_SETTINGS_PATH) == OK:
		target_fps = int(config.get_value(
			"performance", "target_fps", DEFAULT_TARGET_FPS
		))
		_details_theme_mode = String(config.get_value(
			"appearance", "details_theme", "light"
		))
		keep_screen_on = bool(config.get_value(
			"power", "keep_screen_on", DEFAULT_KEEP_SCREEN_ON
		))
		focus_mode = bool(config.get_value(
			"behavior", "focus_mode", DEFAULT_FOCUS_MODE
		))
	if _details_theme_mode not in ["light", "dark"]:
		_details_theme_mode = "light"
	Engine.max_fps = _normalize_target_fps(target_fps)
	_apply_keep_screen_on(keep_screen_on)
	_apply_focus_mode(focus_mode)


func _apply_keep_screen_on(enabled: bool) -> void:
	_keep_screen_on = enabled
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(enabled)
	if is_instance_valid(_keep_screen_on_check_box):
		_keep_screen_on_check_box.set_pressed_no_signal(enabled)


func _apply_focus_mode(enabled: bool) -> void:
	_focus_mode = enabled
	if enabled and _gameplay_coordinator != null:
		_gameplay_coordinator.cancel_autonomous_action()
	if is_instance_valid(_focus_mode_check_box):
		_focus_mode_check_box.set_pressed_no_signal(enabled)


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


func _on_details_theme_selected(index: int) -> void:
	var requested := "dark" if index == 1 else "light"
	if requested == _details_theme_mode:
		return
	_details_theme_mode = requested
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("appearance", "details_theme", _details_theme_mode)
	config.save(UI_SETTINGS_PATH)
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


func _on_keep_screen_on_toggled(enabled: bool) -> void:
	_apply_keep_screen_on(enabled)
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("power", "keep_screen_on", enabled)
	config.save(UI_SETTINGS_PATH)


func _on_focus_mode_toggled(enabled: bool) -> void:
	_apply_focus_mode(enabled)
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("behavior", "focus_mode", enabled)
	config.save(UI_SETTINGS_PATH)


func _on_visual_scale_previewed(value: float) -> void:
	pet.set_visual_size(value)


func _on_visual_scale_changed(value: float) -> void:
	state.set_visual_scale(value)


func _on_codex_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_codex_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_VSCODE]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_codex_app_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_codex_app_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_CODEX_APP]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_terminal_codex_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_terminal_codex_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_TERMINAL]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_terminal_opencode_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_terminal_opencode_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_TERMINAL]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_vscode_opencode_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_vscode_opencode_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_VSCODE]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_opencode_app_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_opencode_app_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_OPENCODE_APP]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_claude_vscode_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_claude_vscode_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_VSCODE]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_claude_app_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_claude_app_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_CLAUDE_APP]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_claude_terminal_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_claude_terminal_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_TERMINAL]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_gemini_terminal_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_gemini_terminal_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_TERMINAL]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_agy_terminal_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_agy_terminal_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_TERMINAL]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_copilot_enabled_toggled(enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_copilot_enabled(enabled)
	if enabled:
		_agent_controller.refresh_executable_paths_if_invalid(
			[AgentIntegrationControllerScript.TARGET_VSCODE]
		)
	_apply_agent_control_state()
	call_deferred("_apply_agent_control_state")


func _on_agent_port_changed(value: float) -> void:
	if _agent_controller == null:
		return
	if _agent_controller.is_any_enabled():
		if is_instance_valid(_agent_port_spin_box):
			_agent_port_spin_box.set_value_no_signal(_agent_controller.port)
		return
	var pending_port := _agent_controller.normalize_port(roundi(value))
	_agent_controller.set_port(pending_port)


func _on_vscode_executable_path_changed(path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_executable_path(path)
	_refresh_agent_settings_ui()


func _on_codex_app_executable_path_changed(path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_codex_app_executable_path(path)
	_refresh_agent_settings_ui()


func _on_terminal_executable_path_changed(path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_terminal_executable_path(path)
	_refresh_agent_settings_ui()


func _on_opencode_app_executable_path_changed(path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_opencode_app_executable_path(path)
	_refresh_agent_settings_ui()


func _on_claude_app_executable_path_changed(path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_claude_app_executable_path(path)
	_refresh_agent_settings_ui()


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


func _is_autostart_supported() -> bool:
	return _autostart_service != null and _autostart_service.is_supported()


func _on_autostart_toggled(enabled: bool) -> void:
	if not _is_autostart_supported():
		return
	_start_autostart_operation("set", enabled)


func _start_autostart_operation(operation: String, enabled: bool) -> void:
	if is_instance_valid(_autostart_check_box):
		_autostart_check_box.disabled = true
	if is_instance_valid(_settings_feedback):
		_settings_feedback.text = (
			"正在讀取 Windows 開機啟動設定…"
			if operation == "query"
			else "正在套用開機啟動設定…"
		)
	if _autostart_service == null:
		_finish_autostart_operation(
			-1, operation, enabled,
			{"exists": false, "matches": false, "success": false}
		)
		return
	if operation == "query":
		_autostart_service.query()
	else:
		_autostart_service.set_enabled(enabled)


func _finish_autostart_operation(
	operation_id: int,
	operation: String,
	enabled: bool,
	result: Dictionary
) -> void:
	# A panel can be closed and recreated while an older registry request is
	# finishing. Only the newest request may update the current controls.
	if _autostart_service != null \
			and operation_id >= 0 \
			and not _autostart_service.is_latest_operation(operation_id):
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
	if is_instance_valid(_visual_scale_slider):
		_visual_scale_slider.set_value_no_signal(current_visual_scale)
	if is_instance_valid(_visual_scale_value_label):
		_visual_scale_value_label.text = "%d%%" % roundi(current_visual_scale * 100.0)
	_update_unlock_tracking()
	var level_text := "Lv.%d  ·  %d 金幣  ·  XP %d/%d" % [
		snapshot.level, snapshot.coins, snapshot.xp, snapshot.level * 20
	]
	if is_instance_valid(_stats_status):
		_stats_status.text = level_text
		_wish_status.text = "願望：%s" % _formatted_wish_text(snapshot)

	if is_instance_valid(_companion_status):
		_companion_status.text = (
			"陪伴紀錄 : "
			+ "連續陪伴 %d 天"
		) % [
			int(snapshot.get("companion_streak", 0)),
		]
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
	if is_instance_valid(_tray_menu) and _tray_menu.item_count > 0:
		_tray_menu.set_item_text(0, level_text)


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
	if not _focus_mode and not pet.is_busy() and not state.is_action_busy():
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
