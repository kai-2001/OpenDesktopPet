param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$antigravityConfigHome = Join-Path $env:USERPROFILE '.gemini\config'
$hooksPath = Join-Path $antigravityConfigHome 'hooks.json'
$installedBridgePath = Join-Path $integrationHome 'antigravity_cli_notify.ps1'
$sourceBridgePath = Join-Path $PSScriptRoot 'antigravity_cli_notify.ps1'
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

function Test-OpenDesktopPetHook($entry) {
    if ([string]$entry.command -like '*antigravity_cli_notify.ps1*') {
        return $true
    }
    foreach ($hook in @($entry.hooks)) {
        if ([string]$hook.command -like '*antigravity_cli_notify.ps1*') {
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

if (-not (Test-Path -LiteralPath $sourceBridgePath -PathType Leaf)) {
    throw "Antigravity CLI bridge source not found: $sourceBridgePath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $antigravityConfigHome | Out-Null
Copy-Item -LiteralPath $sourceBridgePath -Destination $installedBridgePath -Force
Set-Content -LiteralPath $installMarker -Value $markerText -Encoding ASCII

# Antigravity's Windows hook runner evaluates this command through a shell
# wrapper. Do not add another pair of quotes around the -File path: the
# wrapper would pass those quote characters into PowerShell as part of the
# filename. Also avoid -WindowStyle Hidden because the hook inherits the
# active console and can hide/minimize the parent PowerShell window.
# Windows user profile directories normally contain no spaces.
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' +
    $installedBridgePath
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
