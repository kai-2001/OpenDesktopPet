param(
	[switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
	Join-Path $env:USERPROFILE '.codex'
} else {
	$env:CODEX_HOME
}
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$hookConfigPath = Join-Path $codexHome 'hooks.json'
$configPath = Join-Path $codexHome 'config.toml'
$installedStopBridge = Join-Path $integrationHome 'codex_stop_notify.ps1'
$installedRuntimeHelper = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
$sourceStopBridge = Join-Path $PSScriptRoot 'codex_stop_notify.ps1'
$sourceRuntimeHelper = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
$installMarker = Join-Path $codexHome 'open_desktop_pet_codex_installed.txt'

# Legacy notify paths are retained only for migration and uninstall cleanup.
# New installations never create these files.
$legacyNotifyBridge = Join-Path $codexHome 'open_desktop_pet_notify.ps1'
$legacyPreviousNotify = Join-Path $codexHome 'open_desktop_pet_previous_notify.json'
$stopBridgeFileName = [IO.Path]::GetFileName($installedStopBridge)
$legacyBridgeFileName = [IO.Path]::GetFileName($legacyNotifyBridge)

function Save-HookConfig($config) {
	$tempPath = "$hookConfigPath.open-desktop-pet.tmp"
	$config | ConvertTo-Json -Depth 20 |
		Set-Content -LiteralPath $tempPath -Encoding UTF8
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
		Write-Warning "Existing invalid Codex hook config was backed up to $backupPath"
		return [pscustomobject]@{ hooks = [pscustomobject]@{} }
	}
}

function Test-IsOpenDesktopPetHandler($handler) {
	$command = [string]$handler.command
	$windowsCommand = [string]$handler.commandWindows
	return $command -like "*$stopBridgeFileName*" -or
		$windowsCommand -like "*$stopBridgeFileName*"
}

function Remove-OpenDesktopPetStopHook($config) {
	if ($null -eq $config.hooks -or $null -eq $config.hooks.PSObject.Properties['Stop']) {
		return
	}
	$remainingGroups = @()
	foreach ($group in @($config.hooks.Stop)) {
		if ($null -eq $group.PSObject.Properties['hooks']) {
			$remainingGroups += $group
			continue
		}
		$remainingHandlers = @($group.hooks | Where-Object {
			-not (Test-IsOpenDesktopPetHandler $_)
		})
		if ($remainingHandlers.Count -gt 0) {
			$group | Add-Member -MemberType NoteProperty -Name hooks `
				-Value $remainingHandlers -Force
			$remainingGroups += $group
		}
	}
	if ($remainingGroups.Count -eq 0) {
		$config.hooks.PSObject.Properties.Remove('Stop')
	} else {
		$config.hooks | Add-Member -MemberType NoteProperty -Name Stop `
			-Value $remainingGroups -Force
	}
}

function Get-NotifyAssignments([string]$text) {
	$assignments = @()
	$searchIndex = 0
	$notifyRegex = [regex]::new('(?m)^[ \t]*notify[ \t]*=')
	while ($searchIndex -lt $text.Length) {
		$match = $notifyRegex.Match($text, $searchIndex)
		if (-not $match.Success) {
			break
		}
		$openIndex = $text.IndexOf('[', $match.Index + $match.Length)
		if ($openIndex -lt 0) {
			break
		}
		$depth = 0
		$inString = $false
		$escaped = $false
		$closeIndex = -1
		for ($index = $openIndex; $index -lt $text.Length; $index++) {
			$character = $text[$index]
			if ($inString) {
				if ($escaped) {
					$escaped = $false
				} elseif ($character -eq '\') {
					$escaped = $true
				} elseif ($character -eq '"') {
					$inString = $false
				}
				continue
			}
			if ($character -eq '"') {
				$inString = $true
			} elseif ($character -eq '[') {
				$depth++
			} elseif ($character -eq ']') {
				$depth--
				if ($depth -eq 0) {
					$closeIndex = $index + 1
					break
				}
			}
		}
		if ($closeIndex -lt 0) {
			break
		}
		$blockEnd = $closeIndex
		while ($blockEnd -lt $text.Length -and $text[$blockEnd] -match '[ \t]') {
			$blockEnd++
		}
		if ($blockEnd + 1 -lt $text.Length -and $text.Substring($blockEnd, 2) -eq "`r`n") {
			$blockEnd += 2
		} elseif ($blockEnd -lt $text.Length -and $text[$blockEnd] -eq "`n") {
			$blockEnd++
		}
		$assignments += [pscustomobject]@{
			Start = $match.Index
			End = $blockEnd
			Text = $text.Substring($match.Index, $blockEnd - $match.Index)
		}
		$searchIndex = $blockEnd
	}
	return $assignments
}

function ConvertFrom-TomlStringArray([string]$text) {
	$matches = [regex]::Matches($text, '"((?:\\.|[^"\\])*)"')
	$values = @()
	foreach ($match in $matches) {
		$value = $match.Groups[1].Value
		$value = $value.Replace('\\', '\')
		$value = $value.Replace('\"', '"')
		$value = $value.Replace('\n', "`n")
		$value = $value.Replace('\r', "`r")
		$value = $value.Replace('\t', "`t")
		$values += $value
	}
	return $values
}

function ConvertTo-TomlBasicString([string]$value) {
	return $value.Replace('\', '\\').Replace('"', '\"').Replace(
		"`r", '\r'
	).Replace("`n", '\n').Replace("`t", '\t')
}

function New-NotifyBlock([object[]]$command) {
	$lines = @('notify = [')
	for ($index = 0; $index -lt $command.Count; $index++) {
		$comma = if ($index -lt $command.Count - 1) { ',' } else { '' }
		$lines += ('  "{0}"{1}' -f (
			ConvertTo-TomlBasicString ([string]$command[$index])
		), $comma)
	}
	$lines += ']'
	return $lines -join [Environment]::NewLine
}

function Get-LegacyPreviousNotifyCommand {
	if (-not (Test-Path -LiteralPath $legacyPreviousNotify)) {
		return @()
	}
	try {
		$document = Get-Content -LiteralPath $legacyPreviousNotify -Raw -Encoding UTF8 |
			ConvertFrom-Json
		return @($document.command)
	} catch {
		return @()
	}
}

function Convert-LegacyNotifyCommand([object[]]$command, [object[]]$previousCommand) {
	$legacyArgumentIndex = -1
	for ($index = 0; $index -lt $command.Count; $index++) {
		if ([string]$command[$index] -like "*$legacyBridgeFileName*") {
			$legacyArgumentIndex = $index
			break
		}
	}
	if ($legacyArgumentIndex -lt 0) {
		return [pscustomobject]@{ Changed = $false; Command = $command }
	}

	if ($legacyArgumentIndex -gt 0 -and
		[string]$command[$legacyArgumentIndex - 1] -eq '--previous-notify') {
		$replacement = @($command)
		if ($previousCommand.Count -gt 0) {
			$replacement[$legacyArgumentIndex] = ConvertTo-Json `
				-InputObject @($previousCommand) -Compress
		} else {
			$before = if ($legacyArgumentIndex -gt 1) {
				@($replacement[0..($legacyArgumentIndex - 2)])
			} else {
				@()
			}
			$after = if ($legacyArgumentIndex + 1 -lt $replacement.Count) {
				@($replacement[($legacyArgumentIndex + 1)..($replacement.Count - 1)])
			} else {
				@()
			}
			$replacement = @($before + $after)
		}
		return [pscustomobject]@{ Changed = $true; Command = $replacement }
	}

	return [pscustomobject]@{
		Changed = $true
		Command = @($previousCommand)
	}
}

function Remove-LegacyNotifyIntegration {
	if (-not (Test-Path -LiteralPath $configPath)) {
		return
	}
	$configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
	$previousCommand = @(Get-LegacyPreviousNotifyCommand)
	$assignments = @(Get-NotifyAssignments $configText)
	$changed = $false
	for ($index = $assignments.Count - 1; $index -ge 0; $index--) {
		$assignment = $assignments[$index]
		$command = @(ConvertFrom-TomlStringArray $assignment.Text)
		$migration = Convert-LegacyNotifyCommand $command $previousCommand
		if (-not $migration.Changed) {
			continue
		}
		$replacement = ''
		if (@($migration.Command).Count -gt 0) {
			$replacement = (New-NotifyBlock @($migration.Command)) + [Environment]::NewLine
		}
		$configText = $configText.Remove(
			$assignment.Start, $assignment.End - $assignment.Start
		).Insert($assignment.Start, $replacement)
		$changed = $true
	}
	if ($changed) {
		$backupPath = "$configPath.open-desktop-pet-stop-migration-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
		Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
		Write-Output "Backed up the legacy Codex notify configuration to: $backupPath"
		Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
	}
	foreach ($legacyPath in @($legacyPreviousNotify, $legacyNotifyBridge)) {
		if (Test-Path -LiteralPath $legacyPath) {
			Remove-Item -LiteralPath $legacyPath -Force
		}
	}
}

New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null

if ($Uninstall) {
	if (Test-Path -LiteralPath $hookConfigPath) {
		try {
			$hookConfig = Get-HookConfig
			Remove-OpenDesktopPetStopHook $hookConfig
			Save-HookConfig $hookConfig
		} catch {
			Write-Warning 'Could not update existing Codex hook config; leaving it unchanged.'
		}
	}
	Remove-LegacyNotifyIntegration
	foreach ($path in @($installedStopBridge, $installMarker)) {
		if (Test-Path -LiteralPath $path) {
			Remove-Item -LiteralPath $path -Force
		}
	}
	Write-Output "Removed Codex Stop hook: $hookConfigPath"
	exit 0
}

if (-not (Test-Path -LiteralPath $sourceStopBridge) -or
	-not (Test-Path -LiteralPath $sourceRuntimeHelper)) {
	throw "Codex Stop-hook bridge not found: $sourceStopBridge"
}

Remove-LegacyNotifyIntegration
Copy-Item -LiteralPath $sourceStopBridge -Destination $installedStopBridge -Force
Copy-Item -LiteralPath $sourceRuntimeHelper -Destination $installedRuntimeHelper -Force

$windowsCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' +
	$installedStopBridge + '"'
$hookConfig = Get-HookConfig
Remove-OpenDesktopPetStopHook $hookConfig
$existingStopGroups = if ($null -ne $hookConfig.hooks.PSObject.Properties['Stop']) {
	@($hookConfig.hooks.Stop)
} else {
	@()
}
$stopHandler = [pscustomobject]@{
	type = 'command'
	command = $windowsCommand
	commandWindows = $windowsCommand
	async = $true
	timeout = 5
}
$stopGroup = [pscustomobject]@{ hooks = @($stopHandler) }
$hookConfig.hooks | Add-Member -MemberType NoteProperty -Name Stop `
	-Value (@($existingStopGroups) + @($stopGroup)) -Force
Save-HookConfig $hookConfig
Set-Content -LiteralPath $installMarker -Value '1' -Encoding ASCII

Write-Output "Codex Stop hook installed: $hookConfigPath"
Write-Output "Notification bridge: $installedStopBridge"
Write-Output 'Restart Codex or VS Code, then review and trust the hook when prompted.'
