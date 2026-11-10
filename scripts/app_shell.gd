class_name AppShell
extends Node

# The part of the app that outlives the pet. It owns the tray icon and the
# single-instance link, and creates the pet (main.tscn) when it is shown.
# Closing the pet saves and frees it completely, as if the app had quit, so
# nothing keeps running or changing until the tray brings it back.

const PetScene = preload("res://scenes/main.tscn")
const InstanceLinkScript = preload("res://scripts/instance_link.gd")
const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const UpdateCheckServiceScript = preload("res://scripts/update_check_service.gd")
const DesktopWindowServiceScript = preload("res://scripts/desktop_window_service.gd")
const STATUS_ICON = preload("res://assets/branding/birthmark_app_icon.png")

## How long a newer copy waits for the running one to save and exit.
const HANDOFF_TIMEOUT_MS := 15000
const NOTICE_SECONDS := 8.0
const OLDER_VERSION_NOTICE := (
	"較新版本的桌寵正在執行中。要使用舊版，請先在右下角的桌寵圖示按右鍵，選「退出」。"
)

## The open pet, or null while it is closed.
var pet: Node = null
var _link
var _window_service = DesktopWindowServiceScript.new()
var _status_indicator: StatusIndicator
var _closed_menu: PopupMenu
var _exiting := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_link = InstanceLinkScript.new()
	if not _claim_instance():
		return
	_setup_status_indicator()
	open_pet()


func _process(_delta: float) -> void:
	if _link != null:
		_link.poll(Callable(self, "_on_launch_requested"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		call_deferred("exit_app")


func is_window_concealed() -> bool:
	return _window_service.is_window_concealed()


func is_pet_open() -> bool:
	return is_instance_valid(pet)


## Creates the pet, or brings an open one back into view.
func show_pet(notice := "") -> void:
	if _exiting:
		return
	if not is_pet_open():
		open_pet(notice)
		return
	pet.recover_pet()
	if not notice.is_empty():
		pet.say(notice, NOTICE_SECONDS)


func open_pet(notice := "") -> void:
	if _exiting or is_pet_open():
		return
	_window_service.reveal_window()
	var instance: Node = PetScene.instantiate()
	instance.hosted = true
	instance.startup_notice = notice
	instance.close_requested.connect(close_pet)
	instance.exit_requested.connect(exit_app)
	pet = instance
	add_child(instance)
	_use_tray_menu(instance.get_tray_menu())


## Saves the pet and frees it; the tray icon stays to bring it back.
func close_pet() -> void:
	if not is_pet_open():
		return
	_use_tray_menu(_closed_menu)
	var closing := pet
	pet = null
	closing.prepare_shutdown()
	remove_child(closing)
	closing.queue_free()
	_window_service.conceal_window()


func exit_app() -> void:
	if _exiting:
		return
	_exiting = true
	if is_pet_open():
		pet.prepare_shutdown()
	if is_instance_valid(_status_indicator):
		_status_indicator.queue_free()
	_status_indicator = null
	if _link != null:
		_link.close()
	get_tree().quit()


## Stops this launch when another copy already runs the pet, unless this copy
## is newer: then the running one saves and exits and this one takes over.
func _claim_instance() -> bool:
	var result: Dictionary = _link.claim()
	if String(result.role) == InstanceLinkScript.ROLE_PRIMARY:
		return true
	if String(result.reply) == InstanceLinkScript.REPLY_YIELD \
			and _link.wait_until_free(HANDOFF_TIMEOUT_MS):
		return true
	_exiting = true
	_window_service.conceal_window()
	get_tree().quit()
	return false


func _on_launch_requested(version: String) -> String:
	var running := InstanceLinkScript.current_version()
	var reply := InstanceLinkScript.decide(version, running)
	if reply == InstanceLinkScript.REPLY_YIELD:
		call_deferred("exit_app")
	elif UpdateCheckServiceScript.is_newer(running, version):
		call_deferred("show_pet", OLDER_VERSION_NOTICE)
	else:
		call_deferred("show_pet")
	return reply


func _setup_status_indicator() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_closed_menu = PopupMenu.new()
	_closed_menu.name = "ClosedTrayMenu"
	PetMenuBuilderScript.populate_closed_tray(_closed_menu)
	_closed_menu.id_pressed.connect(_on_closed_menu_action)
	add_child(_closed_menu)
	_status_indicator = StatusIndicator.new()
	_status_indicator.icon = STATUS_ICON
	_status_indicator.tooltip = "Open Desktop Pet"
	add_child(_status_indicator)
	_status_indicator.pressed.connect(_on_status_indicator_pressed)
	_use_tray_menu(_closed_menu)


func _use_tray_menu(menu: PopupMenu) -> void:
	if not is_instance_valid(_status_indicator):
		return
	if not is_instance_valid(menu):
		menu = _closed_menu
	_status_indicator.menu = _status_indicator.get_path_to(menu)


func _on_status_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		call_deferred("show_pet")


func _on_closed_menu_action(id: int) -> void:
	match id:
		PetMenuBuilderScript.SHOW_ITEM_ID:
			call_deferred("show_pet")
		PetMenuBuilderScript.EXIT_ITEM_ID:
			call_deferred("exit_app")
