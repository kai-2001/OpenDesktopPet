class_name PetState
extends Node

signal changed(snapshot: Dictionary)
signal message_requested(key: String, fallback: String)
signal action_requested(action: String, request_id: int)
signal wish_started(action: String)
signal action_result_available(request_id: int)
signal sleep_started
signal sleep_ended(reason: String)

const DEFAULT_SAVE_PATH := "user://profiles/default/save_v2.json"
const SAVE_VERSION := 2
const DECAY_INTERVAL_SECONDS := 600
const COMPANION_CHECK_INTERVAL_SECONDS := 600
const PET_REWARD_COOLDOWN_SECONDS := 600
const WISH_DURATION_SECONDS := 900
const FIRST_WISH_MIN_SECONDS := 30
const FIRST_WISH_MAX_SECONDS := 60
const WISH_MIN_SECONDS := 1200
const WISH_MAX_SECONDS := 2400
const SLEEP_RECOVERY_INTERVAL_SECONDS := 3.0
const SLEEP_ENERGY_PER_TICK := 2.0

const DEFAULT_DATA := {
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
	# 陪伴紀錄，每個角色分別保存。
	"last_companion_date": "",
	"companion_streak": 0,
	"total_companion_days": 0,
	"longest_companion_streak": 0,
	"bond_progress": 0.0,
	"last_seen": 0,
	"last_decay_at": 0,
	"wish_action": "",
	"wish_expires_at": 0,
	"next_wish_at": 0,
	"wish_intro_seen": false,
	"wish_notice_version": 0,
	"last_pet_reward_at": 0,
	"visual_scale": 1.0,
}

var data: Dictionary = DEFAULT_DATA.duplicate(true)
var save_path := DEFAULT_SAVE_PATH
var _clock_accumulator := 0.0
var _companion_check_accumulator := 0.0
var _action_busy := false
var _next_request_id := 1
var _action_results: Dictionary = {}
var _initialized := false
var _sleeping := false
var _sleep_accumulator := 0.0
var _sleep_energy_before := 0.0
var _sleep_recovered := 0.0


func _ready() -> void:
	call_deferred("_initialize_if_needed")


func configure_profile(character_id: String) -> void:
	var safe_id := character_id.strip_edges().to_lower().validate_filename()
	safe_id = safe_id.replace(" ", "_")
	if safe_id.is_empty():
		safe_id = "default"
	var profile_save_path := "user://profiles/%s/save_v2.json" % safe_id
	if _initialized and save_path == profile_save_path:
		return
	save_path = profile_save_path
	data = DEFAULT_DATA.duplicate(true)
	_clock_accumulator = 0.0
	_companion_check_accumulator = 0.0
	_action_busy = false
	_sleeping = false
	_sleep_accumulator = 0.0
	_sleep_recovered = 0.0
	_action_results.clear()
	_initialized = false
	_initialize_if_needed()


func _initialize_if_needed() -> void:
	if _initialized:
		return

	_initialized = true
	load_state()

	# Offline time is frozen by design: needs and bond progress resume from the
	# saved values instead of simulating intervals while the app was closed.
	data.last_decay_at = _now()

	# 啟動程式或切換角色時，記錄今天的陪伴。
	_update_companion_record()

	_ensure_wish_schedule()
	save_state()
	emit_changed()


func _process(delta: float) -> void:
	if _sleeping:
		_process_sleep(delta)
	_clock_accumulator += delta
	_companion_check_accumulator += delta

	if _clock_accumulator < 1.0:
		return

	_clock_accumulator = fmod(_clock_accumulator, 1.0)

	var changed_by_companion := false

	if _companion_check_accumulator >= COMPANION_CHECK_INTERVAL_SECONDS:
		_companion_check_accumulator = fmod(
			_companion_check_accumulator,
			COMPANION_CHECK_INTERVAL_SECONDS
		)
		changed_by_companion = _update_companion_record()

	var changed_by_decay := _apply_elapsed_decay(_now(), 48)

	_update_wish()

	# 只有數值衰減或陪伴日期真的改變時才存檔。
	if changed_by_decay or changed_by_companion:
		_commit()


func pet() -> void:
	var request_id := _begin_action("pet")
	if request_id <= 0:
		return
	var played: bool = await _wait_for_action_result(request_id)
	if not played:
		_abort_action("pet_failed", "摸摸動畫無法播放，請檢查角色包。")
		return
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
	_finish_action("pet_rewarded" if rewarded else "pet_cooldown", message)


func feed() -> void:
	if _action_busy:
		_request_message("action_busy", "先等目前的動作完成～")
		return

	if data.hunger >= 100.0:
		_request_message("feed_full", "肚子已經很飽了，晚點再吃吧。")
		return

	if data.coins < 2:
		_request_message("feed_no_coins", "需要 2 枚金幣，先去工作吧。")
		return

	var request_id := _begin_action("eat")

	if request_id <= 0:
		return

	var played: bool = await _wait_for_action_result(request_id)

	if not played:
		_abort_action("feed_failed", "餵食動畫無法播放，沒有扣除金幣。")
		return

	var hunger_before := float(data.hunger)
	var affection_reward := _care_affection_reward(hunger_before)

	data.coins -= 2
	data.hunger = _limit(hunger_before + 20.0)
	data.mood = _limit(float(data.mood) + 4.0)
	data.care += 1

	if affection_reward > 0:
		_add_affection(affection_reward)

	_add_xp(2)

	_finish_action(
		"feed_complete",
		"好吃！一下就吃光了！"
		+ _complete_wish("feed")
	)


func water() -> void:
	if _action_busy:
		_request_message("action_busy", "先等目前的動作完成～")
		return

	if data.thirst >= 100.0:
		_request_message("water_full", "現在不渴，晚點再喝吧。")
		return

	if data.coins < 1:
		_request_message("water_no_coins", "需要 1 枚金幣，先去工作吧。")
		return

	var request_id := _begin_action("drink")

	if request_id <= 0:
		return

	var played: bool = await _wait_for_action_result(request_id)

	if not played:
		_abort_action("water_failed", "喝水動畫無法播放，沒有扣除金幣。")
		return

	# 記錄喝水前的口渴度。
	var thirst_before := float(data.thirst)
	var affection_reward := _care_affection_reward(thirst_before)

	data.coins -= 1
	data.thirst = _limit(thirst_before + 25.0)
	data.mood = _limit(float(data.mood) + 2.0)
	data.care += 1

	if affection_reward > 0:
		_add_affection(affection_reward)

	_add_xp(1)

	_finish_action(
		"water_complete",
		"咕嚕咕嚕，好清爽！"
		+ _complete_wish("water")
	)


func sleep() -> void:
	var request_id := _begin_action("sleep")
	if request_id <= 0:
		return
	var played: bool = await _wait_for_action_result(request_id)
	if not played:
		_abort_action("sleep_failed", "睡覺動畫無法播放。")
		return
	if float(data.energy) >= 100.0:
		data.mood = _limit(float(data.mood) + 4.0)
		_finish_action(
			"sleep_full",
			"雖然很有精神，還是舒服地瞇了一會。" + _complete_wish("sleep")
		)
		return
	_sleeping = true
	_sleep_accumulator = 0.0
	_sleep_energy_before = float(data.energy)
	_sleep_recovered = 0.0
	sleep_started.emit()
	emit_changed()


func work() -> void:
	if _action_busy:
		_request_message("action_busy", "先等目前的動作完成～")
		return

	if data.energy < 18.0:
		_request_message("work_tired", "太累了，先睡一下吧。")
		return

	if data.hunger < 8.0:
		_request_message("work_hungry", "肚子太餓了，吃飽再工作吧。")
		return

	if data.thirst < 10.0:
		_request_message("work_thirsty", "太渴了，喝水後再工作吧。")
		return

	var request_id := _begin_action("work")

	if request_id <= 0:
		return

	var played: bool = await _wait_for_action_result(request_id)

	if not played:
		_abort_action("work_failed", "工作動畫無法播放，沒有結算獎勵。")
		return

	var earned_coins := _apply_work_result()

	_finish_action(
		"work_complete",
		"工作完成！\n賺取 %d 枚金幣。" % earned_coins
		+ _complete_wish("work")
	)


func _process_sleep(delta: float) -> void:
	_sleep_accumulator += delta
	if _sleep_accumulator < SLEEP_RECOVERY_INTERVAL_SECONDS:
		return
	_sleep_accumulator = fmod(
		_sleep_accumulator, SLEEP_RECOVERY_INTERVAL_SECONDS
	)
	var before := float(data.energy)
	data.energy = _limit(before + SLEEP_ENERGY_PER_TICK)
	_sleep_recovered += float(data.energy) - before
	emit_changed()
	if float(data.energy) >= 100.0:
		_end_sleep("natural")


func wake_sleep(reason := "user") -> bool:
	if not _sleeping:
		return false
	_end_sleep(reason)
	return true


func _end_sleep(reason: String) -> void:
	if not _sleeping:
		return
	var natural := reason == "natural"
	_sleeping = false
	_sleep_accumulator = 0.0
	_action_busy = false
	sleep_ended.emit(reason)
	if natural:
		data.mood = _limit(float(data.mood) + 4.0)
		var affection_reward := _care_affection_reward(_sleep_energy_before)
		if affection_reward > 0:
			_add_affection(affection_reward)
			_add_xp(1)
		_request_message(
			"sleep_recovered",
			"睡飽了，精神完全恢復！" + _complete_wish("sleep")
		)
	else:
		_request_message(
			"sleep_woken",
			"醒來了，這次恢復了 %.0f 點體力。" % _sleep_recovered
		)
	_sleep_recovered = 0.0
	_commit()


func _apply_work_result() -> int:
	var coin_reward := _work_coin_reward()

	data.energy = _limit(float(data.energy) - 18.0)
	data.hunger = _limit(float(data.hunger) - 8.0)
	data.thirst = _limit(float(data.thirst) - 10.0)
	data.coins += coin_reward

	_add_xp(5)

	return coin_reward


func is_action_busy() -> bool:
	return _action_busy


func is_sleeping() -> bool:
	return _sleeping


func wish_text() -> String:
	if not has_active_wish():
		return "目前沒有願望"
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
			return "想工作（完成一次工作，剩餘約 %d 分鐘）" % minutes
		_:
			return "目前沒有願望"


func has_active_wish(now := -1) -> bool:
	var current_time: int = _now() if now < 0 else now
	return not String(data.wish_action).is_empty() \
		and int(data.wish_expires_at) > current_time


func _begin_action(action: String) -> int:
	if _action_busy:
		_request_message("action_busy", "先等目前的動作完成～")
		return 0
	_action_busy = true
	var request_id := _next_request_id
	_next_request_id += 1
	action_requested.emit(action, request_id)
	return request_id


func receive_action_completed(request_id: int, _action: String, success: bool) -> void:
	if request_id <= 0:
		return
	_action_results[request_id] = success
	action_result_available.emit(request_id)


func _wait_for_action_result(request_id: int) -> bool:
	while not _action_results.has(request_id):
		await action_result_available
	var success := bool(_action_results[request_id])
	_action_results.erase(request_id)
	return success


func _finish_action(key: String, message: String) -> void:
	_action_busy = false
	_request_message(key, message)
	_commit()


func _abort_action(key: String, message: String) -> void:
	_action_busy = false
	_request_message(key, message)
	emit_changed()


func _request_message(key: String, fallback: String) -> void:
	message_requested.emit(key, fallback)


func _complete_wish(action: String) -> String:
	if String(data.wish_action) != action or not has_active_wish():
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
		if not has_active_wish(now):
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
	wish_started.emit(action)
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


func _ensure_wish_schedule() -> void:
	var now := _now()
	data.wish_notice_version = 1
	if int(data.next_wish_at) <= 0 and String(data.wish_action).is_empty():
		if bool(data.wish_intro_seen):
			data.next_wish_at = now + randi_range(WISH_MIN_SECONDS, WISH_MAX_SECONDS)
		else:
			data.next_wish_at = now + randi_range(
				FIRST_WISH_MIN_SECONDS, FIRST_WISH_MAX_SECONDS
			)
	data.save_version = SAVE_VERSION


func save_state() -> void:
	data.last_seen = _now()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_path.get_base_dir())
	)
	var temporary_path := save_path + ".tmp"
	var backup_path := save_path + ".backup"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to open save file: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var verification := FileAccess.open(temporary_path, FileAccess.READ)
	if verification == null or JSON.parse_string(verification.get_as_text()) is not Dictionary:
		push_warning("Temporary save verification failed.")
		return
	verification.close()
	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(save_path):
		if DirAccess.rename_absolute(absolute_save, absolute_backup) != OK:
			push_warning("Unable to rotate the previous save file.")
			return
	if DirAccess.rename_absolute(absolute_temporary, absolute_save) != OK:
		push_warning("Unable to install the verified save file.")
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_save)


func load_state() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("Save data is invalid; defaults are used.")
		return
	for key: String in data.keys():
		if parsed.has(key):
			data[key] = parsed[key]
	_normalize_loaded_data()


func emit_changed() -> void:
	changed.emit(get_snapshot())


func get_snapshot() -> Dictionary:
	var snapshot := data.duplicate(true)

	snapshot.wish_text = wish_text()
	snapshot.has_active_wish = has_active_wish()

	# 提供給詳細面板與未來自主動畫使用。
	snapshot.lowest_need = _lowest_need()
	snapshot.condition_tier = _condition_tier()

	return snapshot


func _commit() -> void:
	save_state()
	emit_changed()

func _update_companion_record(date_override := "") -> bool:
	# 使用電腦目前的本地日期，只比較年月日。
	var today := (
		date_override
		if not date_override.is_empty()
		else Time.get_date_string_from_system(false)
	)
	var last_date := String(
		data.get("last_companion_date", "")
	)

	# 同一天已經記錄過，不重複增加。
	if last_date == today:
		return false

	var today_number := _date_to_day_number(today)
	var last_number := _date_to_day_number(last_date)

	# 正常情況下今天一定有效；此判斷用來防止異常資料。
	if today_number < 0:
		return false

	# 第一次陪伴，或舊日期資料無效。
	if last_date.is_empty() or last_number < 0:
		data.companion_streak = 1

	# 上一次陪伴日期正好是昨天，延續連續紀錄。
	elif today_number == last_number + 1:
		data.companion_streak = (
			maxi(int(data.companion_streak), 0) + 1
		)

	# 中間漏了一天以上，連續陪伴重新從 1 開始。
	elif today_number > last_number + 1:
		data.companion_streak = 1

	# 系統日期被調回過去時，不覆蓋原本紀錄。
	else:
		return false

	data.total_companion_days = (
		maxi(int(data.total_companion_days), 0) + 1
	)

	data.longest_companion_streak = maxi(
		int(data.longest_companion_streak),
		int(data.companion_streak)
	)

	data.last_companion_date = today

	return true


func _date_to_day_number(date_string: String) -> int:
	if date_string.is_empty():
		return -1

	var parts := date_string.split("-")

	if parts.size() != 3:
		return -1

	# 將 YYYY-MM-DD 換算成日序號，正確處理跨月、跨年及閏年。
	var unix_time := Time.get_unix_time_from_datetime_string(
		date_string
	)

	return int(unix_time / 86400.0)

func _lowest_need() -> float:
	return minf(
		float(data.hunger),
		minf(
			float(data.thirst),
			float(data.energy)
		)
	)


func _condition_tier() -> int:
	var lowest := _lowest_need()

	if lowest < 20.0:
		return 0 # 危急

	if lowest < 50.0:
		return 1 # 不佳

	if lowest < 80.0:
		return 2 # 正常

	return 3 # 良好


func _care_affection_reward(value_before: float) -> int:
	if value_before < 25.0:
		return 2

	if value_before < 70.0:
		return 1

	return 0


func _apply_bond_progress() -> void:
	match _condition_tier():
		3:
			# 三項需求都至少 80，每 10 分鐘累積 1 點。
			data.bond_progress = float(data.bond_progress) + 1.0

		2:
			# 最低需求介於 50～79，每 10 分鐘累積 0.5 點。
			data.bond_progress = float(data.bond_progress) + 0.5

		_:
			# 狀態不佳或危急時，不會自動增加親密度。
			pass

	while float(data.bond_progress) >= 12.0:
		data.bond_progress = float(data.bond_progress) - 12.0
		_add_affection(1)


func _work_coin_reward() -> int:
	# 體力占工作效率 60%，心情占 40%。
	var efficiency := (
		float(data.energy) * 0.6
		+ float(data.mood) * 0.4
	) / 100.0

	# 工作收入最低 5 枚、最高 9 枚。
	return clampi(
		roundi(5.0 + efficiency * 4.0),
		5,
		9
	)

func _add_affection(amount: int) -> void:
	data.affection = clampi(int(data.affection) + amount, 0, 100)


func _add_xp(amount: int) -> void:
	data.xp += amount
	while data.xp >= data.level * 20:
		data.xp -= data.level * 20
		data.level += 1
		data.mood = _limit(data.mood + 12.0)
		_request_message("level_up", "升級了！現在是第 %d 級。" % data.level)


func change_visual_size(delta: float) -> void:
	data.visual_scale = clampf(float(data.visual_scale) + delta, 0.7, 1.15)
	_commit()


func _apply_elapsed_decay(now: int, maximum_intervals: int) -> bool:
	var last_decay := int(data.get("last_decay_at", 0))

	if last_decay <= 0 or last_decay > now:
		data.last_decay_at = now
		return false

	var available_intervals := int(
		(now - last_decay) / float(DECAY_INTERVAL_SECONDS)
	)

	var intervals: int = mini(
		available_intervals,
		maximum_intervals
	)

	if intervals <= 0:
		return false

	for _interval in intervals:
		# 每 10 分鐘的自然衰減。
		data.hunger = _limit(float(data.hunger) - 2.0)
		data.thirst = _limit(float(data.thirst) - 3.0)
		data.energy = _limit(float(data.energy) - 0.5)

		var lowest := _lowest_need()

		# 至少一項需求嚴重不足。
		if lowest < 20.0:
			data.mood = _limit(float(data.mood) - 2.0)

		# 至少一項需求不佳。
		elif lowest < 50.0:
			data.mood = _limit(float(data.mood) - 1.0)

		# 根據整體照顧狀態累積親密成長。
		_apply_bond_progress()

	data.last_decay_at = (
		now
		if available_intervals > maximum_intervals
		else last_decay + intervals * DECAY_INTERVAL_SECONDS
	)

	return true


func _normalize_loaded_data() -> void:
	for key: String in [
		"hunger",
		"thirst",
		"energy",
		"mood",
		"affection"
	]:
		data[key] = _limit(float(data.get(key, 0.0)))

	data.bond_progress = clampf(
		float(data.get("bond_progress", 0.0)),
		0.0,
		11.999
	)

	# 陪伴紀錄相容舊存檔。
	data.last_companion_date = String(
		data.get("last_companion_date", "")
	)

	data.companion_streak = maxi(
		int(data.get("companion_streak", 0)),
		0
	)

	data.total_companion_days = maxi(
		int(data.get("total_companion_days", 0)),
		data.companion_streak
	)

	data.longest_companion_streak = maxi(
		int(data.get("longest_companion_streak", 0)),
		data.companion_streak
	)

	# 日期內容損壞時，清除日期，下一次載入會重新開始記錄。
	if (
		not data.last_companion_date.is_empty()
		and _date_to_day_number(data.last_companion_date) < 0
	):
		data.last_companion_date = ""
		data.companion_streak = 0

	data.coins = maxi(int(data.coins), 0)
	data.level = maxi(int(data.level), 1)
	data.xp = maxi(int(data.xp), 0)
	data.care = maxi(int(data.care), 0)

	data.visual_scale = clampf(
		float(data.visual_scale),
		0.7,
		1.15
	)

	for key: String in [
		"last_seen",
		"last_decay_at",
		"wish_expires_at",
		"next_wish_at",
		"last_pet_reward_at"
	]:
		data[key] = maxi(
			int(data.get(key, 0)),
			0
		)

	if String(data.wish_action) not in [
		"",
		"feed",
		"water",
		"pet",
		"sleep",
		"work"
	]:
		data.wish_action = ""
		data.wish_expires_at = 0


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _limit(value: float) -> float:
	return clampf(value, 0.0, 100.0)
