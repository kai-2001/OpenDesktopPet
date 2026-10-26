class_name AgentChannelCatalog
extends RefCounted

# One entry per Agent notification switch. Adding an Agent means adding its
# channel (and its setup, if it has a new installer) here; the controller,
# settings file, runtime registration and Agent tab all iterate this catalog.

const AgentNotificationRouterScript = preload("res://scripts/agent_notification_router.gd")
const TARGET_VSCODE := AgentNotificationRouterScript.TARGET_VSCODE
const TARGET_CODEX_APP := AgentNotificationRouterScript.TARGET_CODEX_APP
const TARGET_TERMINAL := AgentNotificationRouterScript.TARGET_TERMINAL
const TARGET_OPENCODE_APP := AgentNotificationRouterScript.TARGET_OPENCODE_APP
const TARGET_CLAUDE_APP := AgentNotificationRouterScript.TARGET_CLAUDE_APP

const SETUP_CODEX := "codex"
const SETUP_COPILOT := "copilot"
const SETUP_OPENCODE := "opencode"
const SETUP_CLAUDE_CODE := "claude_code"
const SETUP_GEMINI_CLI := "gemini_cli"
const SETUP_ANTIGRAVITY_CLI := "antigravity_cli"
const SETUP_PI := "pi"

# Installer and the name reported when a startup reinstall fails, in the
# order startup checks them.
const SETUPS := {
	SETUP_CODEX: {
		"installer": "install_codex_integration.ps1",
		"failure_name": "Codex",
	},
	SETUP_COPILOT: {
		"installer": "install_copilot_integration.ps1",
		"failure_name": "VS Code Copilot",
	},
	SETUP_OPENCODE: {
		"installer": "install_opencode_integration.ps1",
		"failure_name": "終端機 OpenCode",
	},
	SETUP_CLAUDE_CODE: {
		"installer": "install_claude_code_integration.ps1",
		"failure_name": "Claude Code",
	},
	SETUP_GEMINI_CLI: {
		"installer": "install_gemini_cli_integration.ps1",
		"failure_name": "Gemini CLI 終端機",
	},
	SETUP_ANTIGRAVITY_CLI: {
		"installer": "install_antigravity_cli_integration.ps1",
		"failure_name": "Antigravity CLI 終端機",
	},
	SETUP_PI: {
		"installer": "install_pi_integration.ps1",
		"failure_name": "Pi",
	},
}

# Executable each notification target switches back to, in Agent tab order.
const TARGETS := [
	{
		"target": TARGET_VSCODE,
		"property": "executable_path",
		"title": "VS Code",
		"node_prefix": "Vscode",
		"placeholder": "選擇 Code.exe",
		"dialog_title": "選擇 VS Code 執行檔",
		"required": true,
	},
	{
		"target": TARGET_CODEX_APP,
		"property": "codex_app_executable_path",
		"title": "ChatGPT",
		"node_prefix": "CodexApp",
		"placeholder": "選擇 ChatGPT.exe",
		"dialog_title": "選擇 ChatGPT 執行檔",
		"required": true,
	},
	{
		"target": TARGET_OPENCODE_APP,
		"property": "opencode_app_executable_path",
		"title": "OpenCode",
		"node_prefix": "OpenCodeApp",
		"placeholder": "選擇 OpenCode Desktop.exe",
		"dialog_title": "選擇 OpenCode Desktop 執行檔",
		"required": false,
	},
	{
		"target": TARGET_CLAUDE_APP,
		"property": "claude_app_executable_path",
		"title": "Claude",
		"node_prefix": "ClaudeApp",
		"placeholder": "選擇 Claude.exe",
		"dialog_title": "選擇 Claude Code 執行檔",
		"required": false,
	},
	{
		"target": TARGET_TERMINAL,
		"property": "terminal_executable_path",
		"title": "終端機",
		"node_prefix": "Terminal",
		"placeholder": "選擇 WindowsTerminal.exe",
		"dialog_title": "選擇終端機執行檔",
		"required": false,
	},
]

# `property` is the controller field, `settings_section` the ui_settings.cfg
# section and `runtime_key` the name the notification bridges read. Codex
# channels use `setup_name` in their trust messages; other setups report it
# when enabling fails.
const CHANNELS := [
	{
		"id": "codex",
		"property": "codex_enabled",
		"settings_section": "codex",
		"runtime_key": "codex_vscode",
		"target": TARGET_VSCODE,
		"setup": SETUP_CODEX,
		"setup_name": "VS Code",
		"label": "Codex",
		"node_name": "CodexEnabledToggle",
		"tooltip": "開啟或關閉 VS Code 中的 Codex 通知",
	},
	{
		"id": "claude_vscode",
		"property": "claude_vscode_enabled",
		"settings_section": "claude_code_vscode",
		"runtime_key": "claude_vscode",
		"target": TARGET_VSCODE,
		"setup": SETUP_CLAUDE_CODE,
		"setup_name": "Claude Code",
		"label": "Claude Code",
		"node_name": "ClaudeCodeVscodeEnabledToggle",
		"tooltip": "開啟或關閉 VS Code 中的 Claude Code 通知",
	},
	{
		"id": "copilot",
		"property": "copilot_enabled",
		"settings_section": "copilot",
		"runtime_key": "copilot",
		"target": TARGET_VSCODE,
		"setup": SETUP_COPILOT,
		"setup_name": "VS Code Copilot",
		"label": "Copilot",
		"node_name": "CopilotEnabledToggle",
		"tooltip": "開啟或關閉 Copilot Agent 通知",
	},
	{
		"id": "vscode_opencode",
		"property": "vscode_opencode_enabled",
		"settings_section": "opencode_vscode",
		"runtime_key": "opencode_vscode",
		"target": TARGET_VSCODE,
		"setup": SETUP_OPENCODE,
		"setup_name": "終端機 OpenCode",
		"label": "OpenCode",
		"node_name": "VscodeOpenCodeEnabledToggle",
		"tooltip": "開啟或關閉 VS Code 中的 OpenCode 通知",
	},
	{
		"id": "codex_app",
		"property": "codex_app_enabled",
		"settings_section": "codex_app",
		"runtime_key": "codex_app",
		"target": TARGET_CODEX_APP,
		"setup": SETUP_CODEX,
		"setup_name": "ChatGPT",
		"label": "Codex",
		"node_name": "CodexAppEnabledToggle",
		"tooltip": "開啟或關閉 ChatGPT 中的 Codex 通知",
	},
	{
		"id": "opencode_app",
		"property": "opencode_app_enabled",
		"settings_section": "opencode_app",
		"runtime_key": "opencode_app",
		"target": TARGET_OPENCODE_APP,
		"setup": SETUP_OPENCODE,
		"setup_name": "終端機 OpenCode",
		"label": "OpenCode",
		"node_name": "OpenCodeAppEnabledToggle",
		"tooltip": "開啟或關閉 OpenCode Desktop 通知",
	},
	{
		"id": "claude_app",
		"property": "claude_app_enabled",
		"settings_section": "claude_code_app",
		"runtime_key": "claude_app",
		"target": TARGET_CLAUDE_APP,
		"setup": SETUP_CLAUDE_CODE,
		"setup_name": "Claude Desktop",
		"label": "Claude Code",
		"node_name": "ClaudeDesktopEnabledToggle",
		"tooltip": "開啟或關閉 Claude Desktop Code 通知",
	},
	{
		"id": "terminal_codex",
		"property": "terminal_codex_enabled",
		"settings_section": "codex_terminal",
		"runtime_key": "codex_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_CODEX,
		"setup_name": "終端機",
		"label": "Codex",
		"node_name": "TerminalCodexEnabledToggle",
		"tooltip": "開啟或關閉終端機中的 Codex CLI 通知",
	},
	{
		"id": "pi_codex",
		"property": "pi_codex_enabled",
		"settings_section": "pi_codex_terminal",
		"runtime_key": "pi_codex_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_PI,
		"setup_name": "Pi",
		"label": "Pi",
		"node_name": "PiCodexEnabledToggle",
		"tooltip": "開啟或關閉 Pi 中所有模型的通知",
	},
	{
		"id": "terminal_opencode",
		"property": "terminal_opencode_enabled",
		"settings_section": "opencode_terminal",
		"runtime_key": "opencode_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_OPENCODE,
		"setup_name": "終端機 OpenCode",
		"label": "OpenCode",
		"node_name": "TerminalOpenCodeEnabledToggle",
		"tooltip": "開啟或關閉終端機中的 OpenCode 通知",
	},
	{
		"id": "gemini_terminal",
		"property": "gemini_terminal_enabled",
		"settings_section": "gemini_terminal",
		"runtime_key": "gemini_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_GEMINI_CLI,
		"setup_name": "Gemini CLI 終端機",
		"label": "Gemini CLI（舊版）",
		"node_name": "GeminiCliTerminalEnabledToggle",
		"tooltip": "開啟或關閉終端機中的 Gemini CLI 舊版通知（企業/API Key）",
	},
	{
		"id": "agy_terminal",
		"property": "agy_terminal_enabled",
		"settings_section": "agy_terminal",
		"runtime_key": "agy_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_ANTIGRAVITY_CLI,
		"setup_name": "Antigravity CLI 終端機",
		"label": "Antigravity CLI",
		"node_name": "AgyTerminalEnabledToggle",
		"tooltip": "開啟或關閉終端機中的 Antigravity CLI 通知",
	},
	{
		"id": "claude_terminal",
		"property": "claude_terminal_enabled",
		"settings_section": "claude_code_terminal",
		"runtime_key": "claude_terminal",
		"target": TARGET_TERMINAL,
		"setup": SETUP_CLAUDE_CODE,
		"setup_name": "Claude 終端機",
		"label": "Claude Code",
		"node_name": "ClaudeCodeTerminalEnabledToggle",
		"tooltip": "開啟或關閉終端機中的 Claude Code 通知",
	},
]


static func channel(channel_id: String) -> Dictionary:
	for entry: Dictionary in CHANNELS:
		if entry["id"] == channel_id:
			return entry
	return {}


static func channels_for_target(target: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for entry: Dictionary in CHANNELS:
		if entry["target"] == target:
			matches.append(entry)
	return matches


static func channels_for_setup(setup: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for entry: Dictionary in CHANNELS:
		if entry["setup"] == setup:
			matches.append(entry)
	return matches


static func codex_channel_for_target(target: String) -> Dictionary:
	for entry: Dictionary in channels_for_setup(SETUP_CODEX):
		if entry["target"] == target:
			return entry
	return {}
