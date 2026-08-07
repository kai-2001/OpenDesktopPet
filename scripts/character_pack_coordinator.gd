class_name CharacterPackCoordinator
extends RefCounted

const CharacterPackManagerScript = preload("res://scripts/character_pack_manager.gd")

const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const DEFAULT_CHARACTER_ID := "open_desktop_pet_default"

var _state: Node
var _pet: Node2D


func configure(state: Node, pet: Node2D) -> void:
	_state = state
	_pet = pet


func list_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [{
		"id": DEFAULT_CHARACTER_ID,
		"name": "預設桌寵",
		"version": "內建",
		"installed": false,
		"builtin": true,
	}]
	for entry: Dictionary in CharacterPackManagerScript.list_installed():
		var installed_entry := entry.duplicate()
		installed_entry.installed = true
		installed_entry.builtin = false
		entries.append(installed_entry)
	return entries


func inspect_archive(path: String) -> Dictionary:
	return CharacterPackManagerScript.inspect_archive(path)


func install_archive(path: String) -> Dictionary:
	return CharacterPackManagerScript.install_archive(path)


func remove_pack(character_id: String) -> Dictionary:
	return CharacterPackManagerScript.remove_pack(character_id)


func ensure_packs_root() -> Error:
	return CharacterPackManagerScript.ensure_packs_root()


func packs_root() -> String:
	return CharacterPackManagerScript.PACKS_ROOT


func save_selected_character_id(character_id: String) -> void:
	var config := ConfigFile.new()
	config.load(UI_SETTINGS_PATH)
	config.set_value("character", "selected_id", character_id)
	config.save(UI_SETTINGS_PATH)


func switch_character(character_id: String) -> Dictionary:
	var previous_character_id: String = _pet.get_character_id()
	save_selected_character_id(character_id)
	if not _pet.reload_character() or _pet.get_character_id() != character_id:
		save_selected_character_id(previous_character_id)
		_pet.reload_character()
		_state.configure_profile(_pet.get_character_id())
		return {
			"ok": false,
			"previous_id": previous_character_id,
			"active_id": _pet.get_character_id(),
		}
	return {
		"ok": true,
		"previous_id": previous_character_id,
		"active_id": _pet.get_character_id(),
	}
