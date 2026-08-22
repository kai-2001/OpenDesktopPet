param(
    [string]$ExecutablePath,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $projectRoot 'build\public\OpenDesktopPet.exe'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'build\release-codex'
}

$ExecutablePath = [IO.Path]::GetFullPath($ExecutablePath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
    throw "Executable not found: $ExecutablePath"
}

$extensionFileName = 'open_desktop_pet_windows.windows.template_release.x86_64.dll'
$extensionPath = Join-Path ([IO.Path]::GetDirectoryName($ExecutablePath)) $extensionFileName
if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
    $extensionPath = Join-Path $projectRoot "native\windows\bin\$extensionFileName"
}
if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
    throw "Windows GDExtension not found: $extensionFileName"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$toolsOutput = Join-Path $OutputDirectory 'tools'
New-Item -ItemType Directory -Force -Path $toolsOutput | Out-Null

Copy-Item -LiteralPath $ExecutablePath -Destination (Join-Path $OutputDirectory 'OpenDesktopPet.exe') -Force
Copy-Item -LiteralPath $extensionPath -Destination (Join-Path $OutputDirectory $extensionFileName) -Force
foreach ($fileName in @(
    'Uninstall-OpenDesktopPet.cmd',
    'uninstall_open_desktop_pet.ps1',
    'Install-Codex-Integration.cmd',
    'install_codex_integration.ps1',
    'codex_stop_notify.ps1',
	'codex_hook_review.ps1',
	'open_desktop_pet_runtime.ps1',
    'install_copilot_integration.ps1',
    'vscode_agent_notify.ps1',
    'install_opencode_integration.ps1',
    'opencode_notify.ps1',
    'opencode_notify_plugin.js',
    'Install-Claude-Code-Integration.cmd',
    'install_claude_code_integration.ps1',
    'claude_code_notify.ps1',
    'Install-Gemini-CLI-Integration.cmd',
    'install_gemini_cli_integration.ps1',
    'gemini_cli_notify.ps1',
    'Install-Antigravity-CLI-Integration.cmd',
    'install_antigravity_cli_integration.ps1',
    'antigravity_cli_notify.ps1',
    'Install-Pi-Integration.cmd',
    'install_pi_integration.ps1',
    'pi_agent_notify.ts',
    'README.md'
)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $toolsOutput $fileName) -Force
}

Write-Output "Release prepared: $OutputDirectory"
Write-Output 'Zip this folder and distribute it with the tools directory.'
