$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_copilot_integration.ps1'
$testRoot = Join-Path $env:TEMP (
	'OpenDesktopPet-Copilot-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$originalUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
	if (-not $condition) {
		throw $message
	}
}

try {
	$env:USERPROFILE = $testRoot
	$hooksHome = Join-Path $testRoot '.copilot\hooks'
	New-Item -ItemType Directory -Force -Path $hooksHome | Out-Null
	$hookConfigPath = Join-Path $hooksHome 'open-desktop-pet.json'
	$existingConfig = @'
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "windows": "powershell.exe -File other-agent.ps1"
      }
    ]
  }
}
'@
	Set-Content -LiteralPath $hookConfigPath -Value $existingConfig -Encoding UTF8

	& $installerPath | Write-Output
	$installedConfig = Get-Content -LiteralPath $hookConfigPath -Raw | ConvertFrom-Json
	$stopHooks = @($installedConfig.hooks.Stop)
	Assert-Installer ($stopHooks.Count -eq 2) `
		'The installer must preserve an existing user Stop hook.'
	Assert-Installer (@($stopHooks | Where-Object {
			[string]$_.windows -like '*vscode_copilot_notify.ps1*'
		}).Count -eq 1) `
		'The installer must add exactly one OpenDesktopPet hook.'
	Assert-Installer (Test-Path -LiteralPath (Join-Path $testRoot '.open-desktop-pet\open_desktop_pet_copilot_installed.txt')) `
		'The installer did not write the Copilot install marker.'

	& $installerPath | Write-Output
	$reinstalledConfig = Get-Content -LiteralPath $hookConfigPath -Raw | ConvertFrom-Json
	Assert-Installer (@($reinstalledConfig.hooks.Stop).Count -eq 2) `
		'Reinstalling the Copilot hook must be idempotent.'

	& $installerPath -Uninstall | Write-Output
	$uninstalledConfig = Get-Content -LiteralPath $hookConfigPath -Raw | ConvertFrom-Json
	Assert-Installer (@($uninstalledConfig.hooks.Stop).Count -eq 1) `
		'Uninstall must remove only the OpenDesktopPet hook.'

	Write-Output 'COPILOT_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
	$env:USERPROFILE = $originalUserProfile
	if (Test-Path -LiteralPath $testRoot) {
		Remove-Item -LiteralPath $testRoot -Recurse -Force
	}
}
