$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_antigravity_cli_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Antigravity-CLI-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$geminiConfigHome = Join-Path $testRoot '.gemini\config'
$hooksPath = Join-Path $geminiConfigHome 'hooks.json'
$originalUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $geminiConfigHome | Out-Null
    $env:USERPROFILE = $testRoot
    @'
{
  "existing": {
    "PostToolUse": [
      {"matcher": "run_command", "hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-post.ps1"}]}
    ]
  },
  "open-desktop-pet": {
    "Stop": [
      {"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-stop.ps1"}
    ],
    "PostInvocation": [
      {"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-invocation.ps1"}
    ]
  }
}
'@ | Set-Content -LiteralPath $hooksPath -Encoding UTF8

    & $installerPath | Out-Null
    $settings = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $settingsBytes = [System.IO.File]::ReadAllBytes($hooksPath)
    Assert-Installer (-not (
        $settingsBytes.Length -ge 3 -and
        $settingsBytes[0] -eq 0xEF -and
        $settingsBytes[1] -eq 0xBB -and
        $settingsBytes[2] -eq 0xBF
    )) 'Antigravity installer wrote a UTF-8 BOM.'
    $stopCommands = @($settings.'open-desktop-pet'.Stop | ForEach-Object { $_.command })
    Assert-Installer ($stopCommands.Count -eq 2) 'Antigravity installer removed an existing Stop hook.'
    Assert-Installer (($stopCommands | Where-Object { $_ -like '*antigravity_cli_notify.ps1*' }).Count -eq 1) `
        'Antigravity installer did not add exactly one Stop hook.'
    Assert-Installer ($settings.'open-desktop-pet'.Stop[1].command -notmatch '-File\s+["'']') `
        'Antigravity installer must not quote the -File path for its Windows hook runner.'
    Assert-Installer ($settings.'open-desktop-pet'.Stop[1].command -notmatch 'WindowStyle') `
        'Antigravity installer must not hide the parent PowerShell console.'
    Assert-Installer ($settings.'open-desktop-pet'.Stop[1].timeout -eq 5) `
        'Antigravity installer must use a five-second hook timeout.'
    Assert-Installer ($settings.'open-desktop-pet'.PostInvocation[0].command -like '*existing-invocation.ps1*') `
        'Antigravity installer removed an unrelated hook.'
    Assert-Installer ($settings.existing.PostToolUse[0].hooks.command -like '*existing-post.ps1*') `
        'Antigravity installer removed another hook definition.'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $testRoot '.open-desktop-pet\antigravity_cli_notify.ps1')) `
        'Antigravity installer did not copy the notification bridge.'

    & $installerPath | Out-Null
    $reinstalled = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reinstalledStopCommands = @($reinstalled.'open-desktop-pet'.Stop | ForEach-Object { $_.command })
    Assert-Installer ($reinstalledStopCommands.Count -eq 2) `
        'Reinstalling Antigravity hooks must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    $uninstalled = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Installer ($uninstalled.'open-desktop-pet'.Stop[0].command -like '*existing-stop.ps1*') `
        'Antigravity uninstall did not preserve the existing Stop hook.'
    Assert-Installer ($uninstalled.'open-desktop-pet'.PostInvocation[0].command -like '*existing-invocation.ps1*') `
        'Antigravity uninstall removed an unrelated hook.'

    Write-Output 'ANTIGRAVITY_CLI_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
