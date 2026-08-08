$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_codex_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Codex-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$testCodexHome = Join-Path $testRoot 'codex-home'
$configPath = Join-Path $testCodexHome 'config.toml'
$originalCodexHome = $env:CODEX_HOME

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testCodexHome | Out-Null
    $env:CODEX_HOME = $testCodexHome
    $escapedScriptPath = (Join-Path $testCodexHome 'open_desktop_pet_notify.ps1').Replace('\', '\\')
    $misplacedConfig = @"
model = "gpt-5.6-luna"
model_reasoning_effort = "high"

[windows]
sandbox = "elevated"

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

notify = [
  "powershell.exe",
  "-NoProfile",
  "-File",
  "$escapedScriptPath"
]
"@
    Set-Content -LiteralPath $configPath -Value $misplacedConfig -Encoding UTF8

    & $installerPath | Write-Output
    $installedConfig = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
    $notifyIndex = $installedConfig.IndexOf('notify = [')
    $windowsIndex = $installedConfig.IndexOf('[windows]')
    $notifyCount = [regex]::Matches($installedConfig, '(?m)^[ \t]*notify[ \t]*=').Count

    Assert-Installer ($notifyIndex -ge 0) 'The installer did not write the notify root key.'
    Assert-Installer ($notifyIndex -lt $windowsIndex) 'The notify key must appear before the first TOML table.'
    Assert-Installer ($notifyCount -eq 1) 'The installer must keep exactly one notify key.'
    Assert-Installer ($installedConfig -match [regex]::Escape($escapedScriptPath)) `
        'The installer wrote the wrong notification bridge path.'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $testCodexHome 'open_desktop_pet_notify.ps1')) `
        'The installer did not copy the notification bridge.'

    & $installerPath | Write-Output
    $reinstalledConfig = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
    Assert-Installer ($reinstalledConfig -eq $installedConfig) `
        'Reinstalling the same notification configuration must be idempotent.'

    $doubleEscapedScriptPath = $escapedScriptPath.Replace('\\', '\\\\')
    $computerUseConfig = @"
model = "gpt-5.6-luna"

notify = [ "C:\\Program Files\\OpenAI\\codex-computer-use.exe", "turn-ended", "--previous-notify", "[\"powershell.exe\",\"-NoProfile\",\"-File\",\"$doubleEscapedScriptPath\"]" ]

[windows]
sandbox = "elevated"
"@
    Set-Content -LiteralPath $configPath -Value $computerUseConfig -Encoding UTF8
    & $installerPath | Write-Output
    $wrappedConfig = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
    $wrappedNotifyCount = [regex]::Matches($wrappedConfig, '(?m)^[ \t]*notify[ \t]*=').Count
    Assert-Installer ($wrappedNotifyCount -eq 1) `
        'A nested Computer Use notify array must remain a single notify key.'
    Assert-Installer ($wrappedConfig -match 'codex-computer-use\.exe') `
        'The existing Computer Use notify wrapper must be preserved.'
    Assert-Installer ($wrappedConfig -match 'open_desktop_pet_notify\.ps1') `
        'The existing previous-notify desktop-pet bridge must be preserved.'

    Write-Output 'CODEX_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
    $env:CODEX_HOME = $originalCodexHome
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
