$ErrorActionPreference = 'SilentlyContinue'

# OpenDesktopPet runtime schema v1
# Gemini CLI hook bridge for OpenDesktopPet.
# Gemini CLI sends hook JSON on stdin. The bridge sends a small UDP status
# payload and returns a valid empty JSON object so it never changes the agent.
$notifyHost = '127.0.0.1'
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$runtimeHelperPath = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
    $runtimeHelperPath = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-gemini-cli-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect Gemini CLI.
    }
}

function Complete-GeminiHook {
    [Console]::Out.WriteLine('{}')
    exit 0
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
    if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
        Write-NotifyLog 'ignored reason=runtime-helper-missing'
        Complete-GeminiHook
    }
    . $runtimeHelperPath
    $rawInput = Read-StandardInputUtf8
    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        Write-NotifyLog 'ignored reason=missing-input'
        Complete-GeminiHook
    }
    $rawInput = $rawInput.TrimStart([char]0xFEFF)
    $event = ConvertFrom-Json -InputObject $rawInput
    if ($null -eq $event) {
        Write-NotifyLog 'ignored reason=invalid-json'
        Complete-GeminiHook
    }

    $hookEvent = [string]$event.hook_event_name
    $notificationType = [string]$event.notification_type
    $eventType = ''
    switch ($hookEvent) {
        'AfterAgent' {
            $eventType = 'agent-turn-complete'
        }
        'Notification' {
            if ($notificationType -ieq 'ToolPermission') {
                $eventType = 'approval-requested'
            } else {
                Write-NotifyLog ("ignored reason=unsupported-notification type={0}" -f $notificationType)
                Complete-GeminiHook
            }
        }
        default {
            Write-NotifyLog ("ignored reason=unsupported-event event={0}" -f $hookEvent)
            Complete-GeminiHook
        }
    }

    $runtime = Get-OpenDesktopPetRuntime -IntegrationHome $integrationHome
    if ($null -eq $runtime) {
        Write-NotifyLog 'ignored reason=runtime-unavailable'
        Complete-GeminiHook
    }
    if (-not (Test-OpenDesktopPetRuntimeEnabled -Runtime $runtime -Target 'gemini_terminal')) {
        Write-NotifyLog 'ignored reason=desktop-pet-disabled'
        Complete-GeminiHook
    }
    $notifyPort = Get-OpenDesktopPetRuntimePort -Runtime $runtime

    $sessionId = [string]$event.session_id
    $identityText = "{0}|{1}|{2}|{3}|{4}" -f `
        $sessionId, $hookEvent, $notificationType, [string]$event.timestamp,
        [string]$event.message
    $eventId = 'gemini:terminal:{0}' -f (Get-EventHash $identityText)
    $payload = [ordered]@{
        schema_version = 1
        type = $eventType
        source = 'gemini_cli'
        agent = 'gemini'
        target_app = 'terminal'
        target_platform = 'terminal'
        target_executable = 'WindowsTerminal.exe'
        event_id = $eventId
        thread_id = ''
        turn_id = ''
        session_id = $sessionId
        cwd = [string]$event.cwd
        hook_event = $hookEvent
        notification_type = $notificationType
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog ("sent type={0} port={1}" -f $eventType, $notifyPort)
} catch {
    Write-NotifyLog ("failed error-type={0} message={1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
}

Complete-GeminiHook
