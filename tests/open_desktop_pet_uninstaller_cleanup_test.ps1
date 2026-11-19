$ErrorActionPreference = 'Stop'
# Installing every integration and then uninstalling completely must leave
# the profile as it was: nothing the pet created stays behind, and every
# hook, setting or plugin the user already had is kept.
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $projectRoot 'tools'
$uninstallerPath = Join-Path $toolsPath 'uninstall_open_desktop_pet.ps1'
$installers = @(
    'install_codex_integration.ps1',
    'install_copilot_integration.ps1',
    'install_opencode_integration.ps1',
    'install_claude_code_integration.ps1',
    'install_gemini_cli_integration.ps1',
    'install_antigravity_cli_integration.ps1',
    'install_pi_integration.ps1'
)
$saved = @{}
foreach ($name in 'USERPROFILE', 'CODEX_HOME', 'APPDATA', 'TEMP', 'TMP', 'PI_CODING_AGENT_DIR') {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}

function Assert-Cleanup([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

function Use-TestProfile([string]$root) {
    $profilePath = Join-Path $root 'profile'
    New-Item -ItemType Directory -Force -Path $profilePath, (Join-Path $root 'appdata'), (Join-Path $root 'temp') | Out-Null
    $env:USERPROFILE = $profilePath
    $env:APPDATA = Join-Path $root 'appdata'
    $env:TEMP = Join-Path $root 'temp'
    $env:TMP = $env:TEMP
    $env:CODEX_HOME = Join-Path $profilePath '.codex'
    $env:PI_CODING_AGENT_DIR = Join-Path $profilePath '.pi\agent'
    return $profilePath
}

function Write-ProfileFile([string]$profilePath, [string]$relativePath, [string]$text) {
    $path = Join-Path $profilePath $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text)
}

function Get-Tree([string]$root) {
    return @(Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($root.Length)
    } | Sort-Object)
}

## Rewriting a JSON file may reorder its keys; the content must still match.
function Get-SortedJsonValue($value) {
    if ($value -is [System.Management.Automation.PSCustomObject]) {
        $sorted = [ordered]@{}
        foreach ($property in @($value.PSObject.Properties | Sort-Object Name)) {
            $sorted[$property.Name] = Get-SortedJsonValue $property.Value
        }
        return [pscustomobject]$sorted
    }
    if ($value -is [System.Array]) {
        return ,@($value | ForEach-Object { Get-SortedJsonValue $_ })
    }
    return $value
}

function ConvertTo-Comparable([string]$text) {
    try {
        return (Get-SortedJsonValue ($text | ConvertFrom-Json)) | ConvertTo-Json -Depth 20 -Compress
    } catch {
        return $text.Trim()
    }
}

function Install-AllIntegrations {
    foreach ($installer in $installers) {
        & (Join-Path $toolsPath $installer) | Out-Null
    }
}

$testRoots = @()
try {
    # 1. Agents installed but never configured: everything the pet adds goes.
    #    The data folder sits deep enough that Godot's shader cache passes the
    #    260-character limit, as it does for long Windows user names.
    $freshRoot = Join-Path $env:TEMP ('OpenDesktopPet Cleanup Test ' + [guid]::NewGuid().ToString('N'))
    $testRoots += $freshRoot
    $profilePath = Use-TestProfile $freshRoot
    foreach ($directory in '.codex', '.copilot', '.claude', '.gemini\config', '.config\opencode', '.pi\agent') {
        New-Item -ItemType Directory -Force -Path (Join-Path $profilePath $directory) | Out-Null
    }
    $before = Get-Tree $freshRoot
    Install-AllIntegrations
    $userData = Join-Path $env:APPDATA 'Godot\app_userdata\Open Desktop Pet'
    $shaderFile = Join-Path $userData (
        'shader_cache\CanvasOcclusionShaderGLES3\' + ('a' * 64) + '\' + ('b' * 40) + '.cache'
    )
    Assert-Cleanup ($shaderFile.Length -gt 260) 'The long-path fixture is not past the Windows limit.'
    [IO.Directory]::CreateDirectory('\\?\' + (Split-Path -Parent $shaderFile)) | Out-Null
    [IO.File]::WriteAllText('\\?\' + $shaderFile, 'cache')
    [IO.File]::WriteAllText((Join-Path $userData 'ui_settings.cfg'), '[agent]')
    [IO.File]::WriteAllText((Join-Path $env:TEMP 'OpenDesktopPet-codex-stop-hook.log'), 'log')

    & $uninstallerPath -Mode Complete -SkipAutostart | Out-Null
    if (-not $?) {
        throw 'Complete uninstall failed.'
    }
    $leftovers = @(Compare-Object $before (Get-Tree $freshRoot) |
        Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
    Assert-Cleanup ($leftovers.Count -eq 0) (
        "Complete uninstall left these behind:`n" + ($leftovers -join "`n")
    )

    # 2. Agents the user already configured: only the pet's parts go.
    $ownRoot = Join-Path $env:TEMP ('odp' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $testRoots += $ownRoot
    $profilePath = Use-TestProfile $ownRoot
    $ownFiles = [ordered]@{
        '.codex\hooks.json' = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-stop.cmd"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"my-start.cmd"}]}]}}'
        '.codex\config.toml' = "model = `"gpt-5`"`nnotify = [`"my-notify.exe`"]`n`n[features]`ncodex_hooks = true`n"
        '.claude\settings.json' = '{"theme":"dark","permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-claude-stop.cmd"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-guard.cmd"}]}]}}'
        '.gemini\settings.json' = '{"theme":"GitHub","hooks":{"AfterAgent":[{"hooks":[{"type":"command","command":"my-gemini.cmd"}]}]}}'
        '.gemini\config\hooks.json' = '{"my-hook":{"event":"stop","command":"my-agy.cmd"}}'
        '.copilot\hooks\my-hooks.json' = '{"version":1,"hooks":{"Stop":[{"type":"command","windows":"my-copilot.cmd"}]}}'
        '.config\opencode\plugins\my-plugin.js' = 'export const MyPlugin = async () => ({})'
        '.pi\agent\extensions\my-extension.ts' = 'export default function () {}'
    }
    foreach ($entry in $ownFiles.GetEnumerator()) {
        Write-ProfileFile $profilePath $entry.Key $entry.Value
    }
    $before = Get-Tree $ownRoot
    Install-AllIntegrations
    $claudeInstalled = Get-Content -LiteralPath (Join-Path $profilePath '.claude\settings.json') -Raw
    Assert-Cleanup ($claudeInstalled -match 'claude_code_notify\.ps1') 'The Claude Code hook was not installed.'
    & $uninstallerPath -Mode Integrations -SkipAutostart | Out-Null
    if (-not $?) {
        throw 'Integration-only uninstall failed.'
    }
    foreach ($entry in $ownFiles.GetEnumerator()) {
        $path = Join-Path $profilePath $entry.Key
        Assert-Cleanup (Test-Path -LiteralPath $path -PathType Leaf) "The user's $($entry.Key) was removed."
        $after = [IO.File]::ReadAllText($path)
        Assert-Cleanup ((ConvertTo-Comparable $after) -eq (ConvertTo-Comparable $entry.Value)) (
            "The user's $($entry.Key) changed:`n  before: $($entry.Value)`n  after:  $after"
        )
    }
    $leftovers = @(Compare-Object $before (Get-Tree $ownRoot) |
        Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject |
        Where-Object { $_ -notlike '\profile\.open-desktop-pet*' })
    Assert-Cleanup ($leftovers.Count -eq 0) (
        "Integration-only uninstall left these behind:`n" + ($leftovers -join "`n")
    )
} finally {
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name])
    }
    foreach ($root in $testRoots) {
        if (Test-Path -LiteralPath $root) {
            [IO.Directory]::Delete('\\?\' + [IO.Path]::GetFullPath($root), $true)
        }
    }
}

Write-Output 'OPEN_DESKTOP_PET_UNINSTALLER_CLEANUP_TEST_OK'
