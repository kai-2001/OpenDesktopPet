$ErrorActionPreference = 'SilentlyContinue'

# OpenDesktopPet runtime schema v1
# VS Code Agent Hook bridge for OpenDesktopPet.
# The hook must never block or change the agent's behavior.
$notifyHost = '127.0.0.1'
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$runtimeHelperPath = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
if (-not (Test-Path -LiteralPath $runtimeHelperPath)) {
    $runtimeHelperPath = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
}
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-vscode-hook.log'

function Write-HookLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect VS Code or the agent.
    }
}

function Complete-Hook {
    # VS Code expects valid JSON on stdout. Do not write diagnostics there.
    [Console]::Out.WriteLine('{"continue":true}')
    exit 0
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
		Write-HookLog 'ignored reason=runtime-helper-missing'
		Complete-Hook
	}
	. $runtimeHelperPath
    $rawInput = Read-StandardInputUtf8
    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        Write-HookLog 'ignored reason=missing-input'
        Complete-Hook
    }
	$rawInput = $rawInput.TrimStart([char]0xFEFF)

    $event = ConvertFrom-Json -InputObject $rawInput
    $eventName = [string]$event.hook_event_name
    Write-HookLog ("invoked event={0} session={1}" -f $eventName, [string]$event.session_id)

    if ($eventName -ne 'Stop') {
        Write-HookLog 'ignored reason=unsupported-event'
        Complete-Hook
    }

    # A repeated Stop hook means the agent is continuing because of a previous
    # Stop hook. We never block the agent and avoid a duplicate notification.
    if ([bool]$event.stop_hook_active) {
        Write-HookLog 'ignored reason=stop-hook-already-active'
        Complete-Hook
    }

    $runtime = Get-OpenDesktopPetRuntime -IntegrationHome $integrationHome
    if ($null -eq $runtime) {
        Write-HookLog 'ignored reason=runtime-unavailable'
        Complete-Hook
    }
    if (-not (Test-OpenDesktopPetRuntimeEnabled -Runtime $runtime -Target 'copilot')) {
        Write-HookLog 'ignored reason=desktop-pet-disabled'
        Complete-Hook
    }
	$notifyPort = Get-OpenDesktopPetRuntimePort -Runtime $runtime

    $sessionId = [string]$event.session_id
    $payload = [ordered]@{
        schema_version = 1
        type = 'agent-turn-complete'
        source = 'copilot_vscode'
        agent = 'copilot'
        target_app = 'vscode'
        target_platform = 'vscode'
        target_executable = 'Code.exe'
        event_id = "copilot:vscode:{0}" -f $sessionId
        thread_id = ''
        turn_id = ''
        session_id = $sessionId
        cwd = [string]$event.cwd
        hook_event = 'Stop'
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-HookLog ("sent type=agent-turn-complete port={0}" -f $notifyPort)
} catch {
    Write-HookLog ("failed error-type={0} message={1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
}

Complete-Hook
