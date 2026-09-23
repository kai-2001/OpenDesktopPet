extends Node

const LOG_PATH := "user://display_recovery.log"
const POLL_INTERVAL_SECONDS := 0.5

var _monitor
var _poll_elapsed := 0.0
var _recovery_scheduled := false
var _pending_reasons := PackedStringArray()


func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	if not ClassDB.class_exists("WindowsDisplayRecoveryMonitor"):
		_log("Native display recovery monitor is unavailable.")
		return

	_monitor = ClassDB.instantiate("WindowsDisplayRecoveryMonitor")
	if _monitor == null:
		_log("Could not create the native display recovery monitor.")
		return

	var power_notifications_started: bool = _monitor.call("start")
	if power_notifications_started:
		_log("Monitor started; power resume events and screensaver state are being watched.")
	else:
		_log(
			"Power resume notifications are unavailable; screensaver state polling remains active. "
			+ str(_monitor.call("get_last_error"))
		)


func _process(delta: float) -> void:
	if _monitor == null:
		return
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL_SECONDS:
		return
	_poll_elapsed = fmod(_poll_elapsed, POLL_INTERVAL_SECONDS)

	var events: Dictionary = _monitor.call("poll_events")
	var reasons := PackedStringArray()
	if events.get("screensaver_started", false):
		_log("Windows screensaver started.")
	if events.get("screensaver_ended", false):
		reasons.append("screensaver_exit")
	if events.get("system_resumed", false):
		if events.get("system_was_suspended", false):
			reasons.append("system_resume_after_suspend")
		else:
			reasons.append("system_resume")
	if not reasons.is_empty():
		_schedule_recovery(reasons)


func _exit_tree() -> void:
	if _monitor != null:
		_monitor.call("stop")
		_monitor = null


func _schedule_recovery(reasons: PackedStringArray) -> void:
	for reason in reasons:
		if not _pending_reasons.has(reason):
			_pending_reasons.append(reason)
	if _recovery_scheduled:
		return
	_recovery_scheduled = true
	call_deferred("_apply_recovery_after_delay")


func _apply_recovery_after_delay() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return

	var reasons := ", ".join(_pending_reasons)
	_log("Recovery triggered by: " + reasons + ". Reapplying transparent-window state.")
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	await get_tree().process_frame
	RenderingServer.force_draw()
	_log("Transparent-window state was reapplied and a forced redraw was requested.")
	_pending_reasons.clear()
	_recovery_scheduled = false


func _log(message: String) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), message])
