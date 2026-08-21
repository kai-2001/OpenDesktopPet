$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_codex_integration.ps1'
$testRoot = Join-Path $env:TEMP (
	'OpenDesktopPet-Codex-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$testProfile = Join-Path $testRoot 'profile'
$testCodexHome = Join-Path $testRoot 'codex-home'
$integrationHome = Join-Path $testProfile '.open-desktop-pet'
$configPath = Join-Path $testCodexHome 'config.toml'
$hooksPath = Join-Path $testCodexHome 'hooks.json'
$originalUserProfile = $env:USERPROFILE
$originalCodexHome = $env:CODEX_HOME

function Assert-Installer([bool]$condition, [string]$message) {
	if (-not $condition) {
		throw $message
	}
}

function Test-StartsWithJsonObject([string]$path) {
	$bytes = [System.IO.File]::ReadAllBytes($path)
	return $bytes.Length -gt 0 -and $bytes[0] -eq 0x7B
}

function Get-DesktopPetHandlers($config) {
	$handlers = @()
	foreach ($group in @($config.hooks.Stop)) {
		$handlers += @($group.hooks | Where-Object {
			[string]$_.command -like '*codex_stop_notify.ps1*' -or
			[string]$_.commandWindows -like '*codex_stop_notify.ps1*'
		})
	}
	return $handlers
}

try {
	New-Item -ItemType Directory -Force -Path $testCodexHome | Out-Null
	New-Item -ItemType Directory -Force -Path $testProfile | Out-Null
	$env:USERPROFILE = $testProfile
	$env:CODEX_HOME = $testCodexHome

	$existingHooks = @'
{
  "description": "keep me",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -File C:\\Tools\\other-stop.ps1"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -File C:\\Tools\\session-start.ps1"
          }
        ]
      }
    ]
  }
}
'@
	Set-Content -LiteralPath $hooksPath -Value $existingHooks -Encoding UTF8
	Set-Content -LiteralPath $configPath -Value 'model = "gpt-5.6-luna"' -Encoding UTF8

	& $installerPath | Write-Output
	$installedHooksText = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8
	$installedHooks = $installedHooksText | ConvertFrom-Json
	Assert-Installer (Test-StartsWithJsonObject $hooksPath) `
		'The generated hooks.json must be UTF-8 without a BOM.'
	$desktopHandlers = @(Get-DesktopPetHandlers $installedHooks)
	Assert-Installer ($installedHooks.description -eq 'keep me') `
		'The installer must preserve top-level hook metadata.'
	Assert-Installer (@($installedHooks.hooks.SessionStart).Count -eq 1) `
		'The installer must preserve hooks for other events.'
	Assert-Installer (@($installedHooks.hooks.Stop).Count -eq 2) `
		'The installer must preserve unrelated Stop groups.'
	Assert-Installer ($desktopHandlers.Count -eq 1) `
		'The installer must add exactly one OpenDesktopPet Stop handler.'
	Assert-Installer ($null -eq $desktopHandlers[0].PSObject.Properties['async']) `
		'The notification Stop hook must not declare an unsupported async mode.'
	Assert-Installer ($desktopHandlers[0].timeout -eq 5) `
		'The notification Stop hook must use the bounded timeout.'
	Assert-Installer (
		Test-Path -LiteralPath (Join-Path $integrationHome 'codex_stop_notify.ps1')
	) 'The installer did not copy the Stop-hook bridge.'

	& $installerPath | Out-Null
	$reinstalledHooksText = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8
	Assert-Installer (Test-StartsWithJsonObject $hooksPath) `
		'Reinstalling must keep hooks.json in UTF-8 without a BOM.'
	Assert-Installer ($reinstalledHooksText -eq $installedHooksText) `
		'Reinstalling the same Stop hook must be idempotent.'

	$legacyBridge = Join-Path $testCodexHome 'open_desktop_pet_notify.ps1'
	$legacyPrevious = Join-Path $testCodexHome 'open_desktop_pet_previous_notify.json'
	Set-Content -LiteralPath $legacyBridge -Value '# legacy' -Encoding UTF8
	[pscustomobject]@{
		command = @('powershell.exe', '-NoProfile', '-File', 'C:\Tools\other-notify.ps1')
	} | ConvertTo-Json -Compress | Set-Content -LiteralPath $legacyPrevious -Encoding UTF8
	$legacyConfig = @"
model = "gpt-5.6-luna"

notify = [
  "powershell.exe",
  "-NoProfile",
  "-File",
  "$($legacyBridge.Replace('\', '\\'))"
]

[windows]
sandbox = "elevated"
"@
	Set-Content -LiteralPath $configPath -Value $legacyConfig -Encoding UTF8
	& $installerPath | Out-Null
	$migratedDirectConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
	Assert-Installer ($migratedDirectConfig -match 'other-notify\.ps1') `
		'Legacy direct notify migration must restore the previous command.'
	Assert-Installer (-not ($migratedDirectConfig -match 'open_desktop_pet_notify\.ps1')) `
		'Legacy direct notify migration must remove the obsolete bridge.'
	Assert-Installer (-not (Test-Path -LiteralPath $legacyBridge)) `
		'Legacy bridge file must be removed after migration.'
	Assert-Installer (-not (Test-Path -LiteralPath $legacyPrevious)) `
		'Legacy previous-notify sidecar must be removed after migration.'
	Assert-Installer (@(
		Get-ChildItem -LiteralPath $testCodexHome `
			-Filter 'config.toml.open-desktop-pet-stop-migration-*' -File
	).Count -ge 1) 'Legacy notify migration must back up config.toml.'

	Set-Content -LiteralPath $legacyBridge -Value '# legacy' -Encoding UTF8
	$legacyJson = ConvertTo-Json -InputObject @(
		'powershell.exe', '-NoProfile', '-File', $legacyBridge
	) -Compress
	$escapedLegacyJson = $legacyJson.Replace('\', '\\').Replace('"', '\"')
	$wrappedConfig = @"
model = "gpt-5.6-luna"

notify = [ "C:\\Program Files\\OpenAI\\codex-computer-use.exe", "turn-ended", "--previous-notify", "$escapedLegacyJson" ]

[windows]
sandbox = "elevated"
"@
	Set-Content -LiteralPath $configPath -Value $wrappedConfig -Encoding UTF8
	& $installerPath | Out-Null
	$migratedWrappedConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
	Assert-Installer ($migratedWrappedConfig -match 'codex-computer-use\.exe') `
		'Computer Use notify wrapper must be preserved.'
	Assert-Installer (-not ($migratedWrappedConfig -match '--previous-notify')) `
		'Obsolete nested desktop-pet notify must be removed from Computer Use.'
	Assert-Installer (-not ($migratedWrappedConfig -match 'open_desktop_pet_notify\.ps1')) `
		'Computer Use migration must not retain the obsolete bridge path.'

	& $installerPath -Uninstall | Out-Null
	$uninstalledHooks = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 |
		ConvertFrom-Json
	Assert-Installer (@(Get-DesktopPetHandlers $uninstalledHooks).Count -eq 0) `
		'Uninstall must remove only the OpenDesktopPet Stop handler.'
	Assert-Installer (@($uninstalledHooks.hooks.Stop).Count -eq 1) `
		'Uninstall must preserve unrelated Stop groups.'
	Assert-Installer (@($uninstalledHooks.hooks.SessionStart).Count -eq 1) `
		'Uninstall must preserve other hook events.'
	Assert-Installer (-not (
		Test-Path -LiteralPath (Join-Path $integrationHome 'codex_stop_notify.ps1')
	)) 'Uninstall must remove the installed Stop-hook bridge.'

	Write-Output 'CODEX_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
	$env:USERPROFILE = $originalUserProfile
	$env:CODEX_HOME = $originalCodexHome
	if (Test-Path -LiteralPath $testRoot) {
		Remove-Item -LiteralPath $testRoot -Recurse -Force
	}
}
