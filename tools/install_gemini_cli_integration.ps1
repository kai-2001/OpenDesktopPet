param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$geminiHome = Join-Path $env:USERPROFILE '.gemini'
$settingsPath = Join-Path $geminiHome 'settings.json'
$installedBridgePath = Join-Path $integrationHome 'gemini_cli_notify.ps1'
$sourceBridgePath = Join-Path $PSScriptRoot 'gemini_cli_notify.ps1'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_gemini_cli_installed.txt'
$markerText = 'OpenDesktopPet Gemini CLI notification hooks'
$hookEvents = @('AfterAgent', 'Notification')

function New-EmptySettings {
    return [pscustomobject]@{
        hooks = [pscustomobject]@{}
    }
}

function Get-Settings {
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return New-EmptySettings
    }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ($null -eq $settings) {
            return New-EmptySettings
        }
        if ($null -eq $settings.PSObject.Properties['hooks']) {
            $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
        } elseif ($null -eq $settings.hooks) {
            $settings.hooks = [pscustomobject]@{}
        }
        return $settings
    } catch {
        $backupPath = "$settingsPath.invalid-$(Get-Date -Format 'yyyyMMddHHmmss').bak"
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
        Write-Warning "Existing invalid Gemini CLI settings were backed up to $backupPath"
        return New-EmptySettings
    }
}

function Save-Settings($settings) {
    New-Item -ItemType Directory -Force -Path $geminiHome | Out-Null
    $tempPath = "$settingsPath.open-desktop-pet.tmp"
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $settingsPath -Force
}

function Get-HookEntries($settings, [string]$eventName) {
    if ($null -eq $settings.hooks.PSObject.Properties[$eventName]) {
        return @()
    }
    return @($settings.hooks.$eventName)
}

function Test-OpenDesktopPetHook($entry) {
    foreach ($hook in @($entry.hooks)) {
        if ([string]$hook.command -like '*gemini_cli_notify.ps1*') {
            return $true
        }
    }
    return $false
}

function Remove-OpenDesktopPetHooks($settings) {
    foreach ($eventName in $hookEvents) {
        if ($null -eq $settings.hooks.PSObject.Properties[$eventName]) {
            continue
        }
        $remaining = @(Get-HookEntries $settings $eventName | Where-Object {
            -not (Test-OpenDesktopPetHook $_)
        })
        if ($remaining.Count -eq 0) {
            $settings.hooks.PSObject.Properties.Remove($eventName)
        } else {
            $settings.hooks | Add-Member -MemberType NoteProperty -Name $eventName `
                -Value $remaining -Force
        }
    }
}

function New-GeminiHookEntry([string]$command, [string]$matcher = '') {
    $commandHook = [pscustomobject]@{
        type = 'command'
        command = $command
        timeout = 5000
    }
    $entry = [ordered]@{
        hooks = @($commandHook)
    }
    if (-not [string]::IsNullOrWhiteSpace($matcher)) {
        $entry.matcher = $matcher
    }
    return [pscustomobject]$entry
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $settingsPath) {
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
    Write-Output "Removed Gemini CLI notification hooks: $settingsPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceBridgePath -PathType Leaf)) {
    throw "Gemini CLI bridge source not found: $sourceBridgePath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $geminiHome | Out-Null
Copy-Item -LiteralPath $sourceBridgePath -Destination $installedBridgePath -Force
Set-Content -LiteralPath $installMarker -Value $markerText -Encoding ASCII

$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    $installedBridgePath + '"'
$settings = Get-Settings
Remove-OpenDesktopPetHooks $settings
$existingAfterAgentHooks = @(Get-HookEntries $settings 'AfterAgent')
$existingNotificationHooks = @(Get-HookEntries $settings 'Notification')
$settings.hooks | Add-Member -MemberType NoteProperty -Name 'AfterAgent' -Value @(
    $existingAfterAgentHooks
    New-GeminiHookEntry $command
) -Force
$settings.hooks | Add-Member -MemberType NoteProperty -Name 'Notification' -Value @(
    $existingNotificationHooks
    New-GeminiHookEntry $command 'ToolPermission'
) -Force
Save-Settings $settings

Write-Output "Gemini CLI notification hooks installed: $settingsPath"
Write-Output "Notification bridge: $installedBridgePath"
Write-Output 'Restart Gemini CLI sessions to apply the hook configuration.'
