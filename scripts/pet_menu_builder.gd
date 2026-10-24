class_name PetMenuBuilder
extends RefCounted

const LEVEL_ITEM_ID := 100
const FEED_ITEM_ID := 1
const WATER_ITEM_ID := 2
const PET_ITEM_ID := 3
const WORK_ITEM_ID := 4
const SLEEP_ITEM_ID := 5
const DETAILS_ITEM_ID := 6
const EXIT_ITEM_ID := 7
const RECOVER_ITEM_ID := 22
const REMINDER_VIEW_ALL_ITEM_ID := 8
const REMINDER_ITEM_ID_BASE := 1000


const CARE_ITEM_ACTIONS := {
	FEED_ITEM_ID: "feed",
	WATER_ITEM_ID: "water",
	PET_ITEM_ID: "pet",
	WORK_ITEM_ID: "work",
	SLEEP_ITEM_ID: "sleep",
}


static func populate(
	menu: PopupMenu,
	interaction_icon: Callable,
	interaction_label: Callable,
	care_cost_text: Callable
) -> void:
	menu.add_item("Lv.1  ·  20 金幣", LEVEL_ITEM_ID)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	for id: int in CARE_ITEM_ACTIONS:
		menu.add_item("", id)
	apply_care_labels(menu, interaction_icon, interaction_label, care_cost_text)
	menu.add_separator()
	menu.add_item("📊  開啟詳細面板", DETAILS_ITEM_ID)
	menu.add_item("🏠  找回桌寵", RECOVER_ITEM_ID)


## The single place that writes care item text, so menu prices always match
## PetState instead of a copy that can drift.
static func apply_care_labels(
	menu: PopupMenu,
	interaction_icon: Callable,
	interaction_label: Callable,
	care_cost_text: Callable
) -> void:
	if not is_instance_valid(menu):
		return
	for id: int in CARE_ITEM_ACTIONS:
		var index := menu.get_item_index(id)
		if index < 0:
			continue
		var action: String = CARE_ITEM_ACTIONS[id]
		var text := "%s  %s" % [interaction_icon.call(action), interaction_label.call(action)]
		var cost := String(care_cost_text.call(action))
		if not cost.is_empty():
			text += "（%s）" % cost
		menu.set_item_text(index, text)


static func populate_today_reminders(
	menu: PopupMenu, reminders: Array[Dictionary]
) -> void:
	if reminders.is_empty():
		return
	menu.add_separator()
	menu.add_item("今日待辦", REMINDER_VIEW_ALL_ITEM_ID)
	for index: int in mini(reminders.size(), 4):
		var reminder: Dictionary = reminders[index]
		var time := "整日" if bool(reminder.get("all_day", false)) else String(reminder.get("due_time", ""))
		menu.add_item(
			"  %s  %s" % [time, String(reminder.get("title", ""))],
			REMINDER_ITEM_ID_BASE + index
		)
	if reminders.size() > 4:
		menu.add_item("查看全部今日待辦", REMINDER_VIEW_ALL_ITEM_ID)


static func append_exit(menu: PopupMenu) -> void:
	menu.add_separator()
	menu.add_item("❌  儲存並離開", EXIT_ITEM_ID)
