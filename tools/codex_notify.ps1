$ErrorActionPreference = 'SilentlyContinue'

# Shared Codex bridge. Codex App, VS Code Codex, and Codex CLI all use this
# file through the user's .codex/config.toml. The bridge classifies the host
# before applying the corresponding desktop-pet flag.
$notifyHost = '127.0.0.1'
$notifyPort = 38571
$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $env:USERPROFILE '.codex'
} else {
    $env:CODEX_HOME
}
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$portFile = Join-Path $integrationHome 'open_desktop_pet_notify_port.txt'
$legacyEnabledFile = Join-Path $integrationHome 'open_desktop_pet_codex_enabled.txt'
if (-not (Test-Path -LiteralPath $legacyEnabledFile)) {
    $legacyEnabledFile = Join-Path $codexHome 'open_desktop_pet_notify_enabled.txt'
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-codex-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect Codex.
    }
}

function Get-ProcessTreeContainsCodexApp {
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
            $processName = [string]$process.Name
            $commandLine = [string]$process.CommandLine
			# The Codex CLI can also run as `codex.exe`. Only classify an ancestor
			# as the desktop app when it is ChatGPT.exe or clearly inside the
			# OpenAI Codex App package; otherwise terminal sessions are misrouted
			# to ChatGPT.
			$isChatGptProcess = $processName -match '(?i)^chatgpt\.exe$'
			$isCodexAppProcess = $commandLine -match (
				'(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\(?:ChatGPT|Codex)\.exe'
			)
			if ($isChatGptProcess -or $isCodexAppProcess) {
				return $true
			}
            $parentId = [int]$process.ParentProcessId
        }
    } catch {
        # Process inspection is only a source hint; never block the hook.
    }
    return $false
}

function Get-CodexTarget([object]$event) {
	$cwd = [string]$event.cwd
	if ($cwd -match '(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\' -or
		(Get-ProcessTreeContainsCodexApp)) {
		return [ordered]@{ source = 'codex_app'; target_app = 'codex_app'; flag = 'open_desktop_pet_codex_app_enabled.txt' }
	}

	$isVsCodeEnvironment =
		([string]$env:TERM_PROGRAM).ToLowerInvariant() -eq 'vscode' -or
		-not [string]::IsNullOrWhiteSpace([string]$env:VSCODE_PID)
	if ($isVsCodeEnvironment) {
		return [ordered]@{ source = 'codex_vscode'; target_app = 'vscode'; flag = 'open_desktop_pet_vscode_codex_enabled.txt' }
	}

	return [ordered]@{ source = 'codex_cli'; target_app = 'terminal'; flag = 'open_desktop_pet_terminal_codex_enabled.txt' }
}

function Read-BridgeFlag([string]$flagName, [bool]$allowLegacyFallback = $false) {
    $candidates = @(
        (Join-Path $integrationHome $flagName),
        (Join-Path $codexHome $flagName)
    )
    if ($allowLegacyFallback) {
        $candidates += $legacyEnabledFile
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        try {
            return (Get-Content -LiteralPath $candidate -Raw).Trim() -eq '1'
        } catch {
            return $false
        }
    }
    return $false
}

try {
    Write-NotifyLog ("invoked args={0}" -f $args.Count)
    if ($args.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$args[0])) {
        Write-NotifyLog 'ignored reason=missing-argument'
        exit 0
    }

    $event = ConvertFrom-Json -InputObject ([string]$args[0])
    if ($null -eq $event -or $event.type -ne 'agent-turn-complete') {
        Write-NotifyLog 'ignored reason=unsupported-event'
        exit 0
    }

    $target = Get-CodexTarget $event
    $isEnabled = Read-BridgeFlag $target.flag ($target.target_app -eq 'vscode')
    Write-NotifyLog (
        "event type={0} cwd={1} source={2} target={3} enabled={4}" -f
        [string]$event.type, [string]$event.cwd, $target.source, $target.target_app, $isEnabled
    )
    if (-not $isEnabled) {
        exit 0
    }

    if (Test-Path -LiteralPath $portFile) {
        try {
            $configuredPort = [int](Get-Content -LiteralPath $portFile -Raw).Trim()
            if ($configuredPort -ge 1024 -and $configuredPort -le 65535) {
                $notifyPort = $configuredPort
            }
        } catch {
            # Keep the default port when the optional setting is invalid.
        }
    }

    # Forward only a fixed status payload, never transcript or source content.
    $payload = [ordered]@{
        type = 'agent-turn-complete'
        source = $target.source
        agent = 'codex'
        target_app = $target.target_app
        thread_id = [string]$event.'thread-id'
        turn_id = [string]$event.'turn-id'
        cwd = [string]$event.cwd
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog ("sent status=agent-turn-complete port={0}" -f $notifyPort)
} catch {
	Write-NotifyLog ("failed error-type={0} message={1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
    # A pet notification must never make a Codex turn fail.
    exit 0
}

exit 0
