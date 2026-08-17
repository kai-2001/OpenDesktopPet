param(
	[ValidateSet('Availability', 'Status', 'Launch', 'Review')]
	[string]$Action = 'Status',
	[string]$WorkingDirectory = ''
)

$ErrorActionPreference = 'Stop'
$stopBridgeFileName = 'codex_stop_notify.ps1'

function Resolve-CodexExecutable {
	$candidates = [System.Collections.Generic.List[string]]::new()
	if (-not [string]::IsNullOrWhiteSpace($env:OPEN_DESKTOP_PET_CODEX_EXECUTABLE)) {
		$candidates.Add($env:OPEN_DESKTOP_PET_CODEX_EXECUTABLE)
	}
	if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
		$desktopBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
		if (Test-Path -LiteralPath $desktopBin) {
			Get-ChildItem -LiteralPath $desktopBin -Filter 'codex.exe' -File -Recurse `
				-ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending |
				ForEach-Object { $candidates.Add($_.FullName) }
		}
	}
	if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
		$extensionRoots = @(
			(Join-Path $env:USERPROFILE '.vscode\extensions'),
			(Join-Path $env:USERPROFILE '.vscode-insiders\extensions'),
			(Join-Path $env:USERPROFILE '.vscode-oss\extensions')
		)
		foreach ($extensionRoot in $extensionRoots) {
			if (-not (Test-Path -LiteralPath $extensionRoot -PathType Container)) {
				continue
			}
			Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter 'openai.chatgpt-*' `
				-ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending |
				ForEach-Object {
					Get-ChildItem -LiteralPath $_.FullName -Filter 'codex.exe' -File -Recurse `
						-ErrorAction SilentlyContinue |
						Sort-Object LastWriteTime -Descending |
						ForEach-Object { $candidates.Add($_.FullName) }
				}
		}
	}
	if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
		$npmVendor = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\vendor'
		if (Test-Path -LiteralPath $npmVendor) {
			Get-ChildItem -LiteralPath $npmVendor -Filter 'codex.exe' -File -Recurse `
				-ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending |
				ForEach-Object { $candidates.Add($_.FullName) }
		}
	}
	$pathCommand = Get-Command 'codex.exe' -ErrorAction SilentlyContinue
	if ($null -ne $pathCommand) {
		$candidates.Add([string]$pathCommand.Source)
	}
	foreach ($candidate in $candidates) {
		if (-not [string]::IsNullOrWhiteSpace($candidate) -and
			(Test-Path -LiteralPath $candidate -PathType Leaf)) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	return ''
}

function Write-StatusResult(
	[string]$status,
	[string]$message,
	[bool]$enabled = $false,
	[string]$trustStatus = ''
) {
	[ordered]@{
		status = $status
		message = $message
		enabled = $enabled
		trust_status = $trustStatus
	} | ConvertTo-Json -Compress
}

if ($Action -eq 'Launch') {
	$reviewArguments = @(
		'-NoProfile',
		'-ExecutionPolicy',
		'Bypass',
		'-File',
		('"{0}"' -f $PSCommandPath),
		'-Action',
		'Review'
	)
	$reviewProcess = Start-Process `
		-FilePath 'powershell.exe' `
		-ArgumentList $reviewArguments `
		-WindowStyle Normal `
		-PassThru
	if ($null -eq $reviewProcess) {
		exit 1
	}
	exit 0
}

function Read-RpcResponse(
	[System.Diagnostics.Process]$process,
	[int]$requestId,
	[int]$timeoutMilliseconds
) {
	$deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMilliseconds)
	while ([DateTime]::UtcNow -lt $deadline) {
		$remaining = [Math]::Max(
			1,
			[int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
		)
		$readTask = $process.StandardOutput.ReadLineAsync()
		if (-not $readTask.Wait($remaining)) {
			break
		}
		$line = [string]$readTask.Result
		if ([string]::IsNullOrWhiteSpace($line)) {
			if ($process.HasExited) {
				break
			}
			continue
		}
		try {
			$response = $line | ConvertFrom-Json
			if ([int]$response.id -eq $requestId) {
				return $response
			}
		} catch {
			# App-server notifications and diagnostics are unrelated to this request.
		}
	}
	throw "Codex app-server request $requestId timed out."
}

function Get-HookStatus([string]$codexExecutable, [string]$cwd) {
	$initialize = [ordered]@{
		jsonrpc = '2.0'
		id = 1
		method = 'initialize'
		params = [ordered]@{
			clientInfo = [ordered]@{
				name = 'open-desktop-pet'
				title = 'Open Desktop Pet'
				version = '1'
			}
		}
	} | ConvertTo-Json -Compress -Depth 6
	$request = [ordered]@{
		jsonrpc = '2.0'
		id = 2
		method = 'hooks/list'
		params = [ordered]@{ cwds = @($cwd) }
	} | ConvertTo-Json -Compress -Depth 6
	$inputPath = Join-Path ([System.IO.Path]::GetTempPath()) (
		'OpenDesktopPet-codex-hook-status-' + [guid]::NewGuid().ToString('N') + '.jsonl'
	)
	$inputText = $initialize + "`n" + `
		'{"jsonrpc":"2.0","method":"initialized","params":{}}' + "`n" + `
		$request + "`n"
	[System.IO.File]::WriteAllBytes(
		$inputPath,
		[System.Text.UTF8Encoding]::new($false).GetBytes($inputText)
	)
	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = 'cmd.exe'
	# Keep stdin open briefly after sending the requests. Codex disconnects a
	# stdio client at EOF before queued responses can be delivered.
	$startInfo.Arguments = '/d /s /c "(type "%ODP_RPC_INPUT%" & ping 127.0.0.1 -n 4 >nul) | "%ODP_CODEX_EXE%" app-server --listen stdio://"'
	$startInfo.EnvironmentVariables['ODP_RPC_INPUT'] = $inputPath
	$startInfo.EnvironmentVariables['ODP_CODEX_EXE'] = $codexExecutable
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$process = [System.Diagnostics.Process]::Start($startInfo)
	try {
		$null = Read-RpcResponse $process 1 10000
		$response = Read-RpcResponse $process 2 10000
		if ($null -ne $response.error) {
			throw [string]$response.error.message
		}
		$entries = @($response.result.data)
		if ($entries.Count -lt 1) {
			return @{ status = 'missing'; message = 'Codex returned no hook configuration.' }
		}
		$hooks = @($entries[0].hooks)
		$hook = $hooks | Where-Object {
			[string]$_.command -like "*$stopBridgeFileName*"
		} | Select-Object -First 1
		if ($null -eq $hook) {
			return @{ status = 'missing'; message = 'The Open Desktop Pet Stop hook was not found.' }
		}
		$trustStatus = ([string]$hook.trustStatus).ToLowerInvariant()
		if (-not [bool]$hook.enabled) {
			return @{
				status = 'disabled'
					message = 'Codex has disabled this hook.'
				enabled = $false
				trust_status = $trustStatus
			}
		}
		if ($trustStatus -eq 'trusted') {
			return @{
				status = 'trusted'
					message = 'The Codex Stop hook is trusted.'
				enabled = $true
				trust_status = $trustStatus
			}
		}
		return @{
			status = if ([string]::IsNullOrWhiteSpace($trustStatus)) { 'untrusted' } else { $trustStatus }
				message = 'Codex has not trusted the current hook definition.'
			enabled = $true
			trust_status = $trustStatus
		}
	} catch {
		$failure = $_.Exception.Message
		if (-not $process.HasExited) {
			$process.Kill()
			$process.WaitForExit()
		}
		$diagnostic = $process.StandardError.ReadToEnd().Trim()
		if (-not [string]::IsNullOrWhiteSpace($diagnostic)) {
			$failure += ' ' + $diagnostic
		}
		throw $failure
	} finally {
		if (-not $process.HasExited) {
			if (-not $process.WaitForExit(4000)) {
				$process.Kill()
			}
		}
		$process.Dispose()
		if (Test-Path -LiteralPath $inputPath -PathType Leaf) {
			[System.IO.File]::Delete($inputPath)
		}
	}
}

$codexExecutable = Resolve-CodexExecutable
if ([string]::IsNullOrWhiteSpace($codexExecutable)) {
	if ($Action -in @('Availability', 'Status')) {
		Write-StatusResult 'unavailable' 'A Codex CLI with hook review support was not found.'
		exit 0
	}
	throw 'A Codex CLI with hook review support was not found.'
}

if ($Action -eq 'Availability') {
	Write-StatusResult 'available' 'A Codex executable with hook review support was found.' $true
	exit 0
}

if ($Action -eq 'Review') {
	$createdNew = $false
	$reviewMutex = [System.Threading.Mutex]::new(
		$true,
		'Local\OpenDesktopPetCodexHookReview',
		[ref]$createdNew
	)
	if (-not $createdNew) {
		$reviewMutex.Dispose()
		exit 0
	}
	[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
	if ([string]::IsNullOrWhiteSpace($env:TERM) -or $env:TERM -eq 'dumb') {
		$env:TERM = 'xterm-256color'
	}
	try {
		$Host.UI.RawUI.WindowTitle = 'Codex Hook Review'
	} catch {
		# A custom title is optional; the review must still open.
	}
	Write-Host 'Open Desktop Pet installed a Codex Stop hook.'
	Write-Host 'Recommended: choose 1. Review hooks.' -ForegroundColor Cyan
	Write-Host 'Option 1 opens the hook list; it does not trust the hook yet.'
	Write-Host 'In the hook list, select Stop and press Enter.'
	Write-Host 'Set the Open Desktop Pet hook checkbox to [x]. [ ] is not trusted.'
	Write-Host 'Press Esc to return. If the review screen is still open, press Esc again.'
	Write-Host 'Option 2 trusts every pending hook; option 3 leaves notifications disabled.'
	Write-Host 'After trusting, return to Open Desktop Pet and check the notification status.'
	Write-Host ''
	$reviewExitCode = 1
	try {
		& $codexExecutable --no-alt-screen
		$reviewExitCode = $LASTEXITCODE
	} finally {
		$reviewMutex.ReleaseMutex()
		$reviewMutex.Dispose()
	}
	exit $reviewExitCode
}

try {
	$cwd = $WorkingDirectory.Trim()
	if ([string]::IsNullOrWhiteSpace($cwd) -or -not (Test-Path -LiteralPath $cwd)) {
		$cwd = (Get-Location).Path
	}
	$result = Get-HookStatus $codexExecutable $cwd
	Write-StatusResult `
		([string]$result.status) `
		([string]$result.message) `
		([bool]$result.enabled) `
		([string]$result.trust_status)
} catch {
	Write-StatusResult 'error' ('Codex hook status query failed: ' + $_.Exception.Message)
}
