$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\gemini_cli_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Gemini-CLI-Bridge-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$oldUserProfile = $env:USERPROFILE

function Assert-Bridge([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Receive-Notification([string]$eventJson, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    $process = $null
    try {
        $port = $udp.Client.LocalEndPoint.Port
        Set-Content -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_notify_port.txt') `
            -Value $port -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_gemini_enabled.txt') `
            -Value '1' -Encoding ASCII

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command powershell.exe).Source
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bridgePath + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['USERPROFILE'] = $testRoot

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($eventJson)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.BaseStream.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.StandardError.ReadToEnd() | Out-Null
        $process.WaitForExit()
        Assert-Bridge ($stdout.Trim() -eq '{}') 'Gemini bridge did not return a valid empty JSON object.'

        $udp.Client.ReceiveTimeout = 1500
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Bridge $shouldReceive 'Gemini bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Bridge (-not $shouldReceive) 'Gemini bridge dropped an expected notification.'
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

    $unicodeResponse = ([char]0x5b8c).ToString() + ([char]0x6210).ToString() +
        ([char]0x901a).ToString() + ([char]0x77e5).ToString()
    $afterAgentEvent = '{"hook_event_name":"AfterAgent","session_id":"session-after","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","prompt_response":"' +
        $unicodeResponse + '"}'
    $payload = Receive-Notification $afterAgentEvent $true
    Assert-Bridge ($payload.source -eq 'gemini_cli') 'Gemini source was not classified.'
    Assert-Bridge ($payload.agent -eq 'gemini') 'Gemini agent was not normalized.'
    Assert-Bridge ($payload.target_app -eq 'terminal') 'Gemini target was not classified as terminal.'
    Assert-Bridge ($payload.type -eq 'agent-turn-complete') 'Gemini AfterAgent event was not normalized.'
    Assert-Bridge ($payload.target_executable -eq 'WindowsTerminal.exe') 'Gemini terminal executable was not normalized.'

    $permissionEvent = '{"hook_event_name":"Notification","notification_type":"ToolPermission","session_id":"session-permission","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","message":"Allow tool?"}'
    $payload = Receive-Notification $permissionEvent $true
    Assert-Bridge ($payload.type -eq 'approval-requested') 'Gemini ToolPermission was not normalized.'

    $otherNotification = '{"hook_event_name":"Notification","notification_type":"SystemInfo","session_id":"session-ignored","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","message":"info"}'
    $null = Receive-Notification $otherNotification $false

    Write-Output 'GEMINI_CLI_NOTIFY_BRIDGE_TEST_OK'
}
finally {
    $env:USERPROFILE = $oldUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
