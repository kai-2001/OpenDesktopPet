param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$hooksHome = Join-Path $env:USERPROFILE '.copilot\hooks'
$hookConfigPath = Join-Path $hooksHome 'open-desktop-pet.json'
$installedScriptPath = Join-Path $integrationHome 'vscode_copilot_notify.ps1'
$sourceScriptPath = Join-Path $PSScriptRoot 'vscode_agent_notify.ps1'
$installedRuntimeHelper = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
$sourceRuntimeHelper = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_copilot_installed.txt'

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null

function Save-HookConfig($config) {
	$tempPath = "$hookConfigPath.open-desktop-pet.tmp"
	$config | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding UTF8
	Move-Item -LiteralPath $tempPath -Destination $hookConfigPath -Force
}

function Get-HookConfig {
	if (-not (Test-Path -LiteralPath $hookConfigPath)) {
		return [pscustomobject]@{ hooks = [pscustomobject]@{} }
	}
	try {
		$config = Get-Content -LiteralPath $hookConfigPath -Raw -Encoding UTF8 |
			ConvertFrom-Json
		if ($null -eq $config) {
			throw 'Hook configuration is empty.'
		}
		if ($null -eq $config.PSObject.Properties['hooks']) {
			$config | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
		}
		if ($null -eq $config.hooks) {
			$config.hooks = [pscustomobject]@{}
		}
		return $config
	} catch {
		$backupPath = "$hookConfigPath.invalid-$(Get-Date -Format 'yyyyMMddHHmmss').bak"
		Copy-Item -LiteralPath $hookConfigPath -Destination $backupPath -Force
		Write-Warning "Existing invalid Copilot hook config was backed up to $backupPath"
		return [pscustomobject]@{ hooks = [pscustomobject]@{} }
	}
}

function Remove-OpenDesktopPetStopHook($config) {
	if ($null -eq $config.hooks -or $null -eq $config.hooks.PSObject.Properties['Stop']) {
		return
	}
	$remaining = @($config.hooks.Stop | Where-Object {
		$command = [string]$_.windows
		$command -notlike '*vscode_copilot_notify.ps1*'
	})
	if ($remaining.Count -eq 0) {
		$config.hooks.PSObject.Properties.Remove('Stop')
	} else {
		$config.hooks | Add-Member -MemberType NoteProperty -Name Stop -Value $remaining -Force
	}
}

if ($Uninstall) {
	if (Test-Path -LiteralPath $hookConfigPath) {
		try {
			$hookConfig = Get-Content -LiteralPath $hookConfigPath -Raw -Encoding UTF8 |
				ConvertFrom-Json
			Remove-OpenDesktopPetStopHook $hookConfig
			Save-HookConfig $hookConfig
		} catch {
			Write-Warning "Could not update existing Copilot hook config; leaving it unchanged."
		}
	}
    if (Test-Path -LiteralPath $installedScriptPath) {
        Remove-Item -LiteralPath $installedScriptPath -Force
    }
    if (Test-Path -LiteralPath $installMarker) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    Write-Output "Removed Copilot user hook: $hookConfigPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceScriptPath) -or
    -not (Test-Path -LiteralPath $sourceRuntimeHelper)) {
    throw "VS Code notification bridge not found: $sourceScriptPath"
}

New-Item -ItemType Directory -Force -Path $hooksHome | Out-Null
Copy-Item -LiteralPath $sourceScriptPath -Destination $installedScriptPath -Force
Copy-Item -LiteralPath $sourceRuntimeHelper -Destination $installedRuntimeHelper -Force

$windowsCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' +
	$installedScriptPath + '"'
$hookConfig = Get-HookConfig
Remove-OpenDesktopPetStopHook $hookConfig
$existingStopHooks = if ($null -ne $hookConfig.hooks.PSObject.Properties['Stop']) {
	@($hookConfig.hooks.Stop)
} else {
	@()
}
$stopHook = [pscustomobject]@{
	type = 'command'
	windows = $windowsCommand
	timeout = 5
}
$hookConfig.hooks | Add-Member -MemberType NoteProperty -Name Stop -Value (@($existingStopHooks) + @($stopHook)) -Force
Save-HookConfig $hookConfig
Set-Content -LiteralPath $installMarker -Value '1' -Encoding ASCII
Write-Output "Copilot user hook installed: $hookConfigPath"
Write-Output "Notification bridge: $installedScriptPath"
Write-Output 'Reload VS Code to apply the hook configuration.'
