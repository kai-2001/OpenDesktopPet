param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$pluginsHome = Join-Path $env:USERPROFILE '.config\opencode\plugins'
$pluginPath = Join-Path $pluginsHome 'open-desktop-pet.js'
$installedBridgePath = Join-Path $integrationHome 'opencode_notify.ps1'
$sourcePluginPath = Join-Path $PSScriptRoot 'opencode_notify_plugin.js'
$sourceBridgePath = Join-Path $PSScriptRoot 'opencode_notify.ps1'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_opencode_installed.txt'
$markerText = 'OpenDesktopPet OpenCode notification plugin'

if ($Uninstall) {
    if (Test-Path -LiteralPath $pluginPath) {
        $pluginText = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
        if ($pluginText.Contains($markerText)) {
            Remove-Item -LiteralPath $pluginPath -Force
        }
    }
    if (Test-Path -LiteralPath $installedBridgePath) {
        Remove-Item -LiteralPath $installedBridgePath -Force
    }
    if (Test-Path -LiteralPath $installMarker) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    Write-Output "Removed OpenCode notification plugin: $pluginPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourcePluginPath -PathType Leaf)) {
    throw "OpenCode plugin source not found: $sourcePluginPath"
}
if (-not (Test-Path -LiteralPath $sourceBridgePath -PathType Leaf)) {
    throw "OpenCode bridge source not found: $sourceBridgePath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $pluginsHome | Out-Null

if (Test-Path -LiteralPath $pluginPath) {
    $existingPluginText = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
    if (-not $existingPluginText.Contains($markerText)) {
        $backupPath = "$pluginPath.open-desktop-pet-backup-$(Get-Date -Format 'yyyyMMddHHmmss').js"
        Move-Item -LiteralPath $pluginPath -Destination $backupPath -Force
        Write-Warning "Existing OpenCode plugin was backed up to $backupPath"
    }
}

Copy-Item -LiteralPath $sourcePluginPath -Destination $pluginPath -Force
Copy-Item -LiteralPath $sourceBridgePath -Destination $installedBridgePath -Force
Set-Content -LiteralPath $installMarker -Value '1' -Encoding ASCII

Write-Output "OpenCode notification plugin installed: $pluginPath"
Write-Output "Notification bridge: $installedBridgePath"
Write-Output 'Restart OpenCode to load the plugin.'
