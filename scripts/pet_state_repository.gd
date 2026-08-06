class_name PetStateRepository
extends RefCounted


func save(data: Dictionary, save_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_path.get_base_dir())
	)
	var temporary_path := save_path + ".tmp"
	var backup_path := save_path + ".backup"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to open save file: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()

	var verification := FileAccess.open(temporary_path, FileAccess.READ)
	if verification == null or JSON.parse_string(verification.get_as_text()) is not Dictionary:
		push_warning("Temporary save verification failed.")
		if verification != null:
			verification.close()
		return false
	verification.close()

	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(save_path):
		if DirAccess.rename_absolute(absolute_save, absolute_backup) != OK:
			push_warning("Unable to rotate the previous save file.")
			return false
	if DirAccess.rename_absolute(absolute_temporary, absolute_save) != OK:
		push_warning("Unable to install the verified save file.")
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_save)
		return false
	return true


func load(save_path: String) -> Variant:
	if not FileAccess.file_exists(save_path):
		return null
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		push_warning("Save data is invalid; defaults are used.")
		return null
	return parsed
