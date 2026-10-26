extends "res://scripts/codex_hook_trust_service.gd"

# Answers Codex availability and trust queries from test switches instead of
# launching the Codex hook review helper.

static var available := true
static var trusted := false
# Number of upcoming queries that fail the way a timed-out app-server does.
static var availability_errors := 0
static var status_errors := 0

var recorder: Callable


func query_status(_tool_path: String, _working_directory: String) -> Dictionary:
	recorder.call("trust query_status")
	if status_errors > 0:
		status_errors -= 1
		return _query_error()
	if trusted:
		return {"status": STATUS_TRUSTED, "enabled": true, "message": "已信任"}
	return {"status": STATUS_UNTRUSTED, "enabled": true, "message": "尚未信任"}


func query_availability(_tool_path: String, _working_directory: String) -> Dictionary:
	recorder.call("trust query_availability")
	if availability_errors > 0:
		availability_errors -= 1
		return _query_error()
	if available:
		return {"status": STATUS_AVAILABLE, "enabled": true, "message": "可用"}
	return {"status": STATUS_UNAVAILABLE, "enabled": false, "message": "找不到 Codex"}


func open_review(_tool_path: String) -> bool:
	recorder.call("trust open_review")
	return true


func _query_error() -> Dictionary:
	return {
		"status": STATUS_ERROR,
		"enabled": false,
		"message": "無法查詢 Codex Hook 狀態。 Codex app-server request 2 timed out.",
	}
