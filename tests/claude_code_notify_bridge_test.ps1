$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\claude_code_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Claude-Code-Bridge-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$oldUserProfile = $env:USERPROFILE

function Assert-Bridge([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Save-Runtime([int]$port, [string]$target) {
    [pscustomobject]@{
        schema_version = 1
        instance_id = 'claude-bridge-test'
        pid = $PID
        port = $port
        enabled_targets = [pscustomobject]@{
            claude_vscode = $target -eq 'vscode'
            claude_app = $target -eq 'claude_app'
            claude_terminal = $target -eq 'terminal'
        }
        executable_paths = [pscustomobject]@{ claude_app = '' }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
        Join-Path $integrationHome 'open_desktop_pet_runtime.json'
    ) -Encoding UTF8
}

function Receive-Notification([string]$eventJson, [string]$target, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    $process = $null
    try {
        $port = $udp.Client.LocalEndPoint.Port
		Save-Runtime $port $target

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command powershell.exe).Source
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bridgePath + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['USERPROFILE'] = $testRoot
        $startInfo.EnvironmentVariables['OPEN_DESKTOP_PET_CLAUDE_TARGET'] = $target

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($eventJson)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.BaseStream.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.StandardError.ReadToEnd() | Out-Null
        $process.WaitForExit()
        Assert-Bridge ([string]::IsNullOrWhiteSpace($stdout)) 'Claude bridge wrote to stdout.'

        $udp.Client.ReceiveTimeout = 1500
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Bridge $shouldReceive 'Claude bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Bridge (-not $shouldReceive) 'Claude bridge dropped an expected notification.'
            return $null
        }
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        $udp.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
    $env:USERPROFILE = $testRoot

    $stopEvent = '{"hook_event_name":"Stop","session_id":"session-stop","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","last_assistant_message":"done"}'
    $payload = Receive-Notification $stopEvent 'vscode' $true
    Assert-Bridge ($payload.source -eq 'claude_code') 'Claude source was not classified.'
    Assert-Bridge ($payload.agent -eq 'claude') 'Claude agent was not normalized.'
    Assert-Bridge ($payload.target_app -eq 'vscode') 'Claude VS Code target was not classified.'
    Assert-Bridge ($payload.type -eq 'agent-turn-complete') 'Claude Stop event was not normalized.'
    Assert-Bridge ($payload.target_executable -eq 'Code.exe') 'Claude VS Code executable was not normalized.'

    $unicodePrompt = ([char]0x9700).ToString() + ([char]0x8981).ToString() +
        ([char]0x4f60).ToString() + ([char]0x78ba).ToString() + ([char]0x8a8d).ToString() +
        ([char]0xff1a).ToString() + ([char]0x7e7c).ToString() + ([char]0x7e8c).ToString() +
        ([char]0x55ce).ToString() + ([char]0xff1f).ToString()
    $waitingEvent = '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"session-wait","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","message":"' +
        $unicodePrompt + '"}'
    $payload = Receive-Notification $waitingEvent 'terminal' $true
    Assert-Bridge ($payload.type -eq 'approval-requested') 'Claude permission notification was not normalized.'
    Assert-Bridge ($payload.target_app -eq 'terminal') 'Claude terminal target was not classified.'

    $errorEvent = '{"hook_event_name":"StopFailure","session_id":"session-error","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","error":"rate_limit"}'
    $payload = Receive-Notification $errorEvent 'claude_app' $true
    Assert-Bridge ($payload.type -eq 'agent-error') 'Claude StopFailure was not normalized.'
    Assert-Bridge ($payload.target_app -eq 'claude_app') 'Claude Desktop target was not classified.'
    Assert-Bridge ($payload.target_executable -eq 'Claude.exe') 'Claude Desktop executable was not normalized.'

    Write-Output 'CLAUDE_CODE_NOTIFY_BRIDGE_TEST_OK'
}
finally {
    $env:USERPROFILE = $oldUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
