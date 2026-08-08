$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\antigravity_cli_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Antigravity-CLI-Bridge-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$oldUserProfile = $env:USERPROFILE

function Assert-Bridge([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Receive-Notification([string]$eventJson, [bool]$shouldReceive) {
    $udp = New-Object System.Net.Sockets.UdpClient(0)
    $process = $null
    try {
        $port = $udp.Client.LocalEndPoint.Port
        Set-Content -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_notify_port.txt') `
            -Value $port -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_agy_enabled.txt') `
            -Value '1' -Encoding ASCII

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Get-Command powershell.exe).Source
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bridgePath + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['USERPROFILE'] = $testRoot

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($eventJson)
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
        $process.StandardInput.BaseStream.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.StandardError.ReadToEnd() | Out-Null
        $process.WaitForExit()
        Assert-Bridge ($stdout.Trim() -eq '{"decision":"allow"}') `
            'Antigravity bridge did not return a valid allow decision.'

        $udp.Client.ReceiveTimeout = 1500
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Bridge $shouldReceive 'Antigravity bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Bridge (-not $shouldReceive) 'Antigravity bridge dropped an expected notification.'
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

    $stopEvent = '{"executionNum":3,"terminationReason":"model_stop","error":"","fullyIdle":true,"conversationId":"conversation-stop","workspacePaths":["C:\\Apache24\\htdocs\\OpenDesktopPet"],"modelName":"gemini-test"}'
    $payload = Receive-Notification $stopEvent $true
    Assert-Bridge ($payload.source -eq 'antigravity_cli') 'Antigravity source was not classified.'
    Assert-Bridge ($payload.agent -eq 'agy') 'Antigravity agent was not normalized.'
    Assert-Bridge ($payload.target_app -eq 'terminal') 'Antigravity target was not classified as terminal.'
    Assert-Bridge ($payload.type -eq 'agent-turn-complete') 'Antigravity Stop event was not normalized.'
    Assert-Bridge ($payload.target_executable -eq 'WindowsTerminal.exe') `
        'Antigravity terminal executable was not normalized.'

    $errorEvent = '{"executionNum":4,"terminationReason":"error","error":"agent failed","fullyIdle":true,"conversationId":"conversation-error","workspacePaths":[]}'
    $payload = Receive-Notification $errorEvent $true
    Assert-Bridge ($payload.type -eq 'agent-error') 'Antigravity error was not normalized.'

    $backgroundEvent = '{"executionNum":5,"terminationReason":"model_stop","error":"","fullyIdle":false,"conversationId":"conversation-background","workspacePaths":[]}'
    $null = Receive-Notification $backgroundEvent $false

    Write-Output 'ANTIGRAVITY_CLI_NOTIFY_BRIDGE_TEST_OK'
}
finally {
    $env:USERPROFILE = $oldUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
