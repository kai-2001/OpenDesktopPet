class_name PetState
extends Node

signal changed(snapshot: Dictionary)
signal message_requested(text: String)
signal action_requested(action: String)

const SAVE_PATH := "user://save_v2.json"
const SAVE_VERSION := 1

var data: Dictionary = {
	"save_version": SAVE_VERSION,
	"hunger": 80.0,
	"thirst": 80.0,
	"energy": 80.0,
	"mood": 72.0,
	"coins": 20,
	"level": 1,
	"xp": 0,
	"care": 0,
	"last_seen": 0,
}

var _decay_accumulator := 0.0


func _ready() -> void:
	load_state()
	_apply_offline_progress()
	emit_changed()


func _process(delta: float) -> void:
	_decay_accumulator += delta
	if _decay_accumulator >= 30.0:
		_decay_accumulator -= 30.0
		data.hunger = _limit(data.hunger - 3.0)
		data.thirst = _limit(data.thirst - 4.0)
		data.energy = _limit(data.energy - 2.0)
		if data.hunger < 25.0 or data.thirst < 25.0:
			data.mood = _limit(data.mood - 4.0)
		save_state()
		emit_changed()


func pet() -> void:
	data.mood = _limit(data.mood + 10.0)
	data.care += 1
	_add_xp(1)
	action_requested.emit("clap")
	message_requested.emit("嘿嘿！再摸一下！")
	_commit()


func feed() -> void:
	if data.coins < 2:
		message_requested.emit("需要 2 枚金幣，先去工作吧。")
		return
	data.coins -= 2
	data.hunger = _limit(data.hunger + 28.0)
	data.mood = _limit(data.mood + 5.0)
	data.care += 1
	_add_xp(2)
	action_requested.emit("eat")
	message_requested.emit("好吃！一下就吃光了！")
	_commit()


func water() -> void:
	if data.coins < 1:
		message_requested.emit("需要 1 枚金幣，先去工作吧。")
		return
	data.coins -= 1
	data.thirst = _limit(data.thirst + 30.0)
	data.mood = _limit(data.mood + 2.0)
	data.care += 1
	_add_xp(1)
	action_requested.emit("drink")
	message_requested.emit("咕嚕咕嚕，好清爽！")
	_commit()


func sleep() -> void:
	data.energy = _limit(data.energy + 35.0)
	data.mood = _limit(data.mood + 4.0)
	action_requested.emit("sleep")
	message_requested.emit("呼嚕……睡成一顆麻糬。")
	_commit()


func work() -> void:
	if data.energy < 15.0:
		message_requested.emit("太累了，先睡一下吧。")
		return
	data.energy = _limit(data.energy - 15.0)
	data.hunger = _limit(data.hunger - 5.0)
	data.coins += 7
	_add_xp(5)
	action_requested.emit("roll")
	message_requested.emit("滾去工作！賺到 7 枚金幣。")
	_commit()


func save_state() -> void:
	data.last_seen = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to open save file: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("Save data is invalid; defaults are used.")
		return
	for key: String in data.keys():
		if parsed.has(key):
			data[key] = parsed[key]


func emit_changed() -> void:
	changed.emit(data.duplicate(true))


func _commit() -> void:
	save_state()
	emit_changed()


func _add_xp(amount: int) -> void:
	data.xp += amount
	while data.xp >= data.level * 20:
		data.xp -= data.level * 20
		data.level += 1
		data.mood = _limit(data.mood + 12.0)
		message_requested.emit("升級了！現在是第 %d 級。" % data.level)


func _apply_offline_progress() -> void:
	var now := int(Time.get_unix_time_from_system())
	var last_seen := int(data.get("last_seen", now))
	if last_seen <= 0:
		data.last_seen = now
		return
	var intervals: int = mini(int((now - last_seen) / 1800.0), 48)
	if intervals <= 0:
		return
	data.hunger = _limit(data.hunger - intervals * 2.0)
	data.thirst = _limit(data.thirst - intervals * 2.5)
	data.energy = _limit(data.energy - intervals * 1.0)
	if data.hunger < 25.0 or data.thirst < 25.0:
		data.mood = _limit(data.mood - intervals * 1.5)


func _limit(value: float) -> float:
	return clampf(value, 0.0, 100.0)
