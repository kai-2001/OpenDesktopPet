class_name CharacterPackManager
extends RefCounted

const PACKS_ROOT := "user://character_packs"
const CharacterPackValidatorScript = preload("res://scripts/character_pack_validator.gd")
const REQUIRED_ACTIONS := ["idle", "pet", "eat", "drink", "sleep", "move", "drag", "work"]
const ALLOWED_PREVIEW_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]
const MAX_ARCHIVE_FILES := 2048
const MAX_ARCHIVE_BYTES := 256 * 1024 * 1024
const MAX_SINGLE_FILE_BYTES := 32 * 1024 * 1024


static func ensure_packs_root() -> Error:
	return DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PACKS_ROOT)
	)


static func list_installed() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if ensure_packs_root() != OK:
		return result
	var directory := DirAccess.open(PACKS_ROOT)
	if directory == null:
		return result
	for folder_name: String in directory.get_directories():
		if folder_name.begins_with("."):
			continue
		var root := PACKS_ROOT.path_join(folder_name)
		var validation := validate_pack(root)
		if not bool(validation.get("ok", false)):
			continue
		var manifest: Dictionary = validation.manifest
		result.append({
			"id": String(manifest.id),
			"name": String(manifest.get("name", manifest.id)),
			"version": String(manifest.get("version", "1.0.0")),
			"root": root,
			"preview": _preview_path(root, manifest),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	)
	return result


static func install_archive(archive_path: String) -> Dictionary:
	if ensure_packs_root() != OK:
		return _failure("無法建立角色包資料夾。")
	if not FileAccess.file_exists(archive_path):
		return _failure("找不到選取的角色包檔案。")
	var staging_name := ".staging-%s" % str(Time.get_ticks_usec())
	var staging_root := PACKS_ROOT.path_join(staging_name)
	var staging_absolute := ProjectSettings.globalize_path(staging_root)
	if DirAccess.make_dir_recursive_absolute(staging_absolute) != OK:
		return _failure("無法建立角色包暫存資料夾。")

	var extraction := _extract_archive(archive_path, staging_root)
	if not bool(extraction.get("ok", false)):
		_remove_tree(staging_absolute)
		return extraction

	var validation := validate_pack(staging_root)
	if not bool(validation.get("ok", false)):
		_remove_tree(staging_absolute)
		return validation
	var manifest: Dictionary = validation.manifest
	var character_id := String(manifest.id)
	var target_root := PACKS_ROOT.path_join(character_id)
	var target_absolute := ProjectSettings.globalize_path(target_root)
	var backup_absolute := target_absolute + ".backup-" + str(Time.get_ticks_usec())
	var was_update := DirAccess.dir_exists_absolute(target_absolute)

	if was_update and DirAccess.rename_absolute(target_absolute, backup_absolute) != OK:
		_remove_tree(staging_absolute)
		return _failure(
			"無法更新角色包：角色資料夾可能正被檔案總管、"
			+ "圖片預覽或其他程式使用，請關閉後重試。"
		)
	if DirAccess.rename_absolute(staging_absolute, target_absolute) != OK:
		if was_update:
			DirAccess.rename_absolute(backup_absolute, target_absolute)
		_remove_tree(staging_absolute)
		return _failure("無法完成角色包安裝。")
	if was_update:
		_remove_tree(backup_absolute)
	return {
		"ok": true,
		"id": character_id,
		"name": String(manifest.get("name", character_id)),
		"version": String(manifest.get("version", "1.0.0")),
		"updated": was_update,
	}


static func inspect_archive(archive_path: String) -> Dictionary:
	if not FileAccess.file_exists(archive_path):
		return _failure("找不到選取的角色包檔案。")
	var reader := ZIPReader.new()
	if reader.open(archive_path) != OK:
		return _failure("無法開啟角色包；請使用ZIP或.petpack格式。")
	var entries := reader.get_files()
	if "pet.json" not in entries:
		reader.close()
		return _failure("角色包根目錄缺少 pet.json。")
	var bytes := reader.read_file("pet.json")
	reader.close()
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is not Dictionary:
		return _failure("pet.json 不是有效的JSON物件。")
	var manifest: Dictionary = parsed
	if int(manifest.get("format_version", 0)) != 1:
		return _failure("不支援這個角色包格式版本。")
	var character_id := String(manifest.get("id", "")).strip_edges()
	if character_id.is_empty() or sanitize_character_id(character_id) != character_id:
		return _failure("角色ID只能使用小寫英文字母、數字、底線與連字號。")
	return {
		"ok": true,
		"id": character_id,
		"name": String(manifest.get("name", character_id)),
		"version": String(manifest.get("version", "1.0.0")),
	}


static func remove_pack(character_id: String) -> Dictionary:
	var safe_id := sanitize_character_id(character_id)
	if safe_id.is_empty() or safe_id != character_id:
		return _failure("角色ID不安全，無法刪除。")
	var target_root := PACKS_ROOT.path_join(safe_id)
	var target_absolute := ProjectSettings.globalize_path(target_root)
	if not DirAccess.dir_exists_absolute(target_absolute):
		return _failure("找不到要刪除的角色包。")
	if not _remove_tree(target_absolute):
		return _failure("角色包刪除失敗，可能仍有檔案正在使用。")
	return {"ok": true, "id": safe_id}


static func validate_pack(root: String) -> Dictionary:
	var manifest_path := root.path_join("pet.json")
	if not FileAccess.file_exists(manifest_path):
		return _failure("角色包根目錄缺少 pet.json。")
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return _failure("無法讀取角色包的 pet.json。")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return _failure("pet.json 不是有效的JSON物件。")
	var manifest: Dictionary = parsed
	if int(manifest.get("format_version", 0)) != 1:
		return _failure("不支援這個角色包格式版本。")
	var raw_id := String(manifest.get("id", "")).strip_edges()
	var safe_id := sanitize_character_id(raw_id)
	if safe_id.is_empty() or raw_id != safe_id:
		return _failure("角色ID只能使用小寫英文字母、數字、底線與連字號。")
	var actions: Variant = manifest.get("actions", {})
	if actions is not Dictionary:
		return _failure("pet.json 的 actions 必須是物件。")
	for required_action: String in REQUIRED_ACTIONS:
		if not actions.has(required_action):
			return _failure("角色包缺少必要動作：%s。" % required_action)
	var validator = CharacterPackValidatorScript.new()
	for action_id: String in actions:
		if not validator.validate_action(action_id, actions[action_id], root, false, true):
			return _failure("動作 %s 驗證失敗。" % action_id)
	var preview := String(manifest.get("preview", ""))
	if not preview.is_empty():
		if not _is_safe_relative_path(preview):
			return _failure("角色預覽圖路徑不安全。")
		if preview.get_extension().to_lower() not in ALLOWED_PREVIEW_EXTENSIONS:
			return _failure("角色預覽圖格式不受支援。")
		if not FileAccess.file_exists(root.path_join(preview)):
			return _failure("找不到角色預覽圖。")
	return {"ok": true, "manifest": manifest}


static func sanitize_character_id(value: String) -> String:
	var lowered := value.strip_edges().to_lower()
	var result := ""
	for index in lowered.length():
		var character := lowered.substr(index, 1)
		if character >= "a" and character <= "z" \
				or character >= "0" and character <= "9" \
				or character == "_" or character == "-":
			result += character
	return result


static func _extract_archive(archive_path: String, staging_root: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(archive_path)
	if open_error != OK:
		return _failure("無法開啟角色包；請使用ZIP或.petpack格式。")
	var entries := reader.get_files()
	if entries.size() > MAX_ARCHIVE_FILES:
		reader.close()
		return _failure("角色包檔案數量過多。")
	var total_bytes := 0
	for raw_entry: String in entries:
		var entry := raw_entry.replace("\\", "/")
		if entry.ends_with("/"):
			continue
		if not _is_safe_relative_path(entry):
			reader.close()
			return _failure("角色包包含不安全的路徑：%s。" % raw_entry)
		var bytes := reader.read_file(raw_entry)
		if bytes.size() > MAX_SINGLE_FILE_BYTES:
			reader.close()
			return _failure("角色包內的單一檔案過大：%s。" % raw_entry)
		total_bytes += bytes.size()
		if total_bytes > MAX_ARCHIVE_BYTES:
			reader.close()
			return _failure("角色包解壓後超過256MB限制。")
		var destination := staging_root.path_join(entry)
		var destination_absolute := ProjectSettings.globalize_path(destination)
		if DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir()) != OK:
			reader.close()
			return _failure("無法建立角色包子資料夾。")
		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			reader.close()
			return _failure("無法寫入角色包檔案：%s。" % entry)
		output.store_buffer(bytes)
	reader.close()
	return {"ok": true}


static func _preview_path(root: String, manifest: Dictionary) -> String:
	var relative := String(manifest.get("preview", ""))
	if relative.is_empty():
		return ""
	return root.path_join(relative)


static func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains("\\"):
		return false
	if path.contains(":"):
		return false
	for part: String in path.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


static func _remove_tree(absolute_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return true
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if DirAccess.remove_absolute(absolute_path.path_join(file_name)) != OK:
			return false
	for folder_name: String in directory.get_directories():
		if not _remove_tree(absolute_path.path_join(folder_name)):
			return false
	return DirAccess.remove_absolute(absolute_path) == OK


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
