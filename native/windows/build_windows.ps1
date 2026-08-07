param(
	[ValidateSet('all', 'debug', 'release')]
	[string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dependencyRoot = Join-Path $projectRoot 'build\native-deps'
$godotCppRoot = Join-Path $dependencyRoot 'godot-cpp'
$godotCppCommit = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'
$llvmMingwVersion = '20260616'
$llvmMingwArchiveName = "llvm-mingw-$llvmMingwVersion-ucrt-x86_64.zip"
$llvmMingwArchive = Join-Path $dependencyRoot $llvmMingwArchiveName
$llvmMingwRoot = Join-Path $dependencyRoot "llvm-mingw-$llvmMingwVersion-ucrt-x86_64"
$llvmMingwUrl = "https://github.com/mstorsjo/llvm-mingw/releases/download/$llvmMingwVersion/$llvmMingwArchiveName"
$llvmMingwSha256 = 'b9b68a4d276e16fa25802aaba458e4638f64b3884c290aaccdc2d87083b6ca35'

New-Item -ItemType Directory -Force -Path $dependencyRoot | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $godotCppRoot '.git'))) {
	git clone --branch 4.5 --single-branch https://github.com/godotengine/godot-cpp.git $godotCppRoot
	if ($LASTEXITCODE -ne 0) {
		throw 'Failed to download godot-cpp.'
	}
}

$godotCppChanges = git -C $godotCppRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $godotCppChanges) {
	throw 'build/native-deps/godot-cpp has local changes; build stopped to preserve them.'
}
$currentGodotCppCommit = (git -C $godotCppRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
	throw 'Failed to inspect the godot-cpp revision.'
}
if ($currentGodotCppCommit -ne $godotCppCommit) {
	git -C $godotCppRoot cat-file -e "$godotCppCommit^{commit}" 2>$null
	if ($LASTEXITCODE -ne 0) {
		git -C $godotCppRoot fetch origin $godotCppCommit --depth 1
		if ($LASTEXITCODE -ne 0) {
			throw 'Failed to fetch the pinned godot-cpp revision.'
		}
	}
	git -C $godotCppRoot checkout --detach $godotCppCommit
	if ($LASTEXITCODE -ne 0) {
		throw 'Failed to check out the pinned godot-cpp revision.'
	}
}

if (-not (Test-Path -LiteralPath (Join-Path $llvmMingwRoot 'bin\x86_64-w64-mingw32-clang++.exe'))) {
	if (-not (Test-Path -LiteralPath $llvmMingwArchive)) {
		Write-Output "Downloading LLVM-MinGW $llvmMingwVersion..."
		Invoke-WebRequest -Uri $llvmMingwUrl -OutFile $llvmMingwArchive
	}
	$actualHash = (Get-FileHash -LiteralPath $llvmMingwArchive -Algorithm SHA256).Hash.ToLowerInvariant()
	if ($actualHash -ne $llvmMingwSha256) {
		throw "LLVM-MinGW archive checksum mismatch: $actualHash"
	}
	Expand-Archive -LiteralPath $llvmMingwArchive -DestinationPath $dependencyRoot -Force
}

$sconsTargets = switch ($Target) {
	'debug' { @('template_debug') }
	'release' { @('template_release') }
	default { @('template_debug', 'template_release') }
}

Push-Location $PSScriptRoot
try {
	foreach ($sconsTarget in $sconsTargets) {
		Write-Output "Building $sconsTarget..."
		python -m SCons `
			platform=windows `
			target=$sconsTarget `
			arch=x86_64 `
			use_mingw=yes `
			use_llvm=yes `
			mingw_prefix=$llvmMingwRoot `
			godot_cpp_dir=$godotCppRoot `
			-j ([Environment]::ProcessorCount)
		if ($LASTEXITCODE -ne 0) {
			throw "$sconsTarget build failed."
		}
	}
} finally {
	Pop-Location
}

Write-Output 'WINDOWS_GDEXTENSION_BUILD_OK'
