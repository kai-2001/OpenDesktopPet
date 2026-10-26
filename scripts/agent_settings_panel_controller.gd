class_name AgentSettingsPanelController
extends RefCounted

# Connects the Agent tab of the details window to AgentIntegrationController:
# channel switches, the shared port, executable paths, setup status and the
# Codex hook trust flow. It lives for the whole session; the tab controls are
# bound while the details window exists.

const AgentChannelCatalogScript = preload("res://scripts/agent_channel_catalog.gd")
const CodexHookTrustServiceScript = preload("res://scripts/codex_hook_trust_service.gd")

signal speech_requested(text: String, seconds: float)
signal agent_status_requested(
	message: String, reaction_action: String, target_app: String, agent: String
)

var _agent_controller: AgentIntegrationController
var _details_controller
var _theme_mode := "light"
var _channel_toggles: Dictionary = {}
var _port_spin_box: SpinBox
var _status_label: Label
var _setup_progress_bar: ProgressBar
var _trust_review_button: Button
var _trust_recheck_button: Button
var _trust_dialog: ConfirmationDialog


func configure(agent_controller: AgentIntegrationController) -> void:
	_agent_controller = agent_controller
	_agent_controller.configuration_failed.connect(_handle_configuration_failed)
	_agent_controller.codex_unavailable.connect(_handle_codex_unavailable)
	_agent_controller.codex_trust_required.connect(_handle_codex_trust_required)
	_agent_controller.codex_trust_ready.connect(_handle_codex_trust_ready)
	_agent_controller.codex_trust_refresh_required.connect(
		_handle_codex_trust_refresh_required
	)
	_agent_controller.codex_status_check_failed.connect(_handle_codex_status_check_failed)
	_agent_controller.state_changed.connect(refresh)
	_agent_controller.executable_path_detection_started.connect(
		_on_executable_path_detection_started
	)
	_agent_controller.executable_path_detection_finished.connect(
		_on_executable_path_detection_finished
	)


func bind(details_controller, agent_refs: Dictionary, theme_mode: String) -> void:
	_details_controller = details_controller
	_theme_mode = theme_mode
	_channel_toggles = agent_refs["channel_toggles"]
	_port_spin_box = agent_refs["agent_port_spin_box"] as SpinBox
	_status_label = agent_refs["agent_status_label"] as Label
	_setup_progress_bar = agent_refs["codex_setup_progress_bar"] as ProgressBar
	_trust_review_button = agent_refs["codex_trust_review_button"] as Button
	_trust_recheck_button = agent_refs["codex_trust_recheck_button"] as Button
	_trust_dialog = agent_refs["codex_trust_dialog"] as ConfirmationDialog
	_trust_dialog.confirmed.connect(_open_codex_hook_review)
	_trust_dialog.canceled.connect(_cancel_codex_hook_trust)
	_details_controller.agent_channel_toggled.connect(_on_channel_toggled)
	_details_controller.agent_port_changed.connect(_on_port_changed)
	_details_controller.agent_executable_path_changed.connect(
		_on_executable_path_changed
	)
	_details_controller.codex_trust_review_requested.connect(_open_codex_hook_review)
	_details_controller.codex_trust_recheck_requested.connect(_recheck_codex_hook_trust)
	refresh()


func unbind() -> void:
	_details_controller = null
	_channel_toggles = {}
	_port_spin_box = null
	_status_label = null
	_setup_progress_bar = null
	_trust_review_button = null
	_trust_recheck_button = null
	_trust_dialog = null


func refresh() -> void:
	_apply_control_state()
	if _details_controller != null and _agent_controller != null:
		var executable_paths: Dictionary = (
			_agent_controller.get_settings_snapshot()["executable_paths"]
		)
		for target_entry: Dictionary in AgentChannelCatalogScript.TARGETS:
			var target := String(target_entry["target"])
			_details_controller.refresh_agent_executable_path(
				target, String(executable_paths[target])
			)
	if not is_instance_valid(_status_label):
		return
	var codex_trust_pending := (
		_agent_controller != null and _agent_controller.has_pending_codex_trust()
	)
	var codex_setup_busy := (
		_agent_controller != null and _agent_controller.is_codex_setup_busy()
	)
	if is_instance_valid(_setup_progress_bar):
		_setup_progress_bar.visible = codex_setup_busy
	if is_instance_valid(_trust_review_button):
		_trust_review_button.visible = codex_trust_pending
		_trust_review_button.disabled = codex_setup_busy
	if is_instance_valid(_trust_recheck_button):
		_trust_recheck_button.visible = codex_trust_pending
		_trust_recheck_button.disabled = codex_setup_busy
	if codex_setup_busy:
		_status_label.text = "狀態: 正在檢查 Codex 與通知設定…"
		_status_label.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)
		return
	if codex_trust_pending:
		_status_label.text = (
			"尚未啟用：請先在 Codex 信任桌寵 Hook，再按「我已信任，檢查通知」"
		)
		_status_label.add_theme_color_override(
			"font_color", _details_color("#a66b16", "#dcdcaa")
		)
		return
	if _agent_controller == null or not _agent_controller.is_any_enabled():
		_status_label.text = "狀態: 已關閉"
		_status_label.add_theme_color_override(
			"font_color", _details_color("#68747a", "#9da1a6")
		)
		return
	if _agent_controller.is_running():
		_status_label.text = "狀態: 監聽中  127.0.0.1:%d" % _agent_controller.port
		_status_label.add_theme_color_override(
			"font_color", _details_color("#238b9d", "#4fc1ff")
		)
	else:
		_status_label.text = "狀態: 無法監聽，通訊埠可能被占用"
		_status_label.add_theme_color_override(
			"font_color", _details_color("#b44949", "#ff8c8c")
		)


func _apply_control_state() -> void:
	var enabled := _agent_controller != null and _agent_controller.is_any_enabled()
	var codex_busy := (
		_agent_controller != null and _agent_controller.is_codex_setup_busy()
	)
	for channel_id: String in _channel_toggles:
		var toggle := _channel_toggles[channel_id] as Button
		if not is_instance_valid(toggle):
			continue
		toggle.call(
			"set_enabled_state",
			_agent_controller != null and _agent_controller.is_channel_enabled(channel_id)
		)
		if AgentChannelCatalogScript.channel(channel_id)["setup"] \
				== AgentChannelCatalogScript.SETUP_CODEX:
			toggle.disabled = codex_busy
	if is_instance_valid(_port_spin_box):
		_port_spin_box.editable = not enabled
		_port_spin_box.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		)
		var port_line_edit := _port_spin_box.get_line_edit()
		port_line_edit.editable = not enabled
		port_line_edit.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		)
		_port_spin_box.modulate = (
			Color("#8c979b") if enabled else Color.WHITE
		)


func _on_channel_toggled(channel_id: String, enabled: bool) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_channel_enabled(channel_id, enabled)
	_apply_control_state()
	call_deferred("_apply_control_state")


func _on_port_changed(value: float) -> void:
	if _agent_controller == null:
		return
	if _agent_controller.is_any_enabled():
		if is_instance_valid(_port_spin_box):
			_port_spin_box.set_value_no_signal(_agent_controller.port)
		return
	var pending_port := _agent_controller.normalize_port(roundi(value))
	_agent_controller.set_port(pending_port)


func _on_executable_path_changed(target: String, path: String) -> void:
	if _agent_controller == null:
		return
	_agent_controller.set_target_executable_path(target, path)
	refresh()


func _on_executable_path_detection_started(targets: Array) -> void:
	if _details_controller != null:
		_details_controller.set_agent_executable_path_detection_state(targets, true)


func _on_executable_path_detection_finished(targets: Array) -> void:
	if _details_controller != null:
		_details_controller.set_agent_executable_path_detection_state(targets, false)
	refresh()


func _handle_configuration_failed(target_name: String) -> void:
	speech_requested.emit(
		"%s 通知設定失敗，已自動關閉開關。請確認相關檔案與權限後再試。" % target_name, 8.0
	)


func _handle_codex_unavailable(target_name: String, _message: String) -> void:
	speech_requested.emit(
		(
			"%s 通知無法開啟：找不到支援 Hook 審查的 Codex。請先安裝或更新 "
			+ "Codex Desktop、VS Code Codex 擴充功能或 Codex CLI。"
		) % target_name,
		8.0
	)


func _handle_codex_status_check_failed(target_name: String, _message: String) -> void:
	_apply_control_state()
	if _agent_controller != null and _agent_controller.has_pending_codex_trust():
		speech_requested.emit(
			"暫時無法確認 Codex Hook 狀態，請稍後再按「我已信任，檢查通知」。", 8.0
		)
		return
	speech_requested.emit(
		"暫時無法確認 %s 的 Codex 通知狀態，開關先維持關閉，請稍後再打開一次。" % target_name,
		8.0
	)


func _handle_codex_trust_required(
	target_name: String, status: String, message: String
) -> void:
	_show_codex_trust_instructions(
		"你正在開啟「%s Codex」通知。三種 Codex 共用同一組桌寵 Hook 信任。" % target_name,
		target_name, status, message
	)


func _handle_codex_trust_refresh_required(
	target_name: String, status: String, message: String
) -> void:
	_show_codex_trust_instructions(
		"桌寵已更新 Codex 通知 Hook，Codex 需要重新信任後才會繼續通知。",
		target_name, status, message
	)


func _show_codex_trust_instructions(
	intro: String, target_name: String, status: String, message: String
) -> void:
	_apply_control_state()
	if not is_instance_valid(_trust_dialog):
		speech_requested.emit("%s 的 Codex Hook 尚待信任，請開啟 Hook 審查。" % target_name, 8.0)
		return
	var status_hint := "目前狀態：%s" % message
	if status == CodexHookTrustServiceScript.STATUS_UNAVAILABLE:
		status_hint += "\n這台電腦找不到可用的 Codex 執行核心，請先安裝或更新 Codex。"
	_trust_dialog.dialog_text = (
		"%s"
		+ "\n\n%s\n\n"
		+ "不需另外安裝 CLI；桌寵會使用 Codex Desktop、VS Code 擴充功能或"
		+ "獨立 CLI 所提供的 Codex 核心。\n\n"
		+ "1. 按「開啟 Codex 信任畫面」。\n"
		+ "2. 在 PowerShell 選 1. Review hooks，再按 Enter；這一步只會開啟 Hook 清單。\n"
		+ "3. 在 Hook 清單依序選取 Stop、PermissionRequest、PreToolUse，"
		+ "每一項都按 Enter 開啟詳細內容。\n"
		+ "4. 在每一項找到 Open Desktop Pet 的 Hook，將核取狀態切換為 [x]。"
		+ "[ ] 表示尚未信任；三項都顯示 [x] 才算完成信任。\n"
		+ "5. 按 Esc 返回 Hook 清單；若仍在審查畫面，再按一次 Esc 離開。\n"
		+ "6. 回到桌寵，按「我已信任，檢查通知」。\n\n"
		+ "選 2 會信任所有待審 Hook；選 3 不會信任，通知也不會啟用。"
	) % [intro, status_hint]
	_trust_dialog.popup_centered(Vector2i(700, 540))


func _handle_codex_trust_ready(target_name: String, target_app: String) -> void:
	if is_instance_valid(_trust_dialog):
		_trust_dialog.hide()
	_apply_control_state()
	agent_status_requested.emit(
		"%s 的 Codex 通知已完成信任並啟用。" % target_name,
		"idle",
		target_app,
		"codex"
	)


func _open_codex_hook_review() -> void:
	if _agent_controller == null or not _agent_controller.open_codex_hook_review():
		if is_instance_valid(_trust_dialog):
			_trust_dialog.dialog_text = (
				"無法開啟 Codex Hook 審查。請確認 Codex Desktop、VS Code 的 Codex "
				+ "擴充功能或 Codex CLI 已安裝並更新，再重新嘗試。"
			)
			call_deferred("_show_codex_trust_dialog")
		return
	_apply_control_state()


func _recheck_codex_hook_trust() -> void:
	if _agent_controller == null:
		speech_requested.emit("Codex 通知服務尚未就緒，請關閉並重新開啟桌寵。", 6.0)
		return
	if _agent_controller.is_codex_setup_busy():
		speech_requested.emit("正在檢查 Codex Hook，完成前不需要再按一次。", 6.0)
		return
	if not _agent_controller.has_pending_codex_trust():
		speech_requested.emit(
			"尚未選擇要啟用哪一種 Codex 通知。請在下方找到你使用的程式"
			+ "（VS Code、ChatGPT 或終端機），把它的 Codex 開關打開。",
			8.0
		)
		return
	if not _agent_controller.recheck_pending_codex_trust():
		speech_requested.emit("無法開始檢查，請重新開啟桌寵後再試。", 6.0)
		return
	_apply_control_state()


func _show_codex_trust_dialog() -> void:
	if is_instance_valid(_trust_dialog):
		_trust_dialog.popup_centered(Vector2i(580, 330))


func _cancel_codex_hook_trust() -> void:
	if _agent_controller != null:
		_agent_controller.cancel_pending_codex_enable()
	_apply_control_state()


func _details_color(light: String, dark: String) -> Color:
	return Color(dark if _theme_mode == "dark" else light)
