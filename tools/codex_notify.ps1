$ErrorActionPreference = 'SilentlyContinue'

$notifyHost = '127.0.0.1'
$notifyPort = 38571
$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $env:USERPROFILE '.codex'
} else {
    $env:CODEX_HOME
}
$portFile = Join-Path $codexHome 'open_desktop_pet_notify_port.txt'
$enabledFile = Join-Path $codexHome 'open_desktop_pet_notify_enabled.txt'
if (-not (Test-Path -LiteralPath $enabledFile)) {
    exit 0
}
try {
    $senderEnabled = (Get-Content -LiteralPath $enabledFile -Raw).Trim() -eq '1'
} catch {
    $senderEnabled = $false
}
if (-not $senderEnabled) {
    exit 0
}
if (Test-Path -LiteralPath $portFile) {
    try {
        $configuredPort = [int](Get-Content -LiteralPath $portFile -Raw).Trim()
        if ($configuredPort -ge 1024 -and $configuredPort -le 65535) {
            $notifyPort = $configuredPort
        }
    }
    catch {
        # Keep the default port when the optional setting is invalid.
    }
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-codex-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    }
    catch {
        # Diagnostics must never affect Codex.
    }
}

try {
    Write-NotifyLog ("invoked args={0}" -f $args.Count)
    if ($args.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$args[0])) {
        Write-NotifyLog 'ignored reason=missing-argument'
        exit 0
    }

    $event = ConvertFrom-Json -InputObject ([string]$args[0])
    Write-NotifyLog ("event type={0} cwd={1}" -f [string]$event.type, [string]$event.cwd)
    if ($null -eq $event -or $event.type -ne 'agent-turn-complete') {
        Write-NotifyLog 'ignored reason=unsupported-event'
        exit 0
    }

    # Only forward a small, fixed status payload. Never forward Codex's answer,
    # prompt, source code, or any other transcript content to the pet process.
    $payload = [ordered]@{
        type = 'agent-turn-complete'
        source = 'codex'
        thread_id = [string]$event.'thread-id'
        turn_id = [string]$event.'turn-id'
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog 'sent status=agent-turn-complete'
}
catch {
    Write-NotifyLog ("failed error-type={0}" -f $_.Exception.GetType().Name)
    # A pet notification must never make a Codex turn fail.
    exit 0
}

exit 0
