class_name StatusTabPresenter
extends RefCounted

# Shows the pet's progress on the status tab and forwards its care buttons and
# auto feeder controls. It lives for the whole session; the tab controls are
# bound while the details window exists.

const PetStateScript = preload("res://scripts/pet_state.gd")
const CARE_ACTION_IDS := {"feed": 1, "water": 2, "pet": 3, "work": 4, "sleep": 5}

signal care_action_requested(action_id: int)
signal dialogue_requested(key: String, fallback: String, seconds: float)

var _state: Node
var _pet: Node2D
var _interaction_label: Callable
var _interaction_icon: Callable
var _stats_status: Label
var _companion_status: Label
var _wish_status: Label
var _unlock_status: Label
var _last_message_status: Label
var care_action_buttons: Dictionary = {}
var stats_bars: Dictionary = {}
var _auto_feeder_buy_button: Button
var _auto_feeder_toggle: Button
var _auto_feeder_status: Label


func configure(
	state: Node, pet: Node2D, interaction_label: Callable, interaction_icon: Callable
) -> void:
	_state = state
	_pet = pet
	_interaction_label = interaction_label
	_interaction_icon = interaction_icon


func bind(view, refs: Dictionary) -> void:
	view.care_action_requested.connect(_on_care_action_requested)
	view.auto_feeder_buy_requested.connect(_on_auto_feeder_buy_requested)
	view.auto_feeder_toggled.connect(_on_auto_feeder_toggled)
	_stats_status = refs["stats_status"] as Label
	_companion_status = refs["companion_status"] as Label
	_wish_status = refs["wish_status"] as Label
	_unlock_status = refs["unlock_status"] as Label
	_last_message_status = refs["last_message_status"] as Label
	care_action_buttons = refs["care_action_buttons"] as Dictionary
	_auto_feeder_buy_button = refs["auto_feeder_buy_button"] as Button
	_auto_feeder_toggle = refs["auto_feeder_toggle"] as Button
	_auto_feeder_status = refs["auto_feeder_status"] as Label
	stats_bars = refs["stats_bars"] as Dictionary


func unbind() -> void:
	_stats_status = null
	_companion_status = null
	_wish_status = null
	_unlock_status = null
	_last_message_status = null
	_auto_feeder_buy_button = null
	_auto_feeder_toggle = null
	_auto_feeder_status = null
	stats_bars = {}
	care_action_buttons = {}


func refresh(snapshot: Dictionary, level_text: String) -> void:
	if is_instance_valid(_stats_status):
		_stats_status.text = level_text
		_wish_status.text = "願望：%s" % _formatted_wish_text(snapshot)

	if is_instance_valid(_companion_status):
		_companion_status.text = (
			"陪伴紀錄 : "
			+ "連續陪伴 %d 天"
		) % [
			int(snapshot.get("companion_streak", 0)),
		]
		var next_unlock: Dictionary = _pet.get_next_unlock()
		if next_unlock.is_empty():
			_unlock_status.text = "目前已解鎖所有角色動作"
		else:
			_unlock_status.text = "下一動作：%s　需要 Lv.%d、親密度 %d" % [
				next_unlock.name, next_unlock.level, next_unlock.affection
			]
		# Round down so the shown percent never claims more than the rules see:
		# 19.8 energy reads 19%, matching the 20-energy work requirement.
		for key: String in stats_bars:
			(stats_bars[key] as ProgressBar).value = floorf(float(snapshot[key]))
	_refresh_auto_feeder(snapshot)


func set_last_message(message: String) -> void:
	if is_instance_valid(_last_message_status):
		_last_message_status.text = "最近訊息：%s" % message


func refresh_care_labels() -> void:
	for action: String in care_action_buttons:
		var button: Button = care_action_buttons[action]
		if is_instance_valid(button):
			button.text = "%s %s" % [
				_interaction_icon.call(action), _interaction_label.call(action)
			]


func _refresh_auto_feeder(snapshot: Dictionary) -> void:
	if not is_instance_valid(_auto_feeder_buy_button):
		return
	var owned := bool(snapshot.get("auto_feeder_owned", false))
	var enabled := bool(snapshot.get("auto_feeder_enabled", false))
	var coins := int(snapshot.get("coins", 0))
	_auto_feeder_buy_button.visible = not owned
	_auto_feeder_toggle.visible = owned
	_auto_feeder_toggle.set_pressed_no_signal(enabled)
	_auto_feeder_toggle.queue_redraw()
	if not owned:
		if not bool(snapshot.get("auto_feeder_unlocked", false)):
			_auto_feeder_buy_button.text = "🔒 需要親密 %d" % (
				PetStateScript.AUTO_FEEDER_REQUIRED_AFFECTION
			)
			_auto_feeder_buy_button.disabled = true
			_auto_feeder_buy_button.tooltip_text = (
				"陪伴它到親密 %d，就能購買自動餵食器。目前親密 %d。" % [
					PetStateScript.AUTO_FEEDER_REQUIRED_AFFECTION,
					int(snapshot.get("affection", 0)),
				]
			)
			_set_auto_feeder_status("", "")
			return
		_auto_feeder_buy_button.text = "購買 %d 金幣" % PetStateScript.AUTO_FEEDER_PRICE
		var shortfall := PetStateScript.AUTO_FEEDER_PRICE - coins
		_auto_feeder_buy_button.disabled = shortfall > 0
		_auto_feeder_buy_button.tooltip_text = (
			"還差 %d 枚金幣。" % shortfall
			if shortfall > 0
			else "花 %d 枚金幣購買，買了就永久擁有，可以隨時開關。" % PetStateScript.AUTO_FEEDER_PRICE
		)
		_set_auto_feeder_status("", "")
		return
	# The switch already shows on/off; only "paused" needs a word, because the
	# switch reads on while the feeder is not actually working.
	if not enabled:
		_auto_feeder_toggle.tooltip_text = "開啟後會自動照顧飽食、水分與體力。"
		_set_auto_feeder_status("", "")
	elif bool(snapshot.get("auto_feeder_paused", false)):
		var paused_text := "金幣只剩 %d 枚，已暫停；賺到更多金幣後會恢復運作。" % coins
		_auto_feeder_toggle.tooltip_text = paused_text
		_set_auto_feeder_status("已暫停", paused_text)
	else:
		_auto_feeder_toggle.tooltip_text = "自動餵食器運作中。"
		_set_auto_feeder_status("", "")


func _set_auto_feeder_status(text: String, tooltip: String) -> void:
	if not is_instance_valid(_auto_feeder_status):
		return
	_auto_feeder_status.text = text
	_auto_feeder_status.tooltip_text = tooltip
	_auto_feeder_status.visible = not text.is_empty()


func _formatted_wish_text(snapshot: Dictionary) -> String:
	var action := String(snapshot.get("wish_action", ""))
	if action.is_empty() or not bool(snapshot.get("has_active_wish", false)):
		return "目前沒有願望"
	var remaining := maxi(
		int(snapshot.get("wish_expires_at", 0)) - int(Time.get_unix_time_from_system()),
		0
	)
	var minutes := maxi(ceili(remaining / 60.0), 1)
	var fallback := String(snapshot.get("wish_text", "目前沒有願望"))
	return _pet.get_interaction_wish(action, fallback, minutes)


func _on_care_action_requested(action: String) -> void:
	if CARE_ACTION_IDS.has(action):
		care_action_requested.emit(int(CARE_ACTION_IDS[action]))


func _on_auto_feeder_buy_requested() -> void:
	if not _state.buy_auto_feeder():
		dialogue_requested.emit("auto_feeder_cannot_buy", "現在還買不起自動餵食器。", 2.5)


func _on_auto_feeder_toggled(enabled: bool) -> void:
	_state.set_auto_feeder_enabled(enabled)
