class_name PetGameplayCoordinator
extends RefCounted

const AUTONOMOUS_MOVE_MIN_PX := 96
const AUTONOMOUS_MOVE_MAX_PX := 120

var _owner: Node
var _state: Node
var _pet: Node2D
var _window_service
var _auto_move_tween: Tween


func configure(owner: Node, state: Node, pet: Node2D, window_service) -> void:
	_owner = owner
	_state = state
	_pet = pet
	_window_service = window_service


func can_start_action() -> bool:
	return not _state.is_action_busy() and not _pet.is_busy()


func can_begin_drag() -> bool:
	return not _state.is_action_busy()


func cancel_autonomous_action() -> bool:
	# Sleep is a persistent state action, not an autonomous animation. Mouse
	# activity should stop idle rolls and moves, but must not leave the state
	# sleeping while the visual has already been restored to idle.
	if _state.is_sleeping():
		return true
	_cancel_move_tween()
	return _pet.cancel_autonomous_action()


func request_care_action(action_id: int) -> String:
	if _state.is_sleeping():
		_state.wake_sleep("care_action")
		return "woke"
	if _state.is_action_busy() or not cancel_autonomous_action():
		return "busy"
	match action_id:
		1:
			_state.feed()
		2:
			_state.water()
		3:
			_state.pet()
		4:
			_state.work()
		5:
			_state.sleep()
		_:
			return "invalid"
	return "started"


func run_autonomous_action(mouse_is_idle: bool) -> void:
	if _state.is_sleeping():
		return
	var action: String = _pet.pick_autonomous_action(mouse_is_idle)
	if action == "move":
		start_autonomous_move(mouse_is_idle)
	elif not action.is_empty():
		_pet.play_action(action)


func start_autonomous_move(mouse_is_idle: bool) -> void:
	if not mouse_is_idle or not can_start_action():
		return
	var usable: Rect2i = _window_service.usable_rect()
	var distance := randi_range(
		AUTONOMOUS_MOVE_MIN_PX,
		AUTONOMOUS_MOVE_MAX_PX
	) * (-1 if randf() < 0.5 else 1)
	if not _pet.begin_progressive_move():
		return
	var start: Vector2i = _window_service.window_position()
	var window_size: Vector2i = _window_service.window_size()
	var target_x := clampi(
		start.x + distance,
		usable.position.x,
		usable.end.x - window_size.x
	)
	if target_x == start.x:
		target_x = clampi(
			start.x - distance,
			usable.position.x,
			usable.end.x - window_size.x
		)
	var target := Vector2i(target_x, start.y)
	var move_duration: float = _pet.get_action_duration("move")
	_pet.set_facing_direction(1 if target_x > start.x else -1)
	_pet.update_progressive_move(0.0)
	var tween := _owner.create_tween()
	_auto_move_tween = tween
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(weight: float) -> void:
			_pet.update_progressive_move(weight)
			_window_service.set_window_position(
				Vector2i(Vector2(start).lerp(Vector2(target), weight))
			),
		0.0,
		1.0,
		move_duration
	)
	tween.finished.connect(func() -> void:
		if _auto_move_tween != tween:
			return
		_auto_move_tween = null
		_pet.finish_progressive_move()
	)


func _cancel_move_tween() -> void:
	if is_instance_valid(_auto_move_tween):
		_auto_move_tween.kill()
		_auto_move_tween = null
