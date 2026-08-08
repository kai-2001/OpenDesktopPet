$ErrorActionPreference = 'SilentlyContinue'

# Claude Code hook bridge for OpenDesktopPet.
# Claude Code CLI, the VS Code extension, and Claude Desktop Code sessions
# share the same user hook configuration. This bridge classifies the local
# host, sends only a fixed status payload, and never blocks Claude Code.
$notifyHost = '127.0.0.1'
$notifyPort = 38571
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$portFile = Join-Path $integrationHome 'open_desktop_pet_notify_port.txt'
$claudeAppPathFile = Join-Path $integrationHome 'open_desktop_pet_claude_app_executable_path.txt'
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-claude-code-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect Claude Code.
    }
}

function Get-ProcessExecutablePath($process) {
    if (-not [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
        return [string]$process.ExecutablePath
    }
    $commandLine = [string]$process.CommandLine
    if ($commandLine -match '^"([^"]+)"') {
        return $matches[1]
    }
    return ''
}

function Normalize-PathText([string]$path) {
    return $path.Trim().Trim('"').Replace('/', '\')
}

function Test-ClaudeDesktopPath([string]$path) {
    $normalizedPath = Normalize-PathText $path
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $false
    }
    $fileName = [System.IO.Path]::GetFileName($normalizedPath)
    return $fileName -ieq 'Claude.exe' -or
        $fileName -ieq 'Claude Desktop.exe' -or
        $normalizedPath -match '(?i)[\/]Claude([ _-]?Desktop)?[\/]'
}

function Test-ClaudeDesktopProcess {
    $configuredPath = ''
    if (Test-Path -LiteralPath $claudeAppPathFile) {
        $rawConfiguredPath = Get-Content -LiteralPath $claudeAppPathFile -Raw
        if ($null -ne $rawConfiguredPath) {
            $configuredPath = Normalize-PathText $rawConfiguredPath
        }
    }
    try {
        $parentId = $PID
        for ($index = 0; $index -lt 10 -and $parentId -gt 0; $index++) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId"
            if ($null -eq $process) {
                break
            }
            $candidatePath = Normalize-PathText (Get-ProcessExecutablePath $process)
            if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and
                (Test-ClaudeDesktopPath $configuredPath) -and
                [string]::Equals(
                    $candidatePath,
                    $configuredPath,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                return $true
            }
            $candidateFileName = [System.IO.Path]::GetFileName($candidatePath)
            if ($candidateFileName -ieq 'Claude.exe' -or
                $candidateFileName -ieq 'Claude Desktop.exe') {
                return $true
            }
            $commandLine = [string]$process.CommandLine
            if ($commandLine -match '(?i)Claude([ _-]?Desktop)') {
                return $true
            }
            $parentId = [int]$process.ParentProcessId
        }
    } catch {
        # Process inspection is only a routing hint.
    }
    return $false
}

function Test-VsCodeProcess {
    try {
        $parentId = $PID
        for ($index = 0; $index -lt 10 -and $parentId -gt 0; $index++) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId"
            if ($null -eq $process) {
                break
            }
            $candidatePath = Get-ProcessExecutablePath $process
            if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and
                [string]::Equals(
                    [System.IO.Path]::GetFileName($candidatePath.Trim().Trim('"')),
                    'Code.exe',
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                return $true
            }
            $parentId = [int]$process.ParentProcessId
        }
    } catch {
        # Process inspection is only a routing hint.
    }
    return $false
}

function Get-ClaudeTarget {
    $forcedTarget = ([string]$env:OPEN_DESKTOP_PET_CLAUDE_TARGET).ToLowerInvariant()
    if ($forcedTarget -eq 'vscode') {
        return [ordered]@{
            target_app = 'vscode'
            target_executable = 'Code.exe'
            enabled_file = 'open_desktop_pet_claude_vscode_enabled.txt'
        }
    }
    if ($forcedTarget -eq 'claude_app') {
        return [ordered]@{
            target_app = 'claude_app'
            target_executable = 'Claude.exe'
            enabled_file = 'open_desktop_pet_claude_app_enabled.txt'
        }
    }
    if ($forcedTarget -eq 'terminal') {
        return [ordered]@{
            target_app = 'terminal'
            target_executable = 'WindowsTerminal.exe'
            enabled_file = 'open_desktop_pet_claude_terminal_enabled.txt'
        }
    }

    $isVsCodeEnvironment =
        ([string]$env:TERM_PROGRAM).ToLowerInvariant() -eq 'vscode' -or
        -not [string]::IsNullOrWhiteSpace([string]$env:VSCODE_PID) -or
        (Test-VsCodeProcess)
    if ($isVsCodeEnvironment) {
        return [ordered]@{
            target_app = 'vscode'
            target_executable = 'Code.exe'
            enabled_file = 'open_desktop_pet_claude_vscode_enabled.txt'
        }
    }
    if (Test-ClaudeDesktopProcess) {
        return [ordered]@{
            target_app = 'claude_app'
            target_executable = 'Claude.exe'
            enabled_file = 'open_desktop_pet_claude_app_enabled.txt'
        }
    }
    return [ordered]@{
        target_app = 'terminal'
        target_executable = 'WindowsTerminal.exe'
        enabled_file = 'open_desktop_pet_claude_terminal_enabled.txt'
    }
}

function Test-ClaudeEnabled([string]$flagName) {
    $candidates = @(
        (Join-Path $integrationHome $flagName),
        (Join-Path (Join-Path $env:USERPROFILE '.claude') $flagName)
    )
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

function Get-EventHash([string]$value) {
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } catch {
        return $value.GetHashCode().ToString()
    }
}

function Read-ConfiguredPort {
    if (-not (Test-Path -LiteralPath $portFile)) {
        return
    }
    try {
        $configuredPort = [int](Get-Content -LiteralPath $portFile -Raw).Trim()
        if ($configuredPort -ge 1024 -and $configuredPort -le 65535) {
            $script:notifyPort = $configuredPort
        }
    } catch {
        # Keep the default port when the optional setting is invalid.
    }
}

function Read-StandardInputUtf8 {
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

try {
    $rawInput = Read-StandardInputUtf8
    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        Write-NotifyLog 'ignored reason=missing-input'
        exit 0
    }
    $rawInput = $rawInput.TrimStart([char]0xFEFF)
    $event = ConvertFrom-Json -InputObject $rawInput
    if ($null -eq $event) {
        Write-NotifyLog 'ignored reason=invalid-json'
        exit 0
    }

    $hookEvent = [string]$event.hook_event_name
    $eventType = ''
    switch ($hookEvent) {
        'Stop' {
            if ([bool]$event.stop_hook_active) {
                Write-NotifyLog 'ignored reason=stop-hook-already-active'
                exit 0
            }
            $eventType = 'agent-turn-complete'
        }
        'StopFailure' {
            $eventType = 'agent-error'
        }
        'Notification' {
            $notificationType = [string]$event.notification_type
            if ($notificationType -eq 'agent_completed') {
                $eventType = 'agent-turn-complete'
            } else {
                $eventType = 'approval-requested'
            }
        }
        default {
            Write-NotifyLog ("ignored reason=unsupported-event event={0}" -f $hookEvent)
            exit 0
        }
    }

    $target = Get-ClaudeTarget
    if (-not (Test-ClaudeEnabled $target.enabled_file)) {
        Write-NotifyLog ("ignored reason=desktop-pet-disabled target={0}" -f $target.target_app)
        exit 0
    }
    Read-ConfiguredPort

    $sessionId = [string]$event.session_id
    $identityText = "{0}|{1}|{2}|{3}|{4}" -f `
        $sessionId, $hookEvent, [string]$event.notification_type,
        [string]$event.last_assistant_message, [string]$event.message
    $eventId = "claude:{0}:{1}" -f $target.target_app, (Get-EventHash $identityText)
    $payload = [ordered]@{
        schema_version = 1
        type = $eventType
        source = 'claude_code'
        agent = 'claude'
        target_app = $target.target_app
        target_platform = $target.target_app
        target_executable = $target.target_executable
        event_id = $eventId
        thread_id = ''
        turn_id = ''
        session_id = $sessionId
        cwd = [string]$event.cwd
        hook_event = $hookEvent
        notification_type = [string]$event.notification_type
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog ("sent type={0} target={1} port={2}" -f $eventType, $target.target_app, $notifyPort)
} catch {
    Write-NotifyLog ("failed error-type={0} message={1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
}

exit 0
