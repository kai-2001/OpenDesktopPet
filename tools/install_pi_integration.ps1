param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$piAgentHome = if ([string]::IsNullOrWhiteSpace($env:PI_CODING_AGENT_DIR)) {
    Join-Path $env:USERPROFILE '.pi\agent'
} else {
    [string]$env:PI_CODING_AGENT_DIR
}
if ($piAgentHome -eq '~') {
    $piAgentHome = $env:USERPROFILE
} elseif ($piAgentHome.StartsWith('~\') -or $piAgentHome.StartsWith('~/')) {
    $piAgentHome = Join-Path $env:USERPROFILE $piAgentHome.Substring(2)
}
$extensionsHome = Join-Path $piAgentHome 'extensions'
$extensionPath = Join-Path $extensionsHome 'open-desktop-pet.ts'
$sourceExtensionPath = Join-Path $PSScriptRoot 'pi_agent_notify.ts'
$installMarker = Join-Path $integrationHome 'open_desktop_pet_pi_installed.txt'
$markerText = 'OpenDesktopPet Pi notification extension'
$legacyMarkerText = 'OpenDesktopPet Pi Codex notification extension'
$backupSearchPattern = 'open-desktop-pet.ts.open-desktop-pet-backup-*.ts'

function Get-ExtensionBackups {
    if (-not (Test-Path -LiteralPath $extensionsHome -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $extensionsHome -Filter $backupSearchPattern -File |
        Sort-Object LastWriteTimeUtc -Descending)
}

if ($Uninstall) {
    $removedExtension = $false
    if (Test-Path -LiteralPath $extensionPath -PathType Leaf) {
        $extensionText = Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8
        if ($extensionText.Contains($markerText) -or $extensionText.Contains($legacyMarkerText)) {
            Remove-Item -LiteralPath $extensionPath -Force
            $removedExtension = $true
        }
    }
    if ($removedExtension) {
        $backups = @(Get-ExtensionBackups)
        if ($backups.Count -gt 0) {
            Move-Item -LiteralPath $backups[0].FullName -Destination $extensionPath -Force
            Write-Output "Restored the previous Pi extension: $extensionPath"
        }
    }
    if (Test-Path -LiteralPath $installMarker -PathType Leaf) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    Write-Output "Removed Pi notification extension: $extensionPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceExtensionPath -PathType Leaf)) {
    throw "Pi notification extension source not found: $sourceExtensionPath"
}

New-Item -ItemType Directory -Force -Path $integrationHome | Out-Null
New-Item -ItemType Directory -Force -Path $extensionsHome | Out-Null

if (Test-Path -LiteralPath $extensionPath -PathType Leaf) {
    $existingExtensionText = Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8
    if (-not ($existingExtensionText.Contains($markerText) -or
            $existingExtensionText.Contains($legacyMarkerText))) {
        $backupPath = "$extensionPath.open-desktop-pet-backup-$(Get-Date -Format 'yyyyMMddHHmmss').ts"
        Move-Item -LiteralPath $extensionPath -Destination $backupPath -Force
        Write-Warning "Existing Pi extension was backed up to $backupPath"
    }
}

Copy-Item -LiteralPath $sourceExtensionPath -Destination $extensionPath -Force
Set-Content -LiteralPath $installMarker -Value $markerText -Encoding ASCII

Write-Output "Pi notification extension installed: $extensionPath"
Write-Output 'Restart Pi or run /reload to load the extension.'
