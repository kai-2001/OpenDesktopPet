class_name CharacterPackOptions
extends RefCounted

const SETTINGS_FILE := "open_desktop_pet.json"
const EFFECT_NAMES := ["food", "water", "mask", "zzz"]


static func load_for_pack(root: String, defaults: Dictionary = {}) -> Dictionary:
	var options := {
		"autonomous_chance": clampf(
			float(defaults.get("autonomous_chance", 1.0)), 0.0, 1.0
		),
		"effect_scale_ratio": clampf(
			float(defaults.get("effect_scale_ratio", 1.0)), 0.45, 2.0
		),
		"effects": {},
	}
	var settings_path := root.path_join(SETTINGS_FILE)
	if not FileAccess.file_exists(settings_path):
		return options
	var file := FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		return options
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("open_desktop_pet.json is not a valid JSON object: %s" % settings_path)
		return options
	var settings: Dictionary = parsed
	var behavior: Variant = settings.get("behavior", {})
	if behavior is Dictionary and behavior.has("autonomous_chance"):
		options["autonomous_chance"] = clampf(
			float(behavior.autonomous_chance), 0.0, 1.0
		)
	var effects: Variant = settings.get("effects", {})
	if effects is Dictionary:
		options["effects"] = _normalize_effects(root, effects)
	return options


static func _normalize_effects(root: String, effects: Dictionary) -> Dictionary:
	var result := {}
	for effect_name: String in EFFECT_NAMES:
		var raw_definition: Variant = effects.get(effect_name, {})
		if raw_definition is not Dictionary:
			continue
		var definition: Dictionary = raw_definition.duplicate(true)
		if definition.has("file"):
			var relative_path := String(definition.file).strip_edges()
			if not _is_safe_relative_path(relative_path) \
					or not FileAccess.file_exists(root.path_join(relative_path)):
				definition.erase("file")
			else:
				definition["file"] = root.path_join(relative_path)
		if definition.has("anchor"):
			var anchor: Variant = definition.anchor
			if anchor is not Array or anchor.size() < 2:
				definition.erase("anchor")
		if definition.has("scale"):
			definition["scale"] = clampf(float(definition.scale), 0.01, 4.0)
		if definition.has("duration"):
			definition["duration"] = clampf(float(definition.duration), 0.2, 10.0)
		if definition.has("sway"):
			definition["sway"] = clampf(float(definition.sway), 0.0, 100.0)
		if not definition.is_empty():
			result[effect_name] = definition
	return result


static func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() \
			or path.contains("\\") or path.contains(":"):
		return false
	for part: String in path.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return path.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]
