param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $env:USERPROFILE '.codex'
} else {
    $env:CODEX_HOME
}
$configPath = Join-Path $codexHome 'config.toml'
$installedNotifyScript = Join-Path $codexHome 'open_desktop_pet_notify.ps1'
$sourceNotifyScript = Join-Path $PSScriptRoot 'codex_notify.ps1'

New-Item -ItemType Directory -Force -Path $codexHome | Out-Null

if ($Uninstall) {
    if (Test-Path -LiteralPath $configPath) {
        $configText = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
        $notifyPattern = '(?ms)^[ \t]*notify[ \t]*=[ \t]*\[[^\]]*\][ \t]*(?:\r?\n|$)'
        $updatedText = [regex]::Replace($configText, $notifyPattern, '', 1)
        Set-Content -LiteralPath $configPath -Value $updatedText -Encoding UTF8
    }
    if (Test-Path -LiteralPath $installedNotifyScript) {
        Remove-Item -LiteralPath $installedNotifyScript -Force
    }
    Write-Output "Removed Codex notification configuration: $configPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceNotifyScript)) {
    throw "Notification bridge not found: $sourceNotifyScript"
}

Copy-Item -LiteralPath $sourceNotifyScript -Destination $installedNotifyScript -Force

$escapedScriptPath = $installedNotifyScript.Replace('\', '\\')
$notifyBlock = @(
    'notify = ['
    '  "powershell.exe",'
    '  "-NoProfile",'
    '  "-File",'
    "  `"$escapedScriptPath`""
    ']'
) -join [Environment]::NewLine

$configText = if (Test-Path -LiteralPath $configPath) {
    Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
} else {
    ''
}

$notifyPattern = '(?ms)^[ \t]*notify[ \t]*=[ \t]*\[[^\]]*\][ \t]*(?:\r?\n|$)'
if ([regex]::IsMatch($configText, $notifyPattern)) {
    $backupPath = "$configPath.open-desktop-pet-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    $configText = [regex]::Replace(
        $configText,
        $notifyPattern,
        $notifyBlock + [Environment]::NewLine,
        1
    )
    Write-Output "Backed up the previous Codex configuration to: $backupPath"
} else {
    if (-not [string]::IsNullOrWhiteSpace($configText) -and -not $configText.EndsWith("`n")) {
        $configText += [Environment]::NewLine
    }
    $configText += [Environment]::NewLine + $notifyBlock + [Environment]::NewLine
}

Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
Write-Output "Codex notification installed: $configPath"
Write-Output "Notification bridge: $installedNotifyScript"
Write-Output 'Restart VS Code or Codex to apply the configuration.'
