$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\opencode_notify.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-OpenCode-Bridge-Test-' + [guid]::NewGuid().ToString('N')
)
$integrationHome = Join-Path $testRoot '.open-desktop-pet'
$oldUserProfile = $env:USERPROFILE
$oldTermProgram = $env:TERM_PROGRAM
$oldVscodePid = $env:VSCODE_PID
$oldForcedTarget = $env:OPEN_DESKTOP_PET_OPENCODE_TARGET

function Assert-Bridge([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Save-Runtime([int]$port, [bool]$enabled) {
    [pscustomobject]@{
        schema_version = 1
        instance_id = 'opencode-bridge-test'
        pid = $PID
        port = $port
        enabled_targets = [pscustomobject]@{
            opencode_terminal = $enabled
            opencode_vscode = $enabled
            opencode_app = $enabled
        }
        executable_paths = [pscustomobject]@{ opencode_app = $script:opencodeAppPath }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
        Join-Path $integrationHome 'open_desktop_pet_runtime.json'
    ) -Encoding UTF8
}

function Receive-Notification([string]$eventJson, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    try {
        $port = $udp.Client.LocalEndPoint.Port
		Save-Runtime $port $script:opencodeEnabled
        & $bridgePath $eventJson | Out-Null
        $udp.Client.ReceiveTimeout = 3000
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        try {
            $bytes = $udp.Receive([ref]$remote)
            $payload = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            Assert-Bridge $shouldReceive 'The OpenCode bridge sent an unexpected notification.'
            return $payload
        } catch [System.Net.Sockets.SocketException] {
            Assert-Bridge (-not $shouldReceive) 'The OpenCode bridge dropped an expected notification.'
            return $null
        }
    } finally {
        $udp.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
    $env:USERPROFILE = $testRoot
    $env:TERM_PROGRAM = ''
    $env:VSCODE_PID = ''
    $env:OPEN_DESKTOP_PET_OPENCODE_TARGET = 'terminal'
    # The desktop target may be enabled in the UI before its executable path
    # is configured. The bridge must still classify VS Code/terminal events.
	$script:opencodeAppPath = ''
	$script:opencodeEnabled = $false
    $event = '{"type":"agent-turn-complete","session_id":"session-1","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet"}'
    Receive-Notification $event $false | Out-Null
	$script:opencodeEnabled = $true
    $payload = Receive-Notification $event $true
    Assert-Bridge ($payload.source -eq 'opencode') 'OpenCode source was not classified.'
    Assert-Bridge ($payload.agent -eq 'opencode') 'OpenCode agent was not classified.'
    Assert-Bridge ($payload.target_app -eq 'terminal') 'OpenCode target was not classified as terminal.'
    Assert-Bridge ($payload.schema_version -eq 1) 'OpenCode payload schema was not normalized.'
    Assert-Bridge ($payload.target_executable -eq 'WindowsTerminal.exe') `
        'OpenCode terminal executable target was not normalized.'

    # A stale generic CLI path must not turn a terminal event into the
    # OpenCode Desktop target.
	$script:opencodeAppPath = Join-Path $testRoot 'OpenCode\opencode.exe'
    $payload = Receive-Notification $event $true
    Assert-Bridge ($payload.target_app -eq 'terminal') `
        'A generic OpenCode CLI path must not steal terminal routing.'

    $env:TERM_PROGRAM = 'vscode'
    $env:VSCODE_PID = '1234'
    $env:OPEN_DESKTOP_PET_OPENCODE_TARGET = ''
    $payload = Receive-Notification $event $true
    Assert-Bridge ($payload.target_app -eq 'vscode') 'VS Code OpenCode target was not classified.'
    Assert-Bridge ($payload.target_platform -eq 'vscode') `
        'VS Code OpenCode platform was not normalized.'
    Write-Output 'OPENCODE_NOTIFY_BRIDGE_TEST_OK'
} finally {
    $env:USERPROFILE = $oldUserProfile
    $env:TERM_PROGRAM = $oldTermProgram
    $env:VSCODE_PID = $oldVscodePid
    $env:OPEN_DESKTOP_PET_OPENCODE_TARGET = $oldForcedTarget
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
