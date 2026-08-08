$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\codex_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Codex-Router-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$codexHome = Join-Path $testRoot '.codex'
$oldUserProfile = $env:USERPROFILE
$oldCodexHome = $env:CODEX_HOME
$oldTermProgram = $env:TERM_PROGRAM
$oldVscodePid = $env:VSCODE_PID
$oldSkipProcessTree = $env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE

function Assert-Router([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Set-Flag([string]$name, [bool]$enabled) {
	$value = if ($enabled) { '1' } else { '0' }
	Set-Content -LiteralPath (Join-Path $integrationHome $name) -Value $value -Encoding ASCII
}

function Receive-Notification([string]$eventJson, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    try {
        $port = $udp.Client.LocalEndPoint.Port
        Set-Content -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_notify_port.txt') `
            -Value $port -Encoding ASCII
		& $bridgePath $eventJson | Out-Null
        $udp.Client.ReceiveTimeout = 3000
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Router $shouldReceive 'The bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Router (-not $shouldReceive) 'The bridge dropped an expected notification.'
            return $null
        }
    } finally {
        $udp.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
    Set-Flag 'open_desktop_pet_vscode_codex_enabled.txt' $true
    Set-Flag 'open_desktop_pet_codex_app_enabled.txt' $false
    Set-Flag 'open_desktop_pet_terminal_codex_enabled.txt' $false
    $env:USERPROFILE = $testRoot
    $env:CODEX_HOME = $codexHome
    $env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE = '1'
    $env:TERM_PROGRAM = 'vscode'
    $env:VSCODE_PID = '1234'

    $vscodeEvent = '{"type":"agent-turn-complete","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","thread-id":"vscode","turn-id":"1"}'
    $payload = Receive-Notification $vscodeEvent $true
    Assert-Router ($payload.source -eq 'codex_vscode') 'VS Code Codex source was not classified.'
    Assert-Router ($payload.target_app -eq 'vscode') 'VS Code Codex target was not classified.'

    $env:TERM_PROGRAM = ''
    $env:VSCODE_PID = ''
    $appEvent = '{"type":"agent-turn-complete","cwd":"C:\\Program Files\\WindowsApps\\OpenAI.Codex_26.803.5235.0_x64__2p2nqsd0c76g0\\app","thread-id":"app","turn-id":"1"}'
    Receive-Notification $appEvent $false | Out-Null
    Set-Flag 'open_desktop_pet_codex_app_enabled.txt' $true
    $payload = Receive-Notification $appEvent $true
    Assert-Router ($payload.source -eq 'codex_app') 'Codex App source was not classified.'
    Assert-Router ($payload.target_app -eq 'codex_app') 'Codex App target was not classified.'

    $terminalEvent = '{"type":"agent-turn-complete","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","thread-id":"terminal","turn-id":"1"}'
    Receive-Notification $terminalEvent $false | Out-Null
    Set-Flag 'open_desktop_pet_terminal_codex_enabled.txt' $true
    $payload = Receive-Notification $terminalEvent $true
    Assert-Router ($payload.source -eq 'codex_cli') 'CLI source was not classified.'
    Assert-Router ($payload.target_app -eq 'terminal') 'CLI target was not classified.'

    Write-Output 'CODEX_NOTIFY_ROUTER_TEST_OK'
} finally {
    $env:USERPROFILE = $oldUserProfile
    $env:CODEX_HOME = $oldCodexHome
    $env:TERM_PROGRAM = $oldTermProgram
    $env:VSCODE_PID = $oldVscodePid
    $env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE = $oldSkipProcessTree
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
