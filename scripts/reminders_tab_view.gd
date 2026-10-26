class_name RemindersTabView
extends "res://scripts/details_tab_view.gd"

const TaskReminderPanelScript = preload("res://scripts/task_reminder_panel.gd")

var _task_reminder_panel


func build(tabs: TabContainer, reminder_coordinator) -> Dictionary:
	var reminders_scroll := ScrollContainer.new()
	reminders_scroll.name = "待辦"
	reminders_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(reminders_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	reminders_scroll.add_child(margin)

	_task_reminder_panel = TaskReminderPanelScript.new()
	_task_reminder_panel.configure(reminder_coordinator, theme_mode)
	margin.add_child(_task_reminder_panel)
	return {
		"reminder_tab_index": reminders_scroll.get_index(),
		"reminder_panel": _task_reminder_panel,
	}


func focus_reminder(reminder_id: String) -> void:
	if is_instance_valid(_task_reminder_panel):
		_task_reminder_panel.focus_reminder(reminder_id)


func start_new_reminder() -> void:
	if is_instance_valid(_task_reminder_panel):
		_task_reminder_panel.show_new_form()
