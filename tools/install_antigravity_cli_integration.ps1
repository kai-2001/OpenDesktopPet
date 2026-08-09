param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$antigravityConfigHome = Join-Path $env:USERPROFILE '.gemini\config'
$hooksPath = Join-Path $antigravityConfigHome 'hooks.json'
$installedBridgePath = Join-Path $integrationHome 'antigravity_cli_notify.ps1'
$sourceBridgePath = Join-Path $PSScriptRoot 'antigravity_cli_notify.ps1'
$installedRuntimeHelper = Join-Path $integrationHome 'open_desktop_pet_runtime.ps1'
$sourceRuntimeHelper = Join-Path $PSScriptRoot 'open_desktop_pet_runtime.ps1'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_antigravity_cli_installed.txt'
$markerText = 'OpenDesktopPet Antigravity CLI notification hook'
$hookName = 'open-desktop-pet'

function New-EmptySettings {
    return [pscustomobject]@{}
}

function Get-Settings {
    if (-not (Test-Path -LiteralPath $hooksPath)) {
        return New-EmptySettings
    }
    try {
        $settings = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $settings) {
            return New-EmptySettings
        }
        return $settings
    } catch {
        $backupPath = "$hooksPath.invalid-$(Get-Date -Format 'yyyyMMddHHmmss').bak"
        Copy-Item -LiteralPath $hooksPath -Destination $backupPath -Force
        Write-Warning "Existing invalid Antigravity CLI hooks were backed up to $backupPath"
        return New-EmptySettings
    }
}

function Save-Settings($settings) {
    New-Item -ItemType Directory -Force -Path $antigravityConfigHome | Out-Null
    $tempPath = "$hooksPath.open-desktop-pet.tmp"
    $json = $settings | ConvertTo-Json -Depth 20
    # Windows PowerShell 5.1's `-Encoding UTF8` writes a BOM. Keep the
    # configuration compatible with Antigravity CLI's JSON parser.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $hooksPath -Force
}

function Get-HookDefinition($settings) {
    $property = $settings.PSObject.Properties[$hookName]
    if ($null -eq $property -or $null -eq $property.Value) {
        $settings | Add-Member -MemberType NoteProperty -Name $hookName -Value ([pscustomobject]@{})
    }
    return $settings.PSObject.Properties[$hookName].Value
}

function Get-HookEntries($hookDefinition, [string]$eventName) {
    if ($null -eq $hookDefinition.PSObject.Properties[$eventName]) {
        return @()
    }
    return @($hookDefinition.$eventName)
}

function Test-OpenDesktopPetHookCommand([string]$command) {
    if ($command -like '*antigravity_cli_notify.ps1*') {
        return $true
    }
    try {
        $encodedCommandMatch = [regex]::Match(
            $command,
            '(?i)-EncodedCommand\s+([A-Za-z0-9+/=]+)'
        )
        if (-not $encodedCommandMatch.Success) {
            return $false
        }
        $decodedInvocation = [Text.Encoding]::Unicode.GetString(
            [Convert]::FromBase64String($encodedCommandMatch.Groups[1].Value)
        )
        return $decodedInvocation -like '*antigravity_cli_notify.ps1*'
    } catch {
        return $false
    }
}

function Test-OpenDesktopPetHook($entry) {
    if (Test-OpenDesktopPetHookCommand ([string]$entry.command)) {
        return $true
    }
    foreach ($hook in @($entry.hooks)) {
        if (Test-OpenDesktopPetHookCommand ([string]$hook.command)) {
            return $true
        }
    }
    return $false
}

function Remove-OpenDesktopPetHooks($settings) {
    $property = $settings.PSObject.Properties[$hookName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return
    }
    $hookDefinition = $property.Value
    foreach ($eventName in @('Stop')) {
        if ($null -eq $hookDefinition.PSObject.Properties[$eventName]) {
            continue
        }
        $remaining = @(Get-HookEntries $hookDefinition $eventName | Where-Object {
            -not (Test-OpenDesktopPetHook $_)
        })
        if ($remaining.Count -eq 0) {
            $hookDefinition.PSObject.Properties.Remove($eventName)
        } else {
            $hookDefinition | Add-Member -MemberType NoteProperty -Name $eventName `
                -Value $remaining -Force
        }
    }
    if ($hookDefinition.PSObject.Properties.Count -eq 0) {
        $settings.PSObject.Properties.Remove($hookName)
    }
}

function New-AntigravityHookEntry([string]$command) {
    return [pscustomobject]@{
        type = 'command'
        command = $command
        timeout = 5
    }
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $hooksPath) {
        $settings = Get-Settings
        Remove-OpenDesktopPetHooks $settings
        Save-Settings $settings
    }
    if (Test-Path -LiteralPath $installedBridgePath) {
        Remove-Item -LiteralPath $installedBridgePath -Force
    }
    if (Test-Path -LiteralPath $installMarker) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    Write-Output "Removed Antigravity CLI notification hook: $hooksPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceBridgePath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $sourceRuntimeHelper -PathType Leaf)) {
    throw "Antigravity CLI bridge source not found: $sourceBridgePath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $antigravityConfigHome | Out-Null
Copy-Item -LiteralPath $sourceBridgePath -Destination $installedBridgePath -Force
Copy-Item -LiteralPath $sourceRuntimeHelper -Destination $installedRuntimeHelper -Force
Set-Content -LiteralPath $installMarker -Value $markerText -Encoding ASCII

# Antigravity's Windows hook runner evaluates this command through a shell
# wrapper. A quoted -File path is passed through with its quote characters,
# while an unquoted path fails for Windows user profiles containing spaces.
# Use PowerShell's UTF-16LE encoded command form so the hook command itself
# contains no path or shell-sensitive quotes. The child PowerShell process
# inherits Antigravity's JSON stdin and passes it to the bridge unchanged.
$bridgeInvocation = "& '{0}'" -f $installedBridgePath.Replace("'", "''")
$encodedBridgeInvocation = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($bridgeInvocation)
)
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' +
    $encodedBridgeInvocation
$settings = Get-Settings
Remove-OpenDesktopPetHooks $settings
$hookDefinition = Get-HookDefinition $settings
$existingStopHooks = @(Get-HookEntries $hookDefinition 'Stop')
$hookDefinition | Add-Member -MemberType NoteProperty -Name 'Stop' -Value @(
    $existingStopHooks
    New-AntigravityHookEntry $command
) -Force
Save-Settings $settings

Write-Output "Antigravity CLI notification hook installed: $hooksPath"
Write-Output "Notification bridge: $installedBridgePath"
Write-Output 'Restart Antigravity CLI sessions to apply the hook configuration.'
