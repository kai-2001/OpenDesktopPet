# OpenDesktopPet runtime schema v1
#
# Notification hooks are separate PowerShell processes. They read this one
# runtime registration only while a desktop-pet instance owns it; permanent UI
# choices remain in Godot's ui_settings.cfg.

function Get-OpenDesktopPetRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IntegrationHome
    )

    $runtimePath = Join-Path $IntegrationHome 'open_desktop_pet_runtime.json'
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        return $null
    }
    try {
        $runtime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ($null -eq $runtime -or [int]$runtime.schema_version -ne 1 -or
            [string]::IsNullOrWhiteSpace([string]$runtime.instance_id) -or
            $null -eq $runtime.enabled_targets) {
            return $null
        }
        $port = [int]$runtime.port
        if ($port -lt 1024 -or $port -gt 65535) {
            return $null
        }
		$ownerProcess = Get-Process -Id ([int]$runtime.pid) -ErrorAction SilentlyContinue
		if ($null -eq $ownerProcess) {
			return $null
		}
        return $runtime
    } catch {
        return $null
    }
}

function Test-OpenDesktopPetRuntimeEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Runtime,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $property = $Runtime.enabled_targets.PSObject.Properties[$Target]
    return $null -ne $property -and [bool]$property.Value
}

function Get-OpenDesktopPetRuntimePort {
    param([Parameter(Mandatory = $true)][object]$Runtime)
    return [int]$Runtime.port
}

function Get-OpenDesktopPetRuntimeExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Runtime,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if ($null -eq $Runtime.executable_paths) {
        return ''
    }
    $property = $Runtime.executable_paths.PSObject.Properties[$Target]
    if ($null -eq $property) {
        return ''
    }
    return [string]$property.Value
}
