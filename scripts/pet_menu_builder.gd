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


static func populate(
	menu: PopupMenu,
	interaction_icon: Callable,
	interaction_label: Callable
) -> void:
	menu.add_item("Lv.1  ·  20 金幣", LEVEL_ITEM_ID)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	menu.add_item("%s  %s（2 金幣）" % [
		interaction_icon.call("feed"), interaction_label.call("feed")
	], FEED_ITEM_ID)
	menu.add_item("%s  %s（1 金幣）" % [
		interaction_icon.call("water"), interaction_label.call("water")
	], WATER_ITEM_ID)
	menu.add_item("%s  %s" % [
		interaction_icon.call("pet"), interaction_label.call("pet")
	], PET_ITEM_ID)
	menu.add_item("%s  %s（賺取金幣）" % [
		interaction_icon.call("work"), interaction_label.call("work")
	], WORK_ITEM_ID)
	menu.add_item("%s  %s" % [
		interaction_icon.call("sleep"), interaction_label.call("sleep")
	], SLEEP_ITEM_ID)
	menu.add_separator()
	menu.add_item("📊  開啟詳細面板", DETAILS_ITEM_ID)
	menu.add_item("🏠  找回桌寵", RECOVER_ITEM_ID)
	menu.add_separator()
	menu.add_item("❌  儲存並離開", EXIT_ITEM_ID)
