class_name TaskReminderPresentationCoordinator
extends RefCounted

const TaskReminderBadgeStateScript = preload("res://scripts/task_reminder_badge_state.gd")
const MAX_MESSAGE_ITEMS := 3

var reminder_coordinator
var _deferred_due_ids: Array[String] = []


func configure(value) -> void:
	reminder_coordinator = value


func badge_state() -> TaskReminderBadgeState:
	if reminder_coordinator == null:
		return TaskReminderBadgeStateScript.new()
	var today_count: int = reminder_coordinator.get_due_open_today_reminders().size()
	var overdue_count: int = reminder_coordinator.get_overdue_reminders().size()
	var label := _count_label(today_count)
	var tooltip := _tooltip_text(today_count, overdue_count)
	var attention_label := label if today_count > 0 else "!"
	var attention_tooltip := _tooltip_text(today_count, overdue_count)
	if overdue_count <= 0:
		attention_label = ""
		attention_tooltip = ""
	return TaskReminderBadgeStateScript.new(
		today_count > 0,
		label,
		tooltip,
		attention_label,
		attention_tooltip
	)


func startup_message() -> String:
	if reminder_coordinator == null:
		return ""
	var today_items: Array[Dictionary] = reminder_coordinator.get_due_open_today_reminders()
	var overdue_count: int = reminder_coordinator.get_overdue_reminders().size()
	var lines: Array[String] = []
	if not today_items.is_empty():
		lines.append("今天有 %d 件待辦" % today_items.size())
		for reminder: Dictionary in today_items.slice(0, mini(today_items.size(), 2)):
			lines.append("・%s" % _display_title(reminder))
	if overdue_count > 0:
		lines.append(
			"另有 %d 件逾期" % overdue_count if not lines.is_empty()
			else "有 %d 件逾期待辦" % overdue_count
		)
	return "\n".join(lines)


# One bubble for every timed reminder that became due together, so none hides
# another. Items from another day show their date.
func due_message(reminders: Array[Dictionary]) -> String:
	var timed: Array[Dictionary] = []
	for reminder: Dictionary in reminders:
		if not bool(reminder.get("all_day", false)) \
				and not String(reminder.get("title", "")).strip_edges().is_empty() \
				and not String(reminder.get("due_time", "")).strip_edges().is_empty():
			timed.append(reminder)
	var lines: Array[String] = []
	for reminder: Dictionary in timed.slice(0, mini(timed.size(), MAX_MESSAGE_ITEMS)):
		lines.append("・%s%s %s" % [
			_date_prefix(reminder),
			String(reminder.get("due_time", "")).strip_edges(),
			String(reminder.get("title", "")).strip_edges(),
		])
	if timed.size() > MAX_MESSAGE_ITEMS:
		lines.append("・另外 %d 件" % (timed.size() - MAX_MESSAGE_ITEMS))
	return "\n".join(lines)


func _date_prefix(reminder: Dictionary) -> String:
	var date := String(reminder.get("due_date", ""))
	if reminder_coordinator == null or date == reminder_coordinator.today() or date.length() != 10:
		return ""
	return "%d/%d " % [int(date.substr(5, 2)), int(date.right(2))]


func defer_due(reminders: Array[Dictionary]) -> void:
	for reminder: Dictionary in reminders:
		var id := String(reminder.get("id", ""))
		if not id.is_empty() and id not in _deferred_due_ids:
			_deferred_due_ids.append(id)


# Deferred reminders as they are now; completed or deleted ones are dropped.
func take_deferred_due() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _deferred_due_ids:
		var reminder: Dictionary = reminder_coordinator.get_reminder(id)
		if not reminder.is_empty() and String(reminder.get("status", "todo")) != "done":
			result.append(reminder)
	_deferred_due_ids.clear()
	return result


func badge_position(
	visual_bounds: Rect2, viewport_size: Vector2, badge_size: Vector2
) -> Vector2:
	return Vector2(
		clampf(
			visual_bounds.end.x - badge_size.x * 0.6,
			6.0,
			viewport_size.x - badge_size.x - 6.0
		),
		clampf(
			visual_bounds.position.y + 6.0,
			6.0,
			viewport_size.y - badge_size.y - 6.0
		)
	)


func _count_label(count: int) -> String:
	return "9+" if count > 9 else str(maxi(count, 0))


func _tooltip_text(today_count: int, overdue_count: int) -> String:
	if today_count > 0 and overdue_count > 0:
		return "今日待辦 %d 件，逾期 %d 件\n點擊開啟待辦頁" % [
			today_count, overdue_count
		]
	if today_count > 0:
		return "今日待辦 %d 件\n點擊開啟待辦頁" % today_count
	return "逾期待辦 %d 件\n點擊開啟待辦頁" % overdue_count


func _display_title(reminder: Dictionary) -> String:
	var time := "整日" if bool(reminder.get("all_day", false)) else String(reminder.get("due_time", ""))
	return "%s %s" % [time, String(reminder.get("title", ""))]
