extends Node2D

const PetVisualScript = preload("res://scripts/pet_visual.gd")
const OUTPUT_DIR := "res://private_pets/validation/screenshots/"

var _pet: Node2D
var _request_id := 1000
var _completed_requests: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_pet = PetVisualScript.new()
	_pet.position = Vector2(140, 190)
	add_child(_pet)
	_pet.action_completed.connect(_on_action_completed)
	_pet.set_progression({"level": 99, "affection": 100})
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("01_idle.png")
	await _capture_action("clap", "02_clap.png")
	await _capture_action("eat", "03_eat.png")
	await _capture_action("drink", "04_drink.png")
	await _capture_action("sleep", "05_sleep.png")
	await _capture_action("belly_clap", "06_belly_clap.png")
	_pet.set_dragging(true)
	await get_tree().process_frame
	await _capture("07_drag.png")
	_pet.set_dragging(false)
	await get_tree().process_frame
	await _capture_action("roll", "08_roll.png")
	get_tree().quit()


func _capture_action(action: String, filename: String) -> void:
	_request_id += 1
	var request_id := _request_id
	var duration: float = _pet.get_action_duration(action)
	_pet.play_action(action, request_id)
	await get_tree().create_timer(maxf(duration * 0.45, 0.05)).timeout
	await _capture(filename)
	while not _completed_requests.has(request_id):
		await _pet.action_completed
	var success := bool(_completed_requests[request_id])
	_completed_requests.erase(request_id)
	if not success:
		push_error("Unable to validate action: %s" % action)


func _on_action_completed(request_id: int, _action: String, success: bool) -> void:
	_completed_requests[request_id] = success


func _capture(filename: String) -> void:
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + filename))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 280, 340), Color("#f7f5f2"))
