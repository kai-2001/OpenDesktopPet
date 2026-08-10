class_name CharacterPackRuntime
extends RefCounted

const REQUIRED_ACTIONS := ["idle", "pet", "eat", "drink", "sleep", "move", "drag", "work"]
const CharacterPackValidatorScript = preload("res://scripts/character_pack_validator.gd")
const CodexPetImporterScript = preload("res://scripts/codex_pet_importer.gd")
const CharacterPackOptionsScript = preload("res://scripts/character_pack_options.gd")

var _validator = CharacterPackValidatorScript.new()


func load_pack(root: String) -> Dictionary:
	var manifest_path := root.path_join("pet.json")
	if not FileAccess.file_exists(manifest_path):
		return _failure()
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return _failure()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("pet.json is not valid JSON.")
		return _failure()
	var manifest: Dictionary = parsed
	if CodexPetImporterScript.is_codex_manifest(manifest):
		return CodexPetImporterScript.normalize(root, manifest)
	if int(manifest.get("format_version", 0)) != 1:
		push_warning("Unsupported character-pack format version: %s" % manifest_path)
		return _failure()
	var actions: Variant = manifest.get("actions", {})
	if actions is not Dictionary:
		push_warning("Character pack actions must be an object: %s" % manifest_path)
		return _failure()
	for required_action: String in REQUIRED_ACTIONS:
		if not actions.has(required_action):
			push_warning("Character pack is missing required action '%s': %s" % [
				required_action, manifest_path
			])
			return _failure()
	for action_id: String in actions:
		if not _validator.validate_action(
				action_id, actions[action_id], root, true, false
		):
			return _failure()
	var fallback := String(manifest.get("fallback_action", "idle"))
	if not actions.has(fallback):
		push_warning("Character-pack fallback action does not exist: %s" % fallback)
		return _failure()
	var loaded := {
		"ok": true,
		"manifest": manifest,
		"actions": actions,
		"aliases": manifest.get("aliases", {})
			if manifest.get("aliases", {}) is Dictionary else {},
		"scale": clampf(float(manifest.get("scale", 0.31)), 0.01, 4.0),
		"root": root,
	}
	loaded["options"] = CharacterPackOptionsScript.load_for_pack(root, {
		"effect_scale_ratio": float(loaded.scale) / 0.31,
	})
	return loaded

func _failure() -> Dictionary:
	return {"ok": false}
