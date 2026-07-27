extends Node2D

const PetVisualScript = preload("res://scripts/pet_visual.gd")
const OUTPUT_DIR := "res://private_pets/active/rig2d/validation/"

var _pet: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_pet = PetVisualScript.new()
	_pet.position = Vector2(140, 190)
	add_child(_pet)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("01_idle.png")
	_pet.play_action("clap")
	await get_tree().create_timer(0.22).timeout
	await _capture("02_clap.png")
	await get_tree().create_timer(0.9).timeout
	_pet.play_action("eat")
	await get_tree().create_timer(0.32).timeout
	await _capture("03_eat.png")
	await get_tree().create_timer(1.5).timeout
	_pet.play_action("drink")
	await get_tree().create_timer(0.32).timeout
	await _capture("04_drink.png")
	await get_tree().create_timer(1.3).timeout
	_pet.play_action("sleep")
	await get_tree().create_timer(0.25).timeout
	await _capture("05_sleep.png")
	await get_tree().create_timer(2.5).timeout
	_pet.play_action("belly_clap")
	await get_tree().create_timer(0.3).timeout
	await _capture("06_belly_clap.png")
	await get_tree().create_timer(1.2).timeout
	_pet.set_dragging(true)
	await get_tree().create_timer(0.12).timeout
	await _capture("07_drag.png")
	_pet.set_dragging(false)
	await get_tree().create_timer(0.2).timeout
	_pet.play_action("roll")
	await get_tree().create_timer(0.22).timeout
	await _capture("08_roll.png")
	get_tree().quit()


func _capture(filename: String) -> void:
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + filename))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 280, 340), Color("#f7f5f2"))
