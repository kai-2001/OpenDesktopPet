class_name CharacterTabController
extends RefCounted

# Runs the character tab: the pack list, importing, updating and deleting
# packs, choosing the active character and the Codex Pet eye mask editor. It
# lives for the whole session; the tab controls are bound while the details
# window exists. Switching the live character is left to the caller, which
# owns everything else that has to follow the new pack.

const CharacterEffectPreferencesScript = preload(
	"res://scripts/character_effect_preferences.gd"
)
const DEFAULT_CHARACTER_ID := "open_desktop_pet_default"

var tab_index := -1
var loaded := false
var entries: Array[Dictionary] = []
var mask_editing := false
var list: ItemList
var use_button: Button
var delete_button: Button
var _view
var _character_coordinator
var _pet: Node2D
var _state: Node
# (character_id: String, is_reload: bool) -> bool
var _apply_character: Callable
var _feedback: Label
var _mask_panel: Control
var _mask_hint: Control
var _mask_values: Control
var _mask_x_spin: SpinBox
var _mask_y_spin: SpinBox
var _mask_scale_spin: SpinBox
var _mask_header_state: Label
var _mask_header_chevron: Label
var _mask_apply_button: Button
var _mask_reset_button: Button
var _mask_feedback_dialog: AcceptDialog
var _import_dialog: FileDialog
var _update_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _pending_archive := ""
var _pending_mask_anchor := Vector2.ZERO
var _pending_mask_scale := 0.38


func configure(
	character_coordinator, pet: Node2D, state: Node, apply_character: Callable
) -> void:
	_character_coordinator = character_coordinator
	_pet = pet
	_state = state
	_apply_character = apply_character


func bind(view, refs: Dictionary) -> void:
	_view = view
	tab_index = int(refs["character_tab_index"])
	list = refs["character_list"] as ItemList
	use_button = refs["character_use_button"] as Button
	delete_button = refs["character_delete_button"] as Button
	_mask_panel = refs["mask_effect_panel"] as Control
	_mask_hint = refs["mask_effect_hint"] as Control
	_mask_values = refs["mask_effect_values"] as Control
	_mask_x_spin = refs["mask_effect_x"] as SpinBox
	_mask_y_spin = refs["mask_effect_y"] as SpinBox
	_mask_scale_spin = refs["mask_effect_scale"] as SpinBox
	_mask_header_state = refs["mask_effect_header_state"] as Label
	_mask_header_chevron = refs["mask_effect_header_chevron"] as Label
	_mask_apply_button = refs["mask_effect_apply_button"] as Button
	_mask_reset_button = refs["mask_effect_reset_button"] as Button
	_mask_feedback_dialog = refs["mask_effect_feedback_dialog"] as AcceptDialog
	refresh_mask_editor()
	_feedback = refs["character_feedback"] as Label
	_import_dialog = refs["character_import_dialog"] as FileDialog
	_update_dialog = refs["character_update_dialog"] as ConfirmationDialog
	_delete_dialog = refs["character_delete_dialog"] as ConfirmationDialog
	_view.character_selected.connect(_on_character_selected)
	_view.character_use_requested.connect(_use_selected_character)
	_view.character_delete_requested.connect(_confirm_delete_selected_character)
	_view.character_import_requested.connect(_open_import_dialog)
	_view.open_character_packs_folder_requested.connect(_open_packs_folder)
	_view.character_archive_selected.connect(_install_archive)
	_view.character_update_confirmed.connect(_install_pending_archive)
	_view.character_delete_confirmed.connect(_delete_selected_character)
	_view.mask_effect_changed.connect(_on_mask_effect_changed)
	_view.mask_effect_toggle_requested.connect(_on_mask_effect_toggle_requested)
	_view.mask_effect_apply_requested.connect(_on_mask_effect_apply_requested)
	_view.mask_effect_reset_requested.connect(_on_mask_effect_reset_requested)


func unbind() -> void:
	_view = null
	list = null
	_feedback = null
	use_button = null
	delete_button = null
	_mask_panel = null
	_mask_hint = null
	_mask_values = null
	_mask_x_spin = null
	_mask_y_spin = null
	_mask_scale_spin = null
	_mask_header_state = null
	_mask_header_chevron = null
	_mask_apply_button = null
	_mask_reset_button = null
	_mask_feedback_dialog = null
	_import_dialog = null
	_update_dialog = null
	_delete_dialog = null
	_pending_archive = ""
	entries.clear()
	tab_index = -1
	loaded = false


func on_tab_changed(selected_tab: int) -> void:
	if selected_tab != tab_index and mask_editing:
		cancel_mask_editing()
	if selected_tab != tab_index or loaded:
		return
	refresh_list()


func set_feedback(text: String) -> void:
	_feedback.text = text


func refresh_list(message := "") -> void:
	if not is_instance_valid(list):
		return
	loaded = true
	entries.clear()
	list.clear()
	entries.append({
		"id": DEFAULT_CHARACTER_ID,
		"name": "預設桌寵",
		"version": "內建",
		"installed": false,
		"builtin": true,
	})
	entries.append_array(_character_coordinator.list_entries().slice(1))
	var active_id: String = _pet.get_character_id()
	var active_found := false
	for entry: Dictionary in entries:
		if String(entry.id) == active_id:
			active_found = true
			break
	if not active_found:
		entries.append({
			"id": active_id,
			"name": _pet.get_character_name(),
			"version": _pet.get_character_version(),
			"installed": false,
			"builtin": true,
		})
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var active_marker := " 〔使用中〕" if String(entry.id) == active_id else ""
		list.add_item("%s  v%s%s\nID: %s" % [
			String(entry.name),
			String(entry.version),
			active_marker,
			String(entry.id),
		])
		if String(entry.id) == active_id:
			list.select(index)
	if not message.is_empty():
		_feedback.text = message
	update_buttons()
	refresh_mask_editor()


func update_buttons() -> void:
	var entry := _selected_entry()
	var has_entry := not entry.is_empty()
	if is_instance_valid(use_button):
		var is_active: bool = has_entry \
			and String(entry.id) == _pet.get_character_id()
		use_button.text = "重新載入角色" if is_active \
			else "使用選取角色"
		use_button.disabled = not has_entry
	if is_instance_valid(delete_button):
		delete_button.disabled = not has_entry \
			or not bool(entry.get("installed", false))


func refresh_mask_editor() -> void:
	if not is_instance_valid(_mask_x_spin) \
			or not is_instance_valid(_mask_header_state):
		return
	var enabled: bool = bool(_pet.is_codex_pet())
	_mask_panel.visible = enabled
	if not enabled:
		mask_editing = false
		_pet.set_effect_preview("mask", false)
		return
	_load_mask_editor_values()
	_set_mask_editing(false)


func cancel_mask_editing() -> void:
	if not mask_editing:
		_pet.set_effect_preview("mask", false)
		return
	_pet.reload_effect_overrides()
	_load_mask_editor_values()
	_set_mask_editing(false)


func _on_character_selected(_index: int) -> void:
	update_buttons()


func _load_mask_editor_values() -> void:
	var definition: Dictionary = _pet.effect_editor_definition("mask")
	var raw_anchor: Variant = definition.get("anchor", [0.0, -20.0])
	var anchor := Vector2.ZERO
	if raw_anchor is Array and raw_anchor.size() >= 2:
		anchor = Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
	var scale := float(definition.get("scale", 0.38))
	_pending_mask_anchor = anchor
	_pending_mask_scale = scale
	_mask_x_spin.set_value_no_signal(anchor.x)
	_mask_y_spin.set_value_no_signal(anchor.y)
	_mask_scale_spin.set_value_no_signal(scale)


func _set_mask_editing(editing: bool) -> void:
	mask_editing = editing
	_mask_hint.visible = editing
	_mask_values.visible = editing
	_mask_x_spin.editable = editing
	_mask_y_spin.editable = editing
	_mask_scale_spin.editable = editing
	_view.configure_mask_effect_header(
		_mask_header_state, _mask_header_chevron, editing
	)
	_mask_apply_button.visible = editing
	_mask_reset_button.disabled = not editing
	_pet.set_effect_preview("mask", editing)


func _on_mask_effect_changed(anchor: Vector2, scale: float) -> void:
	if not _pet.is_codex_pet():
		return
	if not mask_editing:
		return
	_pending_mask_anchor = anchor
	_pending_mask_scale = clampf(scale, 0.05, 2.0)
	_pet.apply_effect_override("mask", _pending_mask_definition())


func _on_mask_effect_toggle_requested() -> void:
	if not _pet.is_codex_pet():
		return
	if not mask_editing:
		_set_mask_editing(true)
		return
	cancel_mask_editing()


func _on_mask_effect_apply_requested() -> void:
	if not _pet.is_codex_pet() or not mask_editing:
		return
	var saved := CharacterEffectPreferencesScript.set_effect(
		_pet.get_character_id(), "mask", _pending_mask_definition()
	)
	if saved:
		_pet.apply_effect_override("mask", _pending_mask_definition())
		_set_mask_editing(false)
		_show_mask_feedback("眼罩位置與大小已保存。")
	else:
		_show_mask_feedback("保存失敗，請稍後再試。")


func _on_mask_effect_reset_requested() -> void:
	if not _pet.is_codex_pet():
		return
	CharacterEffectPreferencesScript.clear_effect(
		_pet.get_character_id(), "mask"
	)
	_pet.apply_effect_override("mask", {})
	_load_mask_editor_values()
	_set_mask_editing(true)


func _show_mask_feedback(message: String) -> void:
	if not is_instance_valid(_mask_feedback_dialog):
		return
	_mask_feedback_dialog.dialog_text = message
	_mask_feedback_dialog.popup_centered()


func _pending_mask_definition() -> Dictionary:
	return {
		"anchor": [_pending_mask_anchor.x, _pending_mask_anchor.y],
		"scale": _pending_mask_scale,
	}


func _selected_entry() -> Dictionary:
	if not is_instance_valid(list):
		return {}
	var selected := list.get_selected_items()
	if selected.is_empty():
		return {}
	var index := int(selected[0])
	if index < 0 or index >= entries.size():
		return {}
	return entries[index]


func _open_import_dialog() -> void:
	cancel_mask_editing()
	if is_instance_valid(_import_dialog):
		_import_dialog.popup_centered_ratio(0.75)


func _install_archive(path: String) -> void:
	var inspection: Dictionary = _character_coordinator.inspect_archive(path)
	if not bool(inspection.get("ok", false)):
		_feedback.text = "匯入失敗：%s" % String(inspection.get(
			"message", "未知錯誤"
		))
		return
	for entry: Dictionary in _character_coordinator.list_entries():
		if String(entry.id) != String(inspection.id):
			continue
		_pending_archive = path
		_update_dialog.dialog_text = (
			"已安裝「%s」v%s。\n準備匯入同一角色ID的v%s。\n\n"
			+ "更新會替換角色圖片與設定，但保留遊戲進度。"
		) % [
			String(entry.name),
			String(entry.version),
			String(inspection.version),
		]
		_update_dialog.popup_centered()
		return
	_install_archive_now(path)


func _install_pending_archive() -> void:
	if _pending_archive.is_empty():
		return
	var path := _pending_archive
	_pending_archive = ""
	_install_archive_now(path)


func _install_archive_now(path: String) -> void:
	_feedback.text = "正在驗證並安裝角色包…"
	var result: Dictionary = _character_coordinator.install_archive(path)
	if not bool(result.get("ok", false)):
		_feedback.text = "匯入失敗：%s" % String(result.get(
			"message", "未知錯誤"
		))
		return
	var verb := "更新" if bool(result.get("updated", false)) else "安裝"
	refresh_list("已%s「%s」v%s；角色進度保持不變。" % [
		verb,
		String(result.name),
		String(result.version),
	])


func _use_selected_character() -> void:
	cancel_mask_editing()
	var entry := _selected_entry()
	if entry.is_empty():
		return
	var is_reload: bool = String(entry.id) == _pet.get_character_id()
	_state.save_state()
	_apply_character.call(String(entry.id), is_reload)


func _confirm_delete_selected_character() -> void:
	cancel_mask_editing()
	var entry := _selected_entry()
	if entry.is_empty() or not bool(entry.get("installed", false)):
		return
	_delete_dialog.dialog_text = (
		"確定要刪除「%s」嗎？\n\n角色包會被移除，但遊戲進度會保留。"
		% String(entry.name)
	)
	_delete_dialog.popup_centered()


func _delete_selected_character() -> void:
	var entry := _selected_entry()
	if entry.is_empty() or not bool(entry.get("installed", false)):
		return
	var character_id := String(entry.id)
	var was_active: bool = character_id == _pet.get_character_id()
	if was_active:
		_character_coordinator.save_selected_character_id(DEFAULT_CHARACTER_ID)
		_state.save_state()
	var result: Dictionary = _character_coordinator.remove_pack(character_id)
	if not bool(result.get("ok", false)):
		_feedback.text = "刪除失敗：%s" % String(result.get(
			"message", "未知錯誤"
		))
		return
	refresh_list("已刪除角色包；遊戲進度仍保留。")
	if was_active:
		_apply_character.call(DEFAULT_CHARACTER_ID, false)


func _open_packs_folder() -> void:
	cancel_mask_editing()
	if _character_coordinator.ensure_packs_root() != OK:
		_feedback.text = "無法建立角色包資料夾。"
		return
	OS.shell_open(ProjectSettings.globalize_path(
		_character_coordinator.packs_root()
	))
