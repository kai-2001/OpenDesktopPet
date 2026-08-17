$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $projectRoot 'tools'
$uninstallerPath = Join-Path $toolsPath 'uninstall_open_desktop_pet.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet Uninstaller Test ' + [guid]::NewGuid().ToString('N')
)
$testProfile = Join-Path $testRoot 'Kai Chen'
$testAppData = Join-Path $testRoot 'Roaming App Data'
$testTemp = Join-Path $testRoot 'Temporary Logs'
$originalUserProfile = $env:USERPROFILE
$originalAppData = $env:APPDATA
$originalTemp = $env:TEMP

function Assert-Uninstaller([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Write-TestFile([string]$path, [string]$content = 'test') {
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
}

try {
    $env:USERPROFILE = $testProfile
    $env:APPDATA = $testAppData
    $env:TEMP = $testTemp

    foreach ($installerName in @(
        'install_codex_integration.ps1',
        'install_copilot_integration.ps1',
        'install_opencode_integration.ps1',
        'install_claude_code_integration.ps1',
        'install_gemini_cli_integration.ps1',
        'install_antigravity_cli_integration.ps1'
    )) {
        & (Join-Path $toolsPath $installerName) | Out-Null
        if (-not $?) {
            throw "Could not prepare $installerName for the uninstaller test."
        }
    }

    $integrationHome = Join-Path $testProfile '.open-desktop-pet'
    $userDataHome = Join-Path $testAppData 'Godot\app_userdata\Open Desktop Pet'
    Write-TestFile (Join-Path $integrationHome 'open_desktop_pet_notify_port.txt') '38571'
    Write-TestFile (Join-Path $integrationHome 'open_desktop_pet_agy_enabled.txt') '1'
	Write-TestFile (Join-Path $integrationHome 'open_desktop_pet_runtime.json') '{"schema_version":1}'
    Write-TestFile (Join-Path $integrationHome 'user-notes.txt') 'keep this in integration-only mode'
    Write-TestFile (Join-Path $userDataHome 'ui_settings.cfg') '[agent]'
    Write-TestFile (Join-Path $userDataHome 'profiles\default\save_v2.json') '{"hunger":75}'
    Write-TestFile (Join-Path $userDataHome 'character_packs\custom\pet.json') '{"id":"custom"}'
    foreach ($logName in @(
		'OpenDesktopPet-codex-stop-hook.log',
        'OpenDesktopPet-codex-notify.log',
        'OpenDesktopPet-vscode-hook.log',
        'OpenDesktopPet-opencode-notify.log',
        'OpenDesktopPet-claude-code-notify.log',
        'OpenDesktopPet-gemini-cli-notify.log',
        'OpenDesktopPet-antigravity-cli-notify.log'
    )) {
        Write-TestFile (Join-Path $testTemp $logName) 'diagnostic'
    }

    & $uninstallerPath -Mode Integrations -SkipAutostart | Out-Null
    if (-not $?) {
        throw 'Integration-only uninstall failed.'
    }

    Assert-Uninstaller (Test-Path -LiteralPath (Join-Path $integrationHome 'user-notes.txt')) `
        'Integration-only uninstall removed an unknown file from the integration directory.'
    Assert-Uninstaller (-not (Test-Path -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_notify_port.txt'))) `
        'Integration-only uninstall did not remove the notification port file.'
	Assert-Uninstaller (-not (Test-Path -LiteralPath (Join-Path $integrationHome 'open_desktop_pet_runtime.json'))) `
		'Integration-only uninstall did not remove the runtime registration.'
    Assert-Uninstaller (-not (Test-Path -LiteralPath (Join-Path $integrationHome 'antigravity_cli_notify.ps1'))) `
        'Integration-only uninstall did not remove the Antigravity bridge.'
    Assert-Uninstaller (Test-Path -LiteralPath $userDataHome) `
        'Integration-only uninstall removed OpenDesktopPet user data.'
    Assert-Uninstaller (Test-Path -LiteralPath (Join-Path $testTemp 'OpenDesktopPet-codex-notify.log')) `
        'Integration-only uninstall removed diagnostic logs.'

    $codexHooks = Get-Content -LiteralPath (Join-Path $testProfile '.codex\hooks.json') -Raw -Encoding UTF8
    $copilotConfig = Get-Content -LiteralPath (Join-Path $testProfile '.copilot\hooks\open-desktop-pet.json') -Raw -Encoding UTF8
    $claudeConfig = Get-Content -LiteralPath (Join-Path $testProfile '.claude\settings.json') -Raw -Encoding UTF8
    $geminiConfig = Get-Content -LiteralPath (Join-Path $testProfile '.gemini\settings.json') -Raw -Encoding UTF8
    $agyConfig = Get-Content -LiteralPath (Join-Path $testProfile '.gemini\config\hooks.json') -Raw -Encoding UTF8
    Assert-Uninstaller ($codexHooks -notmatch 'codex_stop_notify\.ps1') `
        'Integration-only uninstall did not remove the Codex Stop hook.'
    Assert-Uninstaller ($copilotConfig -notmatch 'vscode_copilot_notify\.ps1') `
        'Integration-only uninstall did not remove the Copilot hook.'
    Assert-Uninstaller (-not (Test-Path -LiteralPath (Join-Path $testProfile '.config\opencode\plugins\open-desktop-pet.js'))) `
        'Integration-only uninstall did not remove the OpenCode plugin.'
    Assert-Uninstaller ($claudeConfig -notmatch 'claude_code_notify\.ps1') `
        'Integration-only uninstall did not remove the Claude Code hook.'
    Assert-Uninstaller ($geminiConfig -notmatch 'gemini_cli_notify\.ps1') `
        'Integration-only uninstall did not remove the Gemini CLI hook.'
    Assert-Uninstaller ($agyConfig -notmatch 'EncodedCommand') `
        'Integration-only uninstall did not remove the Antigravity CLI hook.'

    & $uninstallerPath -Mode Complete -SkipAutostart | Out-Null
    if (-not $?) {
        throw 'Complete uninstall failed.'
    }

    Assert-Uninstaller (-not (Test-Path -LiteralPath $integrationHome)) `
        'Complete uninstall did not remove the OpenDesktopPet integration directory.'
    Assert-Uninstaller (-not (Test-Path -LiteralPath $userDataHome)) `
        'Complete uninstall did not remove OpenDesktopPet user data.'
    foreach ($logName in @(
		'OpenDesktopPet-codex-stop-hook.log',
        'OpenDesktopPet-codex-notify.log',
        'OpenDesktopPet-vscode-hook.log',
        'OpenDesktopPet-opencode-notify.log',
        'OpenDesktopPet-claude-code-notify.log',
        'OpenDesktopPet-gemini-cli-notify.log',
        'OpenDesktopPet-antigravity-cli-notify.log'
    )) {
        Assert-Uninstaller (-not (Test-Path -LiteralPath (Join-Path $testTemp $logName))) `
            "Complete uninstall did not remove $logName."
    }

    $launcherPath = Join-Path $toolsPath 'Uninstall-OpenDesktopPet.cmd'
    Assert-Uninstaller (Test-Path -LiteralPath $launcherPath) 'Uninstall launcher is missing.'
    Assert-Uninstaller ((Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8) -match 'uninstall_open_desktop_pet\.ps1') `
        'Uninstall launcher does not start the uninstaller script.'
    $releasePreparation = Get-Content -LiteralPath (Join-Path $toolsPath 'prepare_windows_release.ps1') -Raw -Encoding UTF8
    Assert-Uninstaller ($releasePreparation -match 'Uninstall-OpenDesktopPet\.cmd') `
        'Release preparation does not include the uninstall launcher.'
    Assert-Uninstaller ($releasePreparation -match 'uninstall_open_desktop_pet\.ps1') `
        'Release preparation does not include the uninstaller script.'
	Assert-Uninstaller ($releasePreparation -match 'open_desktop_pet_runtime\.ps1') `
		'Release preparation does not include the shared runtime helper.'

    Write-Output 'OPEN_DESKTOP_PET_UNINSTALLER_TEST_OK'
} finally {
    $env:USERPROFILE = $originalUserProfile
    $env:APPDATA = $originalAppData
    $env:TEMP = $originalTemp
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
