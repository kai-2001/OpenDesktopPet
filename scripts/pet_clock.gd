class_name PetClock
extends RefCounted


func now() -> int:
	return int(Time.get_unix_time_from_system())


func local_date() -> String:
	return Time.get_date_string_from_system(false)
