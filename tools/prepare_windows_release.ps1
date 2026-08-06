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

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$toolsOutput = Join-Path $OutputDirectory 'tools'
New-Item -ItemType Directory -Force -Path $toolsOutput | Out-Null

Copy-Item -LiteralPath $ExecutablePath -Destination (Join-Path $OutputDirectory 'OpenDesktopPet.exe') -Force
foreach ($fileName in @(
    'Install-Codex-Integration.cmd',
    'install_codex_integration.ps1',
    'codex_notify.ps1',
    'README.md'
)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $toolsOutput $fileName) -Force
}

Write-Output "Release prepared: $OutputDirectory"
Write-Output 'Zip this folder and distribute it with the tools directory.'
