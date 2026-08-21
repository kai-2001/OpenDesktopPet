$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bridgePath = Join-Path $projectRoot 'tools\codex_stop_notify.ps1'
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

function Save-Runtime([int]$port) {
    [pscustomobject]@{
        schema_version = 1
        instance_id = 'codex-router-test'
        pid = $PID
        port = $port
        enabled_targets = [pscustomobject]$script:enabledTargets
        executable_paths = [pscustomobject]@{}
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
        Join-Path $integrationHome 'open_desktop_pet_runtime.json'
    ) -Encoding UTF8
}

function Receive-Notification([string]$eventJson, [bool]$shouldReceive) {
    $udp = [System.Net.Sockets.UdpClient]::new(0)
    try {
        $port = $udp.Client.LocalEndPoint.Port
		Save-Runtime $port
		$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$startInfo.FileName = (Get-Command powershell.exe).Source
		$startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bridgePath + '"'
		$startInfo.UseShellExecute = $false
		$startInfo.CreateNoWindow = $true
		$startInfo.RedirectStandardInput = $true
		$startInfo.RedirectStandardOutput = $true
		$startInfo.RedirectStandardError = $true
		$startInfo.EnvironmentVariables['USERPROFILE'] = $env:USERPROFILE
		$startInfo.EnvironmentVariables['CODEX_HOME'] = $env:CODEX_HOME
		$startInfo.EnvironmentVariables['TERM_PROGRAM'] = $env:TERM_PROGRAM
		$startInfo.EnvironmentVariables['VSCODE_PID'] = $env:VSCODE_PID
		$startInfo.EnvironmentVariables['OPEN_DESKTOP_PET_SKIP_PROCESS_TREE'] = $env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE
		$process = [System.Diagnostics.Process]::Start($startInfo)
		$inputBytes = [System.Text.Encoding]::UTF8.GetBytes($eventJson)
		$process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
		$process.StandardInput.BaseStream.Close()
		if (-not $process.WaitForExit(10000)) {
			$process.Kill()
			throw 'The Codex Stop-hook bridge timed out.'
		}
		Assert-Router ($process.ExitCode -eq 0) 'The Codex Stop-hook bridge failed.'
		Assert-Router ([string]::IsNullOrWhiteSpace($process.StandardOutput.ReadToEnd())) `
			'The Stop hook must not write model-visible output.'
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
	$script:enabledTargets = @{
		codex_vscode = $true
		codex_app = $false
		codex_terminal = $false
	}
    $env:USERPROFILE = $testRoot
    $env:CODEX_HOME = $codexHome
    $env:OPEN_DESKTOP_PET_SKIP_PROCESS_TREE = '1'
    $env:TERM_PROGRAM = 'vscode'
    $env:VSCODE_PID = '1234'

	$unicodeMessage = ([char]0x5b8c).ToString() + ([char]0x6210).ToString() +
		([char]0xff1a).ToString() + ([char]0x4e2d).ToString() +
		([char]0x6587).ToString() + ([char]0x6e2c).ToString() +
		([char]0x8a66).ToString() + ([char]0x300c).ToString() +
		([char]0x684c).ToString() + ([char]0x5bf5).ToString() +
		([char]0x300d).ToString()
	$vscodeEvent = '{"hook_event_name":"Stop","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","session_id":"vscode","turn_id":"1","last_assistant_message":"' + $unicodeMessage + '"}'
	$payload = Receive-Notification $vscodeEvent $true
    Assert-Router ($payload.source -eq 'codex_vscode') 'VS Code Codex source was not classified.'
    Assert-Router ($payload.target_app -eq 'vscode') 'VS Code Codex target was not classified.'
    Assert-Router ($payload.agent -eq 'codex') 'Codex agent was not normalized.'
    Assert-Router ($payload.target_executable -eq 'Code.exe') 'VS Code executable target was not normalized.'
	Assert-Router ($payload.session_id -eq 'vscode') 'Stop-hook session id was not preserved.'
	Assert-Router ($payload.thread_id -eq 'vscode') 'Stop-hook session id must map to thread id.'

	$unsupportedEvent = '{"hook_event_name":"PostToolUse","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","session_id":"vscode","turn_id":"2"}'
	Receive-Notification $unsupportedEvent $false | Out-Null

    $env:TERM_PROGRAM = ''
    $env:VSCODE_PID = ''
	$appEvent = '{"hook_event_name":"Stop","cwd":"C:\\Program Files\\WindowsApps\\OpenAI.Codex_26.803.5235.0_x64__2p2nqsd0c76g0\\app","session_id":"app","turn_id":"1"}'
    Receive-Notification $appEvent $false | Out-Null
	$script:enabledTargets.codex_app = $true
    $payload = Receive-Notification $appEvent $true
    Assert-Router ($payload.source -eq 'codex_app') 'Codex App source was not classified.'
    Assert-Router ($payload.target_app -eq 'codex_app') 'Codex App target was not classified.'

	$terminalEvent = '{"hook_event_name":"Stop","cwd":"C:\\Apache24\\htdocs\\OpenDesktopPet","session_id":"terminal","turn_id":"1"}'
    Receive-Notification $terminalEvent $false | Out-Null
	$script:enabledTargets.codex_terminal = $true
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
