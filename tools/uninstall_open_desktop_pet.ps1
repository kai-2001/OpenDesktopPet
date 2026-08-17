[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Integrations', 'Complete')]
    [string]$Mode = 'Interactive',
    [switch]$SkipAutostart
)

$ErrorActionPreference = 'Stop'

$script:failures = New-Object System.Collections.Generic.List[string]
$integrationHomeFileNames = @(
	'codex_stop_notify.ps1',
    'vscode_copilot_notify.ps1',
    'opencode_notify.ps1',
    'claude_code_notify.ps1',
    'gemini_cli_notify.ps1',
    'antigravity_cli_notify.ps1',
    'open_desktop_pet_runtime.ps1',
    'open_desktop_pet_runtime.json',
    'open_desktop_pet_notify_port.txt',
    'open_desktop_pet_codex_enabled.txt',
    'open_desktop_pet_vscode_codex_enabled.txt',
    'open_desktop_pet_codex_app_enabled.txt',
    'open_desktop_pet_terminal_codex_enabled.txt',
    'open_desktop_pet_copilot_enabled.txt',
    'open_desktop_pet_opencode_enabled.txt',
    'open_desktop_pet_opencode_vscode_enabled.txt',
    'open_desktop_pet_opencode_app_enabled.txt',
    'open_desktop_pet_opencode_terminal_enabled.txt',
    'open_desktop_pet_opencode_app_executable_path.txt',
    'open_desktop_pet_claude_enabled.txt',
    'open_desktop_pet_claude_vscode_enabled.txt',
    'open_desktop_pet_claude_app_enabled.txt',
    'open_desktop_pet_claude_terminal_enabled.txt',
    'open_desktop_pet_claude_app_executable_path.txt',
    'open_desktop_pet_gemini_enabled.txt',
    'open_desktop_pet_agy_enabled.txt',
    'open_desktop_pet_codex_installed.txt',
    'open_desktop_pet_copilot_installed.txt',
    'open_desktop_pet_opencode_installed.txt',
    'open_desktop_pet_claude_code_installed.txt',
    'open_desktop_pet_gemini_cli_installed.txt',
    'open_desktop_pet_antigravity_cli_installed.txt'
)
$codexHomeFileNames = @(
	'open_desktop_pet_notify.ps1',
    'open_desktop_pet_previous_notify.json',
    'open_desktop_pet_notify_enabled.txt',
    'open_desktop_pet_codex_installed.txt'
)
$temporaryLogFileNames = @(
	'OpenDesktopPet-codex-stop-hook.log',
    'OpenDesktopPet-codex-notify.log',
    'OpenDesktopPet-vscode-hook.log',
    'OpenDesktopPet-opencode-notify.log',
    'OpenDesktopPet-claude-code-notify.log',
    'OpenDesktopPet-gemini-cli-notify.log',
    'OpenDesktopPet-antigravity-cli-notify.log'
)

function Get-UserProfilePath {
    $profilePath = [string]$env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::UserProfile
        )
    }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        throw 'Could not resolve the current Windows user profile directory.'
    }
    return [IO.Path]::GetFullPath($profilePath)
}

function Get-CodexHomePath([string]$userProfilePath) {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_HOME)) {
        return [IO.Path]::GetFullPath([string]$env:CODEX_HOME)
    }
    return Join-Path $userProfilePath '.codex'
}

function Get-OpenDesktopPetUserDataPath([string]$userProfilePath) {
    $appDataPath = [string]$env:APPDATA
    if ([string]::IsNullOrWhiteSpace($appDataPath)) {
        $appDataPath = Join-Path $userProfilePath 'AppData\Roaming'
    }
    return Join-Path $appDataPath 'Godot\app_userdata\Open Desktop Pet'
}

function Select-UninstallMode {
    while ($true) {
        Write-Host ''
        Write-Host 'OpenDesktopPet 解除安裝選項'
        Write-Host '1. 只移除 Agent 通知整合與開機啟動（保留角色包、存檔與設定）'
        Write-Host '2. 完整移除（另刪除角色包、存檔、設定與診斷記錄）'
        Write-Host '0. 取消'
        switch (Read-Host '請輸入選項') {
            '1' { return 'Integrations' }
            '2' { return 'Complete' }
            '0' { return '' }
            default { Write-Warning '請輸入 0、1 或 2。' }
        }
    }
}

function Invoke-IntegrationUninstallers {
    $installers = @(
        [pscustomobject]@{ Name = 'Codex'; FileName = 'install_codex_integration.ps1' },
        [pscustomobject]@{ Name = 'VS Code Copilot'; FileName = 'install_copilot_integration.ps1' },
        [pscustomobject]@{ Name = 'OpenCode'; FileName = 'install_opencode_integration.ps1' },
        [pscustomobject]@{ Name = 'Claude Code'; FileName = 'install_claude_code_integration.ps1' },
        [pscustomobject]@{ Name = 'Gemini CLI'; FileName = 'install_gemini_cli_integration.ps1' },
        [pscustomobject]@{ Name = 'Antigravity CLI'; FileName = 'install_antigravity_cli_integration.ps1' }
    )
    foreach ($installer in $installers) {
        $installerPath = Join-Path $PSScriptRoot $installer.FileName
        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            $script:failures.Add("Missing bundled uninstaller for $($installer.Name): $installerPath")
            continue
        }
        try {
            & $installerPath -Uninstall | Out-Null
            if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "exit code $LASTEXITCODE"
            }
            Write-Output "Removed $($installer.Name) notification integration."
        } catch {
            $script:failures.Add("Could not remove $($installer.Name) notification integration: $($_.Exception.Message)")
        }
    }
}

function Remove-ListedFiles([string]$directory, [string[]]$fileNames) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return
    }
    foreach ($fileName in $fileNames) {
        $path = Join-Path $directory $fileName
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Remove-DirectoryWhenEmpty([string]$directory) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return
    }
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $directory -Force
    }
}

function Remove-OpenDesktopPetRuntimeFiles(
    [string]$userProfilePath,
    [bool]$removeUnknownIntegrationFiles
) {
    $integrationHome = Join-Path $userProfilePath '.open-desktop-pet'
    if ($removeUnknownIntegrationFiles -and
        (Test-Path -LiteralPath $integrationHome -PathType Container)) {
        Remove-Item -LiteralPath $integrationHome -Recurse -Force
    } else {
        Remove-ListedFiles $integrationHome $integrationHomeFileNames
        Remove-DirectoryWhenEmpty $integrationHome
    }

    $codexHome = Get-CodexHomePath $userProfilePath
    Remove-ListedFiles $codexHome $codexHomeFileNames
}

function Remove-OpenDesktopPetAutostart {
    if ($SkipAutostart) {
        Write-Output 'Skipped Windows autostart removal.'
        return
    }
    $systemRoot = [string]$env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($systemRoot)) {
        $systemRoot = 'C:\Windows'
    }
    $registryTool = Join-Path $systemRoot 'System32\reg.exe'
    if (-not (Test-Path -LiteralPath $registryTool -PathType Leaf)) {
        $script:failures.Add("Windows registry tool was not found: $registryTool")
        return
    }
    & $registryTool delete 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v 'Open Desktop Pet' /f *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Output 'Removed Open Desktop Pet autostart entry.'
    } elseif ($LASTEXITCODE -eq 1) {
        Write-Output 'No Open Desktop Pet autostart entry was present.'
    } else {
        $script:failures.Add("Could not remove the Open Desktop Pet autostart entry (exit code $LASTEXITCODE).")
    }
}

function Remove-OpenDesktopPetUserData([string]$userProfilePath) {
    $userDataPath = Get-OpenDesktopPetUserDataPath $userProfilePath
    if (Test-Path -LiteralPath $userDataPath -PathType Container) {
        Remove-Item -LiteralPath $userDataPath -Recurse -Force
        Write-Output "Removed Open Desktop Pet settings, saves, and character packs: $userDataPath"
    }
}

function Remove-OpenDesktopPetDiagnosticLogs {
    $tempPath = [string]$env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempPath) -or
        -not (Test-Path -LiteralPath $tempPath -PathType Container)) {
        return
    }
    Remove-ListedFiles $tempPath $temporaryLogFileNames
}

$selectedMode = $Mode
if ($selectedMode -eq 'Interactive') {
    $selectedMode = Select-UninstallMode
}
if ([string]::IsNullOrWhiteSpace($selectedMode)) {
    Write-Output 'OpenDesktopPet uninstall cancelled.'
    exit 0
}

$userProfilePath = Get-UserProfilePath
Invoke-IntegrationUninstallers
Remove-OpenDesktopPetRuntimeFiles $userProfilePath ($selectedMode -eq 'Complete')
Remove-OpenDesktopPetAutostart

if ($selectedMode -eq 'Complete') {
    Remove-OpenDesktopPetUserData $userProfilePath
    Remove-OpenDesktopPetDiagnosticLogs
}

if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Warning $_ }
    throw 'OpenDesktopPet uninstall completed with errors. Review the warnings above.'
}

if ($selectedMode -eq 'Complete') {
    Write-Output 'OpenDesktopPet data and integrations were removed.'
} else {
    Write-Output 'OpenDesktopPet integrations were removed. Settings, saves, and character packs were kept.'
}
Write-Output 'You can now delete the portable OpenDesktopPet release folder manually.'
