class_name TaskReminderPresentationCoordinator
extends RefCounted

const TaskReminderBadgeStateScript = preload("res://scripts/task_reminder_badge_state.gd")

var reminder_coordinator


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
	if today_items.is_empty():
		return ""
	var lines: Array[String] = ["今天有 %d 件待辦" % today_items.size()]
	for reminder: Dictionary in today_items.slice(0, mini(today_items.size(), 2)):
		lines.append("・%s" % _display_title(reminder))
	return "\n".join(lines)


func due_message(reminder: Dictionary) -> String:
	if reminder.is_empty() or bool(reminder.get("all_day", false)):
		return ""
	var title := String(reminder.get("title", "")).strip_edges()
	var due_time := String(reminder.get("due_time", "")).strip_edges()
	if title.is_empty() or due_time.is_empty():
		return ""
	return "・%s %s" % [due_time, title]


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
