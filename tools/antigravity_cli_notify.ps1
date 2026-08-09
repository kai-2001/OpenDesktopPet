$ErrorActionPreference = 'SilentlyContinue'

# OpenDesktopPet runtime schema v1
# Antigravity CLI Stop hook bridge for OpenDesktopPet.
# Antigravity sends hook JSON on stdin. The bridge emits a small UDP status
# payload and returns a harmless decision so it never changes the agent flow.
$notifyHost = '127.0.0.1'
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$runtimeHelperPath = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
    $runtimeHelperPath = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-antigravity-cli-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect Antigravity CLI.
    }
}

function Complete-AgyHook {
    [Console]::Out.WriteLine('{"decision":"allow"}')
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
        Complete-AgyHook
    }
    . $runtimeHelperPath
    $rawInput = Read-StandardInputUtf8
    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        Write-NotifyLog 'ignored reason=missing-input'
        Complete-AgyHook
    }
    $rawInput = $rawInput.TrimStart([char]0xFEFF)
    $event = ConvertFrom-Json -InputObject $rawInput
    if ($null -eq $event) {
        Write-NotifyLog 'ignored reason=invalid-json'
        Complete-AgyHook
    }

    $terminationReason = [string]$event.terminationReason
    $eventError = [string]$event.error
    $fullyIdle = $true
    if ($null -ne $event.PSObject.Properties['fullyIdle']) {
        $fullyIdle = [bool]$event.fullyIdle
    }
    if (-not $fullyIdle) {
        Write-NotifyLog 'ignored reason=background-work-still-active'
        Complete-AgyHook
    }

    $eventType = 'agent-turn-complete'
    if (-not [string]::IsNullOrWhiteSpace($eventError) -or
        $terminationReason -ieq 'error' -or
        $terminationReason -ieq 'max_steps_exceeded') {
        $eventType = 'agent-error'
    }

    $runtime = Get-OpenDesktopPetRuntime -IntegrationHome $integrationHome
    if ($null -eq $runtime) {
        Write-NotifyLog 'ignored reason=runtime-unavailable'
        Complete-AgyHook
    }
    if (-not (Test-OpenDesktopPetRuntimeEnabled -Runtime $runtime -Target 'agy_terminal')) {
        Write-NotifyLog 'ignored reason=desktop-pet-disabled'
        Complete-AgyHook
    }
    $notifyPort = Get-OpenDesktopPetRuntimePort -Runtime $runtime

    $conversationId = [string]$event.conversationId
    $executionNum = [string]$event.executionNum
    $identityText = '{0}|{1}|{2}|{3}|{4}' -f `
        $conversationId, $executionNum, $terminationReason, $eventError, $fullyIdle
    $eventId = 'agy:terminal:{0}' -f (Get-EventHash $identityText)
    $workspacePaths = @($event.workspacePaths)
    $cwd = if ($workspacePaths.Count -gt 0) { [string]$workspacePaths[0] } else { '' }
    $payload = [ordered]@{
        schema_version = 1
        type = $eventType
        source = 'antigravity_cli'
        agent = 'agy'
        target_app = 'terminal'
        target_platform = 'terminal'
        target_executable = 'WindowsTerminal.exe'
        event_id = $eventId
        thread_id = $conversationId
        turn_id = $executionNum
        session_id = $conversationId
        cwd = $cwd
        hook_event = 'Stop'
        termination_reason = $terminationReason
        fully_idle = $fullyIdle
    } | ConvertTo-Json -Compress

    $udp = New-Object System.Net.Sockets.UdpClient
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog ('sent type={0} port={1}' -f $eventType, $notifyPort)
} catch {
    Write-NotifyLog ('failed error-type={0} message={1}' -f $_.Exception.GetType().Name, $_.Exception.Message)
}

Complete-AgyHook
