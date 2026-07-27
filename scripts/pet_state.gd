class_name PetState
extends Node

signal changed(snapshot: Dictionary)
signal message_requested(text: String)
signal action_requested(action: String)

const SAVE_PATH := "user://save_v2.json"
const SAVE_VERSION := 2
const DECAY_INTERVAL_SECONDS := 600
const PET_REWARD_COOLDOWN_SECONDS := 600
const WISH_DURATION_SECONDS := 900
const FIRST_WISH_MIN_SECONDS := 120
const FIRST_WISH_MAX_SECONDS := 300
const WISH_MIN_SECONDS := 1200
const WISH_MAX_SECONDS := 2400

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
	"affection": 0,
	"last_seen": 0,
	"wish_action": "",
	"wish_expires_at": 0,
	"next_wish_at": 0,
	"wish_intro_seen": false,
	"last_pet_reward_at": 0,
}

var _decay_accumulator := 0.0
var _wish_accumulator := 0.0
var _action_busy := false


func _ready() -> void:
	load_state()
	_apply_offline_progress()
	_ensure_wish_schedule()
	emit_changed()


func _process(delta: float) -> void:
	_decay_accumulator += delta
	_wish_accumulator += delta
	if _decay_accumulator >= DECAY_INTERVAL_SECONDS:
		_decay_accumulator -= DECAY_INTERVAL_SECONDS
		data.hunger = _limit(data.hunger - 2.0)
		data.thirst = _limit(data.thirst - 3.0)
		if data.hunger < 25.0 or data.thirst < 25.0:
			data.mood = _limit(data.mood - 2.0)
		_commit()
	if _wish_accumulator >= 1.0:
		_wish_accumulator -= 1.0
		_update_wish()


func pet() -> void:
	if not _begin_action("pet"):
		return
	await get_tree().create_timer(1.0).timeout
	var now := _now()
	var rewarded := now >= int(data.last_pet_reward_at) + PET_REWARD_COOLDOWN_SECONDS
	if rewarded:
		data.last_pet_reward_at = now
		data.mood = _limit(data.mood + 8.0)
		data.care += 1
		_add_affection(1)
		_add_xp(1)
	else:
		data.mood = _limit(data.mood + 1.0)
	var message := "嘿嘿！再摸一下！" if rewarded else "很舒服，不過先讓我休息一下～"
	message += _complete_wish("pet")
	_finish_action(message)


func feed() -> void:
	if _action_busy:
		message_requested.emit("先等目前的動作完成～")
		return
	if data.hunger >= 92.0:
		message_requested.emit("肚子已經很飽了，晚點再吃吧。")
		return
	if data.coins < 2:
		message_requested.emit("需要 2 枚金幣，先去工作吧。")
		return
	if not _begin_action("eat"):
		return
	await get_tree().create_timer(1.7).timeout
	data.coins -= 2
	data.hunger = _limit(data.hunger + 28.0)
	data.mood = _limit(data.mood + 4.0)
	data.care += 1
	_add_affection(1)
	_add_xp(2)
	_finish_action("好吃！一下就吃光了！" + _complete_wish("feed"))


func water() -> void:
	if _action_busy:
		message_requested.emit("先等目前的動作完成～")
		return
	if data.thirst >= 92.0:
		message_requested.emit("現在不渴，晚點再喝吧。")
		return
	if data.coins < 1:
		message_requested.emit("需要 1 枚金幣，先去工作吧。")
		return
	if not _begin_action("drink"):
		return
	await get_tree().create_timer(1.7).timeout
	data.coins -= 1
	data.thirst = _limit(data.thirst + 30.0)
	data.mood = _limit(data.mood + 2.0)
	data.care += 1
	_add_affection(1)
	_add_xp(1)
	_finish_action("咕嚕咕嚕，好清爽！" + _complete_wish("water"))


func sleep() -> void:
	if not _begin_action("sleep"):
		return
	await get_tree().create_timer(2.75).timeout
	var recovered: bool = _apply_sleep_result()
	var message := "呼嚕……睡成一顆麻糬。" if recovered else "雖然很有精神，還是舒服地睡了一覺。"
	_finish_action(message + _complete_wish("sleep"))


func work() -> void:
	if _action_busy:
		message_requested.emit("先等目前的動作完成～")
		return
	if data.energy < 18.0:
		message_requested.emit("太累了，先睡一下吧。")
		return
	if data.hunger < 8.0:
		message_requested.emit("肚子太餓了，吃飽再工作吧。")
		return
	if data.thirst < 10.0:
		message_requested.emit("太渴了，喝水後再工作吧。")
		return
	if not _begin_action("work"):
		return
	await get_tree().create_timer(0.9).timeout
	_apply_work_result()
	_finish_action("工作完成！賺到 7 枚金幣。" + _complete_wish("work"))


func _apply_sleep_result() -> bool:
	var recovered: bool = float(data.energy) < 100.0
	data.energy = _limit(data.energy + 35.0)
	data.mood = _limit(data.mood + 4.0)
	return recovered


func _apply_work_result() -> void:
	data.energy = _limit(data.energy - 18.0)
	data.hunger = _limit(data.hunger - 8.0)
	data.thirst = _limit(data.thirst - 10.0)
	data.coins += 7
	_add_xp(5)


func is_action_busy() -> bool:
	return _action_busy


func wish_text() -> String:
	var remaining := maxi(int(data.wish_expires_at) - _now(), 0)
	var minutes := maxi(ceili(remaining / 60.0), 1)
	match String(data.wish_action):
		"feed":
			return "想吃東西（剩餘約 %d 分鐘）" % minutes
		"water":
			return "想喝水（剩餘約 %d 分鐘）" % minutes
		"pet":
			return "想被摸摸（剩餘約 %d 分鐘）" % minutes
		"sleep":
			return "想睡一下（剩餘約 %d 分鐘）" % minutes
		"work":
			return "想出去活動（剩餘約 %d 分鐘）" % minutes
		_:
			return "目前沒有願望"


func _begin_action(action: String) -> bool:
	if _action_busy:
		message_requested.emit("先等目前的動作完成～")
		return false
	_action_busy = true
	action_requested.emit(action)
	return true


func _finish_action(message: String) -> void:
	message_requested.emit(message)
	_commit()
	_action_busy = false


func _complete_wish(action: String) -> String:
	if String(data.wish_action) != action or _now() > int(data.wish_expires_at):
		return ""
	data.wish_action = ""
	data.wish_expires_at = 0
	data.next_wish_at = _now() + randi_range(WISH_MIN_SECONDS, WISH_MAX_SECONDS)
	data.mood = _limit(data.mood + 5.0)
	_add_affection(2)
	_add_xp(2)
	return "\n願望完成！親密度和 XP 額外提升。"


func _update_wish() -> void:
	var now := _now()
	if not String(data.wish_action).is_empty():
		if not _wish_is_sensible(String(data.wish_action)):
			data.wish_action = ""
			data.wish_expires_at = 0
			data.next_wish_at = now + randi_range(WISH_MIN_SECONDS, WISH_MAX_SECONDS)
			_commit()
			return
		if now > int(data.wish_expires_at):
			data.wish_action = ""
			data.wish_expires_at = 0
			data.next_wish_at = now + randi_range(WISH_MIN_SECONDS, WISH_MAX_SECONDS)
			_commit()
		return
	if now < int(data.next_wish_at):
		return
	var action := _choose_wish()
	data.wish_action = action
	data.wish_expires_at = now + WISH_DURATION_SECONDS
	data.wish_intro_seen = true
	message_requested.emit(_wish_announcement(action))
	_commit()


func _choose_wish() -> String:
	var weighted: Array[Dictionary] = []
	if data.hunger <= 70.0:
		weighted.append({"action": "feed", "weight": 15 + int(70.0 - data.hunger)})
	if data.thirst <= 70.0:
		weighted.append({"action": "water", "weight": 15 + int(70.0 - data.thirst)})
	if data.energy <= 70.0:
		weighted.append({"action": "sleep", "weight": 12 + int(70.0 - data.energy)})
	weighted.append({"action": "pet", "weight": 12 + int(100.0 - data.mood)})
	if data.energy >= 35.0 and data.hunger >= 20.0 and data.thirst >= 20.0:
		weighted.append({"action": "work", "weight": 12})
	var total := 0
	for candidate: Dictionary in weighted:
		total += int(candidate.weight)
	var roll := randi_range(1, total)
	var ceiling := 0
	for candidate: Dictionary in weighted:
		ceiling += int(candidate.weight)
		if roll <= ceiling:
			return String(candidate.action)
	return "pet"


func _wish_is_sensible(action: String) -> bool:
	match action:
		"feed":
			return data.hunger <= 92.0
		"water":
			return data.thirst <= 92.0
		"sleep":
			return true
		"work":
			return data.energy >= 18.0 and data.hunger >= 8.0 and data.thirst >= 10.0
		_:
			return true


func _wish_announcement(action: String) -> String:
	match action:
		"feed":
			return "肚子好像有點餓了……"
		"water":
			return "想喝一點水～"
		"sleep":
			return "開始想打瞌睡了……"
		"work":
			return "今天想出去滾一滾！"
		_:
			return "現在好想被摸摸！"


func _ensure_wish_schedule() -> void:
	var now := _now()
	if not bool(data.wish_intro_seen) and String(data.wish_action).is_empty():
		# Existing saves created before the wish tutorial field should not be
		# forced to wait for the normal 20–40 minute cycle.
		data.next_wish_at = now + randi_range(30, 60)
		data.save_version = SAVE_VERSION
		return
	if int(data.next_wish_at) <= 0 and String(data.wish_action).is_empty():
		data.next_wish_at = now + randi_range(FIRST_WISH_MIN_SECONDS, FIRST_WISH_MAX_SECONDS)
	data.save_version = SAVE_VERSION


func save_state() -> void:
	data.last_seen = _now()
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
	var snapshot := data.duplicate(true)
	snapshot.wish_text = wish_text()
	changed.emit(snapshot)


func _commit() -> void:
	save_state()
	emit_changed()


func _add_affection(amount: int) -> void:
	data.affection = clampi(int(data.affection) + amount, 0, 100)


func _add_xp(amount: int) -> void:
	data.xp += amount
	while data.xp >= data.level * 20:
		data.xp -= data.level * 20
		data.level += 1
		data.mood = _limit(data.mood + 12.0)
		message_requested.emit("升級了！現在是第 %d 級。" % data.level)


func _apply_offline_progress() -> void:
	var now := _now()
	var last_seen := int(data.get("last_seen", now))
	if last_seen <= 0:
		data.last_seen = now
		return
	var intervals: int = mini(int((now - last_seen) / float(DECAY_INTERVAL_SECONDS)), 48)
	if intervals <= 0:
		return
	data.hunger = _limit(data.hunger - intervals * 2.0)
	data.thirst = _limit(data.thirst - intervals * 3.0)
	if data.hunger < 25.0 or data.thirst < 25.0:
		data.mood = _limit(data.mood - intervals * 1.0)


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _limit(value: float) -> float:
	return clampf(value, 0.0, 100.0)
