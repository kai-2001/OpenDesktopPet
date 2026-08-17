class_name CodexHookTrustService
extends RefCounted

const STATUS_TRUSTED := "trusted"
const STATUS_AVAILABLE := "available"
const STATUS_UNTRUSTED := "untrusted"
const STATUS_MODIFIED := "modified"
const STATUS_DISABLED := "disabled"
const STATUS_MISSING := "missing"
const STATUS_UNAVAILABLE := "unavailable"
const STATUS_ERROR := "error"


func query_status(tool_path: String, working_directory: String) -> Dictionary:
	return _query_tool(tool_path, working_directory, "Status")


func query_availability(tool_path: String, working_directory: String) -> Dictionary:
	return _query_tool(tool_path, working_directory, "Availability")


func _query_tool(
	tool_path: String, working_directory: String, action: String
) -> Dictionary:
	if tool_path.is_empty() or not FileAccess.file_exists(tool_path):
		return _result(STATUS_UNAVAILABLE, "找不到 Codex Hook 審查工具。")
	var output: Array = []
	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-WindowStyle",
			"Hidden",
			"-File",
			tool_path,
			"-Action",
			action,
			"-WorkingDirectory",
			working_directory,
		]),
		output,
		true,
		false
	)
	if exit_code != 0:
		return _result(STATUS_ERROR, "Codex Hook 狀態檢查失敗。")
	return parse_status_output("\n".join(PackedStringArray(output)))


func open_review(tool_path: String) -> bool:
	if tool_path.is_empty() or not FileAccess.file_exists(tool_path):
		return false
	return OS.create_process(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-WindowStyle",
			"Hidden",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			tool_path,
			"-Action",
			"Launch",
		])
	) > 0


func parse_status_output(output_text: String) -> Dictionary:
	var lines := output_text.strip_edges().split("\n", false)
	for index in range(lines.size() - 1, -1, -1):
		var parser := JSON.new()
		if parser.parse(lines[index].strip_edges()) != OK:
			continue
		var parsed: Variant = parser.data
		if not parsed is Dictionary:
			continue
		var status := String(parsed.get("status", STATUS_ERROR)).to_lower()
		if status not in [
			STATUS_TRUSTED,
			STATUS_AVAILABLE,
			STATUS_UNTRUSTED,
			STATUS_MODIFIED,
			STATUS_DISABLED,
			STATUS_MISSING,
			STATUS_UNAVAILABLE,
			STATUS_ERROR,
		]:
			status = STATUS_UNTRUSTED
		return {
			"status": status,
			"message": _status_message(
				status, String(parsed.get("message", ""))
			),
			"enabled": bool(parsed.get("enabled", false)),
			"trust_status": String(parsed.get("trust_status", "")),
		}
	return _result(STATUS_ERROR, "Codex Hook 狀態輸出無法解析。")


func is_trusted(status: Dictionary) -> bool:
	return String(status.get("status", "")) == STATUS_TRUSTED \
		and bool(status.get("enabled", false))


func is_available(status: Dictionary) -> bool:
	return String(status.get("status", "")) == STATUS_AVAILABLE \
		and bool(status.get("enabled", false))


func _status_message(status: String, detail: String) -> String:
	match status:
		STATUS_AVAILABLE:
			return "已找到支援 Hook 審查的 Codex。"
		STATUS_TRUSTED:
			return "Codex Stop Hook 已信任。"
		STATUS_MODIFIED:
			return "桌寵 Hook 已變更，需要重新信任。"
		STATUS_DISABLED:
			return "Codex 已停用桌寵 Hook，請在 /hooks 重新啟用。"
		STATUS_MISSING:
			return "Codex 找不到桌寵的 Stop Hook。"
		STATUS_UNAVAILABLE:
			return "找不到支援 Hook 審查的 Codex CLI。"
		STATUS_ERROR:
			return "無法查詢 Codex Hook 狀態。%s" % (
				" " + detail if not detail.is_empty() else ""
			)
		_:
			return "Codex 尚未信任目前的桌寵 Hook。"


func _result(status: String, message: String) -> Dictionary:
	return {
		"status": status,
		"message": message,
		"enabled": false,
		"trust_status": "",
	}
