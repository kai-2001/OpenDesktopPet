class_name CharacterEffectPreferences
extends RefCounted

const SETTINGS_PATH := "user://character_effects.json"
const EFFECT_NAMES := ["food", "water", "mask", "zzz"]


static func load_for_character(
	character_id: String, settings_path: String = SETTINGS_PATH
) -> Dictionary:
	var document := _load_document(settings_path)
	var characters: Variant = document.get("characters", {})
	if not characters is Dictionary:
		return {}
	var entry: Variant = characters.get(character_id, {})
	if not entry is Dictionary:
		return {}
	var effects: Variant = entry.get("effects", {})
	if not effects is Dictionary:
		return {}
	return _normalize_effects(effects)


static func set_effect(
	character_id: String,
	effect_name: String,
	definition: Dictionary,
	settings_path: String = SETTINGS_PATH
) -> bool:
	if character_id.is_empty() or effect_name not in EFFECT_NAMES:
		return false
	var document := _load_document(settings_path)
	var raw_characters: Variant = document.get("characters", {})
	var characters: Dictionary = raw_characters if raw_characters is Dictionary else {}
	var raw_entry: Variant = characters.get(character_id, {})
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	var raw_effects: Variant = entry.get("effects", {})
	var effects: Dictionary = raw_effects if raw_effects is Dictionary else {}
	var normalized := _normalize_effects({effect_name: definition})
	if not normalized.has(effect_name):
		return false
	effects[effect_name] = normalized[effect_name]
	entry["effects"] = effects
	characters[character_id] = entry
	document["characters"] = characters
	return _save_document(document, settings_path)


static func clear_effect(
	character_id: String, effect_name: String, settings_path: String = SETTINGS_PATH
) -> bool:
	if character_id.is_empty() or effect_name not in EFFECT_NAMES:
		return false
	var document := _load_document(settings_path)
	var raw_characters: Variant = document.get("characters", {})
	var characters: Dictionary = raw_characters if raw_characters is Dictionary else {}
	if not characters.has(character_id):
		return true
	var raw_entry: Variant = characters[character_id]
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	var raw_effects: Variant = entry.get("effects", {})
	var effects: Dictionary = raw_effects if raw_effects is Dictionary else {}
	effects.erase(effect_name)
	if effects.is_empty():
		characters.erase(character_id)
	else:
		entry["effects"] = effects
		characters[character_id] = entry
	document["characters"] = characters
	return _save_document(document, settings_path)


static func _load_document(settings_path: String) -> Dictionary:
	if not FileAccess.file_exists(settings_path):
		return {"version": 1, "characters": {}}
	var file := FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		return {"version": 1, "characters": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"version": 1, "characters": {}}
	return parsed


static func _save_document(document: Dictionary, settings_path: String) -> bool:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "\t"))
	return true


static func _normalize_effects(effects: Dictionary) -> Dictionary:
	var result := {}
	for effect_name: String in EFFECT_NAMES:
		var raw_definition: Variant = effects.get(effect_name, {})
		if not raw_definition is Dictionary:
			continue
		var definition: Dictionary = {}
		var raw_anchor: Variant = raw_definition.get("anchor", null)
		if raw_anchor is Array and raw_anchor.size() >= 2:
			var anchor := Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
			if is_finite(anchor.x) and is_finite(anchor.y):
				definition["anchor"] = [anchor.x, anchor.y]
		if raw_definition.has("scale"):
			var scale := float(raw_definition.get("scale", 1.0))
			if is_finite(scale):
				definition["scale"] = clampf(scale, 0.01, 4.0)
		if not definition.is_empty():
			result[effect_name] = definition
	return result
