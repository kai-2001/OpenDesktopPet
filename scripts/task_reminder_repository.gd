class_name TaskReminderRepository
extends RefCounted

const SAVE_PATH := "user://task_reminders.json"
const SAVE_VERSION := 1

var save_path := SAVE_PATH
var _reminders: Array[Dictionary] = []


func load_data() -> void:
	_reminders.clear()
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open task reminder file: %s" % FileAccess.get_open_error())
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("Task reminder data is invalid; defaults are used.")
		return
	var raw_reminders: Variant = parsed.get("reminders", [])
	if not raw_reminders is Array:
		return
	for raw_reminder: Variant in raw_reminders:
		if not raw_reminder is Dictionary:
			continue
		var normalized := _normalize(raw_reminder)
		if not normalized.is_empty():
			_reminders.append(normalized)


func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reminder: Dictionary in _reminders:
		result.append(reminder.duplicate(true))
	return result


func create(
	title: String,
	due_date: String,
	due_time: String,
	all_day: bool,
	status: String = "todo"
) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var reminder := _normalize({
		"id": "%d-%d" % [now, Time.get_ticks_usec()],
		"title": title,
		"due_date": due_date,
		"due_time": due_time if not all_day else "",
		"all_day": all_day,
		"status": status,
		"created_at": now,
		"updated_at": now,
	})
	if reminder.is_empty():
		return {}
	_reminders.append(reminder)
	return reminder.duplicate(true)


func update(id: String, values: Dictionary) -> Dictionary:
	for index: int in _reminders.size():
		if String(_reminders[index].get("id", "")) != id:
			continue
		var updated := _reminders[index].duplicate(true)
		for key: String in [
			"title", "due_date", "due_time", "all_day", "status"
		]:
			if values.has(key):
				updated[key] = values[key]
		updated["updated_at"] = int(Time.get_unix_time_from_system())
		var normalized := _normalize(updated)
		if normalized.is_empty():
			return {}
		_reminders[index] = normalized
		return normalized.duplicate(true)
	return {}


func remove(id: String) -> bool:
	for index: int in _reminders.size():
		if String(_reminders[index].get("id", "")) != id:
			continue
		_reminders.remove_at(index)
		return true
	return false


func save() -> bool:
	var document := {
		"version": SAVE_VERSION,
		"reminders": _reminders,
	}
	var temporary_path := save_path + ".tmp"
	var backup_path := save_path + ".backup"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_path.get_base_dir())
	)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to open task reminder save file: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	file.close()

	var verification := FileAccess.open(temporary_path, FileAccess.READ)
	if verification == null or JSON.parse_string(verification.get_as_text()) is not Dictionary:
		push_warning("Task reminder save verification failed.")
		if verification != null:
			verification.close()
		return false
	verification.close()

	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(save_path):
		if DirAccess.rename_absolute(absolute_save, absolute_backup) != OK:
			push_warning("Unable to rotate the previous task reminder save file.")
			return false
	if DirAccess.rename_absolute(absolute_temporary, absolute_save) != OK:
		push_warning("Unable to install the task reminder save file.")
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_save)
		return false
	return true


func _normalize(raw: Dictionary) -> Dictionary:
	var id := String(raw.get("id", "")).strip_edges()
	var title := String(raw.get("title", "")).strip_edges()
	var due_date := String(raw.get("due_date", "")).strip_edges()
	if id.is_empty() or title.is_empty() or due_date.is_empty():
		return {}
	var status := String(raw.get("status", "todo"))
	# The UI has one binary task state. Preserve legacy closed items as done,
	# and migrate the obsolete in-progress state back to pending.
	status = "done" if status in ["done", "cancelled"] else "todo"
	var all_day := bool(raw.get("all_day", false))
	var due_time := String(raw.get("due_time", "")).strip_edges()
	if all_day:
		due_time = ""
	return {
		"id": id,
		"title": title,
		"due_date": due_date,
		"due_time": due_time,
		"all_day": all_day,
		"status": status,
		"created_at": int(raw.get("created_at", 0)),
		"updated_at": int(raw.get("updated_at", 0)),
	}
