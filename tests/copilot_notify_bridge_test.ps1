$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\vscode_agent_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Copilot-Bridge-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$oldUserProfile = $env:USERPROFILE

function Assert-Bridge([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Save-Runtime([int]$port, [bool]$enabled) {
    [pscustomobject]@{
        schema_version = 1
        instance_id = 'copilot-bridge-test'
        pid = $PID
        port = $port
        enabled_targets = [pscustomobject]@{ copilot = $enabled }
        executable_paths = [pscustomobject]@{}
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
        Join-Path $integrationHome 'open_desktop_pet_runtime.json'
    ) -Encoding UTF8
}

function Receive-Notification([string]$eventJson, [bool]$enabled, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    $process = $null
    try {
        Save-Runtime $udp.Client.LocalEndPoint.Port $enabled
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
        Assert-Bridge ($stdout.Trim() -eq '{"continue":true}') 'Copilot bridge did not return a continue response.'

        $udp.Client.ReceiveTimeout = 1500
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Bridge $shouldReceive 'Copilot bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Bridge (-not $shouldReceive) 'Copilot bridge dropped an expected notification.'
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
    $stopEvent = '{"hook_event_name":"Stop","session_id":"copilot-stop","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet"}'
    $payload = Receive-Notification $stopEvent $true $true
    Assert-Bridge ($payload.source -eq 'copilot_vscode') 'Copilot source was not classified.'
    Assert-Bridge ($payload.target_app -eq 'vscode') 'Copilot target was not classified.'
    Assert-Bridge ($payload.agent -eq 'copilot') 'Copilot agent was not classified.'
    Receive-Notification $stopEvent $false $false | Out-Null
    Write-Output 'COPILOT_NOTIFY_BRIDGE_TEST_OK'
} finally {
    $env:USERPROFILE = $oldUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
