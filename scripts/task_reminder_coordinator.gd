class_name TaskReminderCoordinator
extends RefCounted

const TaskReminderRepositoryScript = preload("res://scripts/task_reminder_repository.gd")
const POLL_INTERVAL_SECONDS := 15.0

signal reminders_changed
# Every reminder that became due in one check, so they can share one message.
signal reminders_due(reminders: Array[Dictionary])

var repository = TaskReminderRepositoryScript.new()
var _poll_accumulator := 0.0
var _notified_due_keys: Dictionary = {}
var _last_date := ""


func initialize() -> void:
	repository.load_data()
	_last_date = _today()
	_prime_current_due_items()


func process(delta: float) -> void:
	_poll_accumulator += delta
	if _poll_accumulator < POLL_INTERVAL_SECONDS:
		return
	_poll_accumulator = fmod(_poll_accumulator, POLL_INTERVAL_SECONDS)
	# "Today" lists, the badge and the menu all depend on the date.
	if _today() != _last_date:
		_last_date = _today()
		reminders_changed.emit()
	_check_due_items()


func today() -> String:
	return _today()


func get_all_reminders() -> Array[Dictionary]:
	var reminders := repository.all()
	reminders.sort_custom(Callable(self, "_sort_reminders"))
	return reminders


func get_today_reminders() -> Array[Dictionary]:
	return _filter_by_date(get_all_reminders(), _today())


func get_open_today_reminders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reminder: Dictionary in get_today_reminders():
		if _is_open(reminder):
			result.append(reminder)
	return result


func get_due_open_today_reminders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reminder: Dictionary in get_today_reminders():
		if _is_open(reminder) and _is_due_now(reminder):
			result.append(reminder)
	return result


func get_upcoming_reminders(limit := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var today := _today()
	for reminder: Dictionary in get_all_reminders():
		if not _is_open(reminder):
			continue
		if String(reminder.get("due_date", "")) <= today:
			continue
		result.append(reminder)
		if limit >= 0 and result.size() >= limit:
			break
	return result


func get_overdue_reminders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var today := _today()
	for reminder: Dictionary in get_all_reminders():
		if _is_open(reminder) and String(reminder.get("due_date", "")) < today:
			result.append(reminder)
	return result


func get_completed_reminders(limit := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var reminders := get_all_reminders()
	reminders.reverse()
	for reminder: Dictionary in reminders:
		if _is_open(reminder):
			continue
		result.append(reminder)
		if limit >= 0 and result.size() >= limit:
			break
	return result


func create_reminder(
	title: String,
	due_date: String,
	due_time: String,
	all_day: bool,
	status := "todo"
) -> Dictionary:
	var previous := repository.snapshot()
	var reminder := repository.create(
		title, due_date, due_time, all_day, status
	)
	if reminder.is_empty():
		return {}
	if not repository.save():
		repository.restore(previous)
		return {}
	reminders_changed.emit()
	_check_due_items()
	return reminder


func update_reminder(id: String, values: Dictionary) -> Dictionary:
	var previous := repository.snapshot()
	var before := get_reminder(id)
	var reminder := repository.update(id, values)
	if reminder.is_empty():
		return {}
	if not repository.save():
		repository.restore(previous)
		return {}
	# Only a new date or time is reminded again; a title edit or reopening a
	# completed item keeps its earlier reminder.
	if _due_key(before) != _due_key(reminder):
		_notified_due_keys.erase(_due_key(reminder))
	reminders_changed.emit()
	_check_due_items()
	return reminder


func set_status(id: String, status: String) -> Dictionary:
	return update_reminder(id, {"status": status})


func delete_reminder(id: String) -> bool:
	var previous := repository.snapshot()
	if not repository.remove(id):
		return false
	if not repository.save():
		repository.restore(previous)
		return false
	_notified_due_keys.erase(id)
	reminders_changed.emit()
	return true


func get_reminder(id: String) -> Dictionary:
	for reminder: Dictionary in repository.all():
		if String(reminder.get("id", "")) == id:
			return reminder
	return {}


# The startup message covers everything already due, overdue items included,
# so none of them is reminded again a moment later.
func _prime_current_due_items() -> void:
	for reminder: Dictionary in get_all_reminders():
		if _is_open(reminder) and _is_due_now(reminder):
			_notified_due_keys[_due_key(reminder)] = true


func _check_due_items() -> void:
	var due: Array[Dictionary] = []
	for reminder: Dictionary in get_all_reminders():
		if not _is_open(reminder) or not _is_due_now(reminder):
			continue
		var key := _due_key(reminder)
		if _notified_due_keys.has(key):
			continue
		_notified_due_keys[key] = true
		due.append(reminder)
	if not due.is_empty():
		reminders_due.emit(due)


func _is_due_now(reminder: Dictionary) -> bool:
	var due_date := String(reminder.get("due_date", ""))
	var today := _today()
	if due_date < today:
		return true
	if due_date > today:
		return false
	if bool(reminder.get("all_day", false)):
		return true
	var due_time := String(reminder.get("due_time", ""))
	return due_time.is_empty() or due_time <= _current_time()


func _is_open(reminder: Dictionary) -> bool:
	return String(reminder.get("status", "todo")) != "done"


func _filter_by_date(reminders: Array[Dictionary], date: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reminder: Dictionary in reminders:
		if String(reminder.get("due_date", "")) == date:
			result.append(reminder)
	return result


func _sort_reminders(left: Dictionary, right: Dictionary) -> bool:
	var left_key := "%s|%s|%s" % [
		String(left.get("due_date", "")),
		String(left.get("due_time", "99:99")) if not bool(left.get("all_day", false)) else "00:00",
		String(left.get("title", "")),
	]
	var right_key := "%s|%s|%s" % [
		String(right.get("due_date", "")),
		String(right.get("due_time", "99:99")) if not bool(right.get("all_day", false)) else "00:00",
		String(right.get("title", "")),
	]
	return left_key < right_key


func _due_key(reminder: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(reminder.get("id", "")),
		String(reminder.get("due_date", "")),
		String(reminder.get("due_time", "")),
	]


func _today() -> String:
	return Time.get_date_string_from_system(false)


func _current_time() -> String:
	var now := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]
