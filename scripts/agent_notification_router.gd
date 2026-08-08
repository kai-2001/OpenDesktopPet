class_name AgentNotificationRouter
extends RefCounted

## Pure routing rules shared by the local Agent notification receiver.
## File installation, process detection, window focus, and UI state remain
## outside this class so a new Agent does not need to modify every concern.

const TARGET_VSCODE := "vscode"
const TARGET_CODEX_APP := "codex_app"
const TARGET_TERMINAL := "terminal"
const TARGET_OPENCODE_APP := "opencode_app"
const TARGET_CLAUDE_APP := "claude_app"


static func normalize_agent(value: String) -> String:
	var candidate := value.to_lower()
	if candidate.contains("copilot"):
		return "copilot"
	if candidate.contains("opencode"):
		return "opencode"
	if candidate.contains("claude"):
		return "claude"
	if candidate.contains("antigravity") or candidate == "agy" or candidate.contains("agy_cli"):
		return "agy"
	if candidate.contains("gemini"):
		return "gemini"
	return "codex"


static func normalize_target_app(value: String) -> String:
	match value:
		TARGET_CODEX_APP, "app":
			return TARGET_CODEX_APP
		TARGET_OPENCODE_APP, "opencode-desktop":
			return TARGET_OPENCODE_APP
		TARGET_CLAUDE_APP, "claude-desktop":
			return TARGET_CLAUDE_APP
		TARGET_TERMINAL, "shell", "powershell", "cmd":
			return TARGET_TERMINAL
		_:
			return TARGET_VSCODE


static func display_name(source: String, agent: String) -> String:
	if source == "copilot" or agent == "copilot":
		return "Copilot"
	if source == "opencode" or agent == "opencode":
		return "OpenCode"
	if source == "claude" or agent == "claude":
		return "Claude Code"
	if source == "antigravity_cli" or source == "agy" or agent == "agy":
		return "Antigravity CLI"
	if source == "gemini" or agent == "gemini":
		return "Gemini CLI（舊版）"
	return "Codex"


static func target_display_name(target_app: String) -> String:
	match target_app:
		TARGET_CODEX_APP:
			return "ChatGPT"
		TARGET_OPENCODE_APP:
			return "OpenCode"
		TARGET_CLAUDE_APP:
			return "Claude Desktop"
		TARGET_TERMINAL:
			return "終端機"
		_:
			return "VS Code"


static func notification_key(source: String, agent: String, target_app: String) -> String:
	if source == "copilot" or agent == "copilot":
		return "copilot"
	if source == "opencode" or agent == "opencode":
		match target_app:
			TARGET_OPENCODE_APP:
				return "opencode_app"
			TARGET_VSCODE:
				return "opencode_vscode"
			_:
				return "opencode_terminal"
	if source == "claude" or agent == "claude":
		match target_app:
			TARGET_CLAUDE_APP:
				return "claude_app"
			TARGET_VSCODE:
				return "claude_vscode"
			_:
				return "claude_terminal"
	if source == "antigravity_cli" or source == "agy" or agent == "agy":
		return "agy_terminal"
	if source == "gemini" or agent == "gemini":
		return "gemini_terminal"
	match target_app:
		TARGET_CODEX_APP:
			return "codex_app"
		TARGET_TERMINAL:
			return "codex_terminal"
		_:
			return "codex_vscode"


static func is_notification_enabled(
	source: String, agent: String, target_app: String, enabled_by_key: Dictionary
) -> bool:
	return bool(enabled_by_key.get(notification_key(source, agent, target_app), false))
