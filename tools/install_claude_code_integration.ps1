param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$claudeHome = Join-Path $env:USERPROFILE '.claude'
$settingsPath = Join-Path $claudeHome 'settings.json'
$installedBridgePath = Join-Path $integrationHome 'claude_code_notify.ps1'
$sourceBridgePath = Join-Path $PSScriptRoot 'claude_code_notify.ps1'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_claude_code_installed.txt'
$markerText = 'OpenDesktopPet Claude Code notification hook'
$hookEvents = @('Stop', 'Notification', 'StopFailure')

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
        Write-Warning "Existing invalid Claude Code settings were backed up to $backupPath"
        return New-EmptySettings
    }
}

function Save-Settings($settings) {
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
        if ([string]$hook.command -like '*claude_code_notify.ps1*') {
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

function New-ClaudeHookEntry([string]$command, [string]$matcher = '') {
    $commandHook = [pscustomobject]@{
        type = 'command'
        command = $command
        timeout = 5
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
    Write-Output "Removed Claude Code notification hooks: $settingsPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceBridgePath -PathType Leaf)) {
    throw "Claude Code bridge source not found: $sourceBridgePath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $claudeHome | Out-Null
Copy-Item -LiteralPath $sourceBridgePath -Destination $installedBridgePath -Force
Set-Content -LiteralPath $installMarker -Value $markerText -Encoding ASCII

$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    $installedBridgePath + '"'
$settings = Get-Settings
Remove-OpenDesktopPetHooks $settings
$existingStopHooks = @(Get-HookEntries $settings 'Stop')
$existingNotificationHooks = @(Get-HookEntries $settings 'Notification')
$existingStopFailureHooks = @(Get-HookEntries $settings 'StopFailure')
$settings.hooks | Add-Member -MemberType NoteProperty -Name 'Stop' -Value @(
    $existingStopHooks
    New-ClaudeHookEntry $command
) -Force
$settings.hooks | Add-Member -MemberType NoteProperty -Name 'Notification' -Value @(
    $existingNotificationHooks
    New-ClaudeHookEntry $command 'permission_prompt|idle_prompt|agent_needs_input|agent_completed|elicitation_dialog'
) -Force
$settings.hooks | Add-Member -MemberType NoteProperty -Name 'StopFailure' -Value @(
    $existingStopFailureHooks
    New-ClaudeHookEntry $command
) -Force
Save-Settings $settings

Write-Output "Claude Code notification hooks installed: $settingsPath"
Write-Output "Notification bridge: $installedBridgePath"
Write-Output 'Restart Claude Code sessions to apply the hook configuration.'
