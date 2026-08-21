$ErrorActionPreference = 'SilentlyContinue'

# OpenDesktopPet runtime schema v1
# Codex Stop-hook bridge. Codex owns the hook lifecycle; this file only
# classifies the host and translates one completed chat turn to the shared
# OpenDesktopPet runtime payload.
$notifyHost = '127.0.0.1'
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$runtimeHelperPath = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
	$runtimeHelperPath = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-codex-stop-hook.log'

function Write-HookLog([string]$message) {
	try {
		Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
			'[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
		)
	} catch {
		# Diagnostics must never affect Codex.
	}
}

function Read-StopHookInput {
	# Codex writes UTF-8 JSON to stdin. Windows PowerShell otherwise decodes
	# redirected stdin with the active legacy console code page, which can turn
	# Chinese assistant text into invalid JSON escape sequences.
	$inputStream = [Console]::OpenStandardInput()
	$memoryStream = New-Object System.IO.MemoryStream
	$buffer = New-Object -TypeName byte[] -ArgumentList 4096
	try {
		while (($readCount = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
			$memoryStream.Write($buffer, 0, $readCount)
		}
		return [System.Text.Encoding]::UTF8.GetString($memoryStream.ToArray())
	} finally {
		$memoryStream.Dispose()
	}
}

function Test-ProcessTree([scriptblock]$matchesProcess) {
	if ([string]$env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE -eq '1') {
		return $false
	}
	try {
		$parentId = $PID
		for ($index = 0; $index -lt 8 -and $parentId -gt 0; $index++) {
			$process = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId"
			if ($null -eq $process) {
				break
			}
			if (& $matchesProcess ([string]$process.Name) ([string]$process.CommandLine)) {
				return $true
			}
			$parentId = [int]$process.ParentProcessId
		}
	} catch {
		# Process inspection is only a routing hint.
	}
	return $false
}

function Test-ProcessTreeContainsCodexApp {
	return Test-ProcessTree {
		param([string]$processName, [string]$commandLine)
		$processName -match '(?i)^chatgpt\.exe$' -or
			$commandLine -match (
				'(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\(?:ChatGPT|Codex)\.exe'
			)
	}
}

function Test-ProcessTreeContainsVsCode {
	return Test-ProcessTree {
		param([string]$processName, [string]$commandLine)
		$processName -match '(?i)^(code|code-insiders)\.exe$' -or
			$commandLine -match '(?i)\\Microsoft VS Code\\'
	}
}

function Get-CodexTarget([object]$event) {
	$isVsCodeEnvironment =
		([string]$env:TERM_PROGRAM).ToLowerInvariant() -eq 'vscode' -or
		-not [string]::IsNullOrWhiteSpace([string]$env:VSCODE_PID) -or
		(Test-ProcessTreeContainsVsCode)
	if ($isVsCodeEnvironment) {
		return [ordered]@{
			source = 'codex_vscode'
			target_app = 'vscode'
			target_executable = 'Code.exe'
			runtime_target = 'codex_vscode'
		}
	}

	$cwd = [string]$event.cwd
	if ($cwd -match '(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\' -or
		(Test-ProcessTreeContainsCodexApp)) {
		return [ordered]@{
			source = 'codex_app'
			target_app = 'codex_app'
			target_executable = 'ChatGPT.exe'
			runtime_target = 'codex_app'
		}
	}

	return [ordered]@{
		source = 'codex_cli'
		target_app = 'terminal'
		target_executable = 'WindowsTerminal.exe'
		runtime_target = 'codex_terminal'
	}
}

try {
	if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
		Write-HookLog 'ignored reason=runtime-helper-missing'
		exit 0
	}
	. $runtimeHelperPath
	$eventJson = Read-StopHookInput
	$eventJson = $eventJson.TrimStart([char]0xFEFF)
	if ([string]::IsNullOrWhiteSpace($eventJson)) {
		Write-HookLog 'ignored reason=missing-stdin'
		exit 0
	}

	$event = ConvertFrom-Json -InputObject $eventJson
	if ($null -eq $event -or [string]$event.hook_event_name -ne 'Stop') {
		Write-HookLog 'ignored reason=unsupported-event'
		exit 0
	}

	$runtime = Get-OpenDesktopPetRuntime -IntegrationHome $integrationHome
	if ($null -eq $runtime) {
		Write-HookLog 'ignored reason=runtime-unavailable'
		exit 0
	}
	$target = Get-CodexTarget $event
	$isEnabled = Test-OpenDesktopPetRuntimeEnabled -Runtime $runtime -Target $target.runtime_target
	Write-HookLog (
		'event hook={0} cwd={1} source={2} target={3} enabled={4}' -f
		[string]$event.hook_event_name, [string]$event.cwd,
		$target.source, $target.target_app, $isEnabled
	)
	if (-not $isEnabled) {
		exit 0
	}

	$notifyPort = Get-OpenDesktopPetRuntimePort -Runtime $runtime
	$payload = [ordered]@{
		schema_version = 1
		type = 'agent-turn-complete'
		source = $target.source
		agent = 'codex'
		target_app = $target.target_app
		target_platform = $target.target_app
		target_executable = $target.target_executable
		event_id = 'codex:{0}:{1}:{2}' -f (
			$target.target_app, [string]$event.session_id, [string]$event.turn_id
		)
		thread_id = [string]$event.session_id
		turn_id = [string]$event.turn_id
		session_id = [string]$event.session_id
		cwd = [string]$event.cwd
	} | ConvertTo-Json -Compress

	$udp = [System.Net.Sockets.UdpClient]::new()
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
	[void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
	$udp.Dispose()
	Write-HookLog ('sent status=agent-turn-complete port={0}' -f $notifyPort)
} catch {
	Write-HookLog (
		'failed error-type={0} message={1}' -f
		$_.Exception.GetType().Name, $_.Exception.Message
	)
	# A pet notification must never make a Codex turn fail.
	exit 0
}

exit 0
