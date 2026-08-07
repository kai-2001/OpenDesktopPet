extends SceneTree

const WindowsAutostartServiceScript = preload(
	"res://scripts/windows_autostart_service.gd"
)

var _service
var _completed := false
var _result: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_name() != "Windows":
		print("WINDOWS_AUTOSTART_SERVICE_TEST_OK")
		quit(0)
		return
	_service = WindowsAutostartServiceScript.new()
	_service.operation_completed.connect(_on_operation_completed)
	_service.query()
	var deadline := Time.get_ticks_msec() + 5000
	while not _completed and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	if not _completed:
		_fail("Windows autostart query did not complete within five seconds.")
		return
	if not _result.has("exists") or not _result.has("matches"):
		_fail("Windows autostart query returned an incomplete result.")
		return
	_service.shutdown()
	print("WINDOWS_AUTOSTART_SERVICE_TEST_OK")
	quit(0)


func _on_operation_completed(
	_operation_id: int,
	operation: String,
	_enabled: bool,
	result: Dictionary
) -> void:
	if operation != "query":
		return
	_result = result
	_completed = true


func _fail(message: String) -> void:
	if _service != null:
		_service.shutdown()
	push_error(message)
	quit(1)
