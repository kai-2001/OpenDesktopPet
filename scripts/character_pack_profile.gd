class_name CharacterPackProfile
extends RefCounted

const BUNDLED_CUSTOM_PACK_ROOT := "res://characters/custom/"
const PUBLIC_PACK_ROOT := "res://characters/public/"
const INSTALLED_PACKS_ROOT := "user://character_packs/"
const CHARACTER_SETTINGS_PATH := "user://ui_settings.cfg"
const PUBLIC_CHARACTER_ID := "open_desktop_pet_default"
const CharacterPackRuntimeScript = preload("res://scripts/character_pack_runtime.gd")
const CharacterEffectPreferencesScript = preload(
	"res://scripts/character_effect_preferences.gd"
)

var _runtime = CharacterPackRuntimeScript.new()
var _manifest: Dictionary = {}
var _actions: Dictionary = {}
var _aliases: Dictionary = {}
var _options: Dictionary = {}
var _progression: Dictionary = {"level": 1, "affection": 0}
var _pack_root := ""
var _pack_scale := 0.31


func set_progression(snapshot: Dictionary) -> void:
	_progression.level = int(snapshot.get("level", 1))
	_progression.affection = int(snapshot.get("affection", 0))


func load_selected_pack() -> bool:
	var candidates: Array[String] = []
	var selected_id := _selected_character_id()
	if selected_id == PUBLIC_CHARACTER_ID:
		candidates.append(PUBLIC_PACK_ROOT)
	elif not selected_id.is_empty():
		candidates.append(INSTALLED_PACKS_ROOT.path_join(selected_id))
	if selected_id != PUBLIC_CHARACTER_ID:
		candidates.append(BUNDLED_CUSTOM_PACK_ROOT)
		candidates.append(PUBLIC_PACK_ROOT)
	for candidate_root: String in candidates:
		if _load_pack_from(candidate_root):
			return true
	return false


func load_pack(root: String) -> bool:
	return _load_pack_from(root)


func clear() -> void:
	_manifest.clear()
	_actions.clear()
	_aliases.clear()
	_options.clear()
	_pack_root = ""
	_pack_scale = 0.31


func has_action(action: String) -> bool:
	return _actions.has(action)


func action_ids() -> Array[String]:
	var result: Array[String] = []
	for action: String in _actions:
		result.append(action)
	return result


func action_definition(action: String) -> Dictionary:
	return _actions.get(action, {})


func set_action_definition(action: String, definition: Dictionary) -> void:
	_actions[action] = definition


func remove_action_definition(action: String) -> void:
	_actions.erase(action)


func resolve_action(action: String) -> String:
	return String(_aliases.get(action, action))


func sequence_for(definition: Dictionary) -> Array:
	var sequence: Array = definition.get("sequence", [0])
	return sequence if not sequence.is_empty() else [0]


func optional_sequence(definition: Dictionary, key: String) -> Array:
	var value: Variant = definition.get(key, [])
	return value if value is Array else []


func first_frame(action: String) -> int:
	return int(sequence_for(action_definition(action))[0])


func fallback_action() -> String:
	return String(_manifest.get("fallback_action", "idle"))


func is_action_unlocked(action: String) -> bool:
	if not has_action(action):
		return false
	var unlock: Dictionary = action_definition(action).get("unlock", {})
	return int(_progression.level) >= int(unlock.get("level", 1)) \
		and int(_progression.affection) >= int(unlock.get("affection", 0))


func pick_autonomous_action(allow_move: bool) -> String:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for action: String in _actions:
		var definition := action_definition(action)
		var weight := int(definition.get("autonomous_weight", 0))
		if weight <= 0 or not is_action_unlocked(action):
			continue
		if action == "move" and not allow_move:
			continue
		total_weight += weight
		candidates.append({"id": action, "ceiling": total_weight})
	if total_weight <= 0:
		return ""
	var chance := autonomous_chance()
	if chance <= 0.0 or (chance < 1.0 and randf() >= chance):
		return ""
	var roll := randi_range(1, total_weight)
	for candidate: Dictionary in candidates:
		if roll <= int(candidate.ceiling):
			return String(candidate.id)
	return ""


func unlocked_action_ids() -> Array[String]:
	var result: Array[String] = []
	for action: String in _actions:
		if is_action_unlocked(action):
			result.append(action)
	return result


func next_unlock() -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 1000000
	for action: String in _actions:
		var definition := action_definition(action)
		var unlock: Dictionary = definition.get("unlock", {})
		if unlock.is_empty() or is_action_unlocked(action):
			continue
		var level_need := int(unlock.get("level", 1))
		var affection_need := int(unlock.get("affection", 0))
		var distance := maxi(level_need - int(_progression.level), 0) * 100 \
			+ maxi(affection_need - int(_progression.affection), 0)
		if distance < best_distance:
			best_distance = distance
			best = {
				"id": action,
				"name": String(definition.get("display_name", action)),
				"level": level_need,
				"affection": affection_need,
			}
	return best


func get_dialogue(key: String, fallback: String) -> String:
	var dialogue: Variant = _manifest.get("dialogue", {})
	if dialogue is not Dictionary or not dialogue.has(key):
		return fallback
	var entry: Variant = dialogue[key]
	if entry is String:
		return String(entry)
	if entry is Array and not entry.is_empty():
		return String(entry.pick_random())
	return fallback


func character_id() -> String:
	var character_id := String(_manifest.get("id", "")).strip_edges()
	return character_id if not character_id.is_empty() else "default"


func character_name() -> String:
	return String(_manifest.get("name", character_id()))


func character_version() -> String:
	return String(_manifest.get("version", "1.0.0"))


func is_codex_pet() -> bool:
	return String(_manifest.get("source_format", "")) == "codex-pet" \
			or String(_manifest.get("format", "")) == "codex-pet"


func drag_anchor() -> Variant:
	var anchor: Variant = _manifest.get("drag_anchor", null)
	if anchor is not Array or anchor.size() < 2:
		return null
	if anchor[0] is not float and anchor[0] is not int:
		return null
	if anchor[1] is not float and anchor[1] is not int:
		return null
	var result := Vector2(float(anchor[0]), float(anchor[1]))
	if not is_finite(result.x) or not is_finite(result.y):
		return null
	return result


func pack_root() -> String:
	return _pack_root


func pack_scale() -> float:
	return _pack_scale


func autonomous_chance() -> float:
	return clampf(float(_options.get("autonomous_chance", 1.0)), 0.0, 1.0)


func effect_scale_ratio() -> float:
	return clampf(float(_options.get("effect_scale_ratio", _pack_scale / 0.31)), 0.45, 2.0)


func effect_overrides() -> Dictionary:
	var effects: Variant = _options.get("effects", {})
	var result: Dictionary = effects.duplicate(true) if effects is Dictionary else {}
	result.merge(CharacterEffectPreferencesScript.load_for_character(character_id()), true)
	return result


func interaction_value(action: String, key: String, fallback: Variant) -> Variant:
	var interactions: Variant = _manifest.get("interactions", {})
	if interactions is not Dictionary:
		return fallback
	var definition: Variant = interactions.get(action, {})
	if definition is not Dictionary:
		return fallback
	return definition.get(key, fallback)


func get_interaction_label(action: String, fallback: String) -> String:
	return String(interaction_value(action, "label", fallback))


func get_interaction_icon(action: String, fallback: String) -> String:
	return String(interaction_value(action, "icon", fallback))


func get_interaction_wish(action: String, fallback: String, minutes: int) -> String:
	var template := String(interaction_value(action, "wish", fallback))
	return template.replace("{minutes}", str(minutes))


func source_facing() -> String:
	return String(_manifest.get("source_facing", "left"))


func action_duration(requested_action: String) -> float:
	var action := resolve_action(requested_action)
	if not has_action(action):
		return 0.0
	var definition := action_definition(action)
	return duration_for_definition(definition)


func duration_for_definition(definition: Dictionary) -> float:
	var frame_time := float(definition.get("frame_time", 0.16))
	if String(definition.get("behavior", "sequence")) == "pulse":
		return maxi(int(definition.get("pulses", 4)), 1) * frame_time
	return sequence_for(definition).size() * frame_time


func _load_pack_from(candidate_root: String) -> bool:
	var loaded: Dictionary = _runtime.load_pack(candidate_root)
	if not bool(loaded.get("ok", false)):
		return false
	_manifest = loaded.manifest
	_actions = loaded.actions
	_aliases = loaded.aliases
	_options = loaded.get("options", {}).duplicate(true) \
		if loaded.get("options", {}) is Dictionary else {}
	_pack_scale = float(loaded.scale)
	_pack_root = String(loaded.root)
	return true


func _selected_character_id() -> String:
	var config := ConfigFile.new()
	if config.load(CHARACTER_SETTINGS_PATH) != OK:
		return ""
	var selected := String(config.get_value("character", "selected_id", ""))
	if selected.is_empty():
		return ""
	var sanitized := selected.to_lower()
	var safe := ""
	for index in sanitized.length():
		var character := sanitized.substr(index, 1)
		if character >= "a" and character <= "z" \
				or character >= "0" and character <= "9" \
				or character == "_" or character == "-":
			safe += character
	return safe if safe == selected else ""
