$ErrorActionPreference = 'SilentlyContinue'

# OpenCode bridge for OpenDesktopPet. It distinguishes the host where the
# OpenCode session was started: VS Code, OpenCode Desktop, or a normal terminal.
# It is intentionally best-effort: a pet notification must never interrupt an
# OpenCode session or change its exit status.
$notifyHost = '127.0.0.1'
$notifyPort = 38571
$integrationHome = Join-Path $env:USERPROFILE '.open-desktop-pet'
$portFile = Join-Path $integrationHome 'open_desktop_pet_notify_port.txt'
$opencodeAppPathFile = Join-Path $integrationHome 'open_desktop_pet_opencode_app_executable_path.txt'
$logPath = Join-Path $env:TEMP 'OpenDesktopPet-opencode-notify.log'

function Write-NotifyLog([string]$message) {
    try {
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
            '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $message
        )
    } catch {
        # Diagnostics must never affect OpenCode.
    }
}

function Get-ProcessExecutablePath($process) {
    if (-not [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
        return [string]$process.ExecutablePath
    }
    $commandLine = [string]$process.CommandLine
    if ($commandLine -match '^"([^"]+)"') {
        return $matches[1]
    }
    return ''
}

function Normalize-PathText([string]$path) {
    return $path.Trim().Trim('"').Replace('/', '\')
}

function Test-OpenCodeDesktopPath([string]$path) {
    $normalizedPath = Normalize-PathText $path
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $false
    }

    $fileName = [System.IO.Path]::GetFileName($normalizedPath)
    # Auto-detection only accepts the unambiguous Desktop executable name.
    # A lowercase opencode.exe is accepted only when its directory explicitly
    # identifies the Desktop build; a generic CLI install must not win routing.
    if ($fileName -ceq 'OpenCode.exe' -or $fileName -ieq 'OpenCode Desktop.exe') {
        return $true
    }
    if ($fileName -ieq 'opencode.exe' -and
        $normalizedPath -match '(?i)[\\/](OpenCode[ _-]?Desktop|opencode-desktop)[\\/]') {
        return $true
    }
    return $false
}

function Test-OpenCodeDesktopProcess {
    $configuredPath = ''
    if (Test-Path -LiteralPath $opencodeAppPathFile) {
        # An enabled-file can exist while its path is still empty. Treat that
        # as "not configured" and continue host detection instead of aborting.
        $rawConfiguredPath = Get-Content -LiteralPath $opencodeAppPathFile -Raw
        if ($null -ne $rawConfiguredPath) {
            $configuredPath = $rawConfiguredPath.Trim().Trim('"')
        }
    }
    try {
        $parentId = $PID
        for ($index = 0; $index -lt 10 -and $parentId -gt 0; $index++) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId"
            if ($null -eq $process) {
                break
            }
            $candidatePath = Normalize-PathText (Get-ProcessExecutablePath $process)
            if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and
                (Test-OpenCodeDesktopPath $configuredPath) -and
                [string]::Equals(
                    $candidatePath,
                    (Normalize-PathText $configuredPath),
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                return $true
            }
            $candidateFileName = [System.IO.Path]::GetFileName($candidatePath)
            if ($candidateFileName -ceq 'OpenCode.exe' -or
                ($candidateFileName -ieq 'opencode.exe' -and
                    $candidatePath -match '(?i)[\\/](OpenCode[ _-]?Desktop|opencode-desktop)[\\/]')) {
                return $true
            }
            $commandLine = [string]$process.CommandLine
            if ($commandLine -match '(?i)OpenCode[ _-]Desktop|opencode-desktop') {
                return $true
            }
            $parentId = [int]$process.ParentProcessId
        }
    } catch {
        # Process inspection is only a routing hint.
    }
    return $false
}

function Test-VsCodeProcess {
    try {
        $parentId = $PID
        for ($index = 0; $index -lt 10 -and $parentId -gt 0; $index++) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId"
            if ($null -eq $process) {
                break
            }
            $candidatePath = Get-ProcessExecutablePath $process
            if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and
                [string]::Equals(
                    [System.IO.Path]::GetFileName($candidatePath.Trim().Trim('"')),
                    'Code.exe',
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                return $true
            }
            $parentId = [int]$process.ParentProcessId
        }
    } catch {
        # Process inspection is only a routing hint.
    }
    return $false
}

function Get-OpenCodeTarget {
    $isVsCodeEnvironment =
        ([string]$env:TERM_PROGRAM).ToLowerInvariant() -eq 'vscode' -or
        -not [string]::IsNullOrWhiteSpace([string]$env:VSCODE_PID) -or
        (Test-VsCodeProcess)
    if ($isVsCodeEnvironment) {
        return [ordered]@{
            target_app = 'vscode'
            target_executable = 'Code.exe'
            enabled_file = 'open_desktop_pet_opencode_vscode_enabled.txt'
        }
    }
    if (Test-OpenCodeDesktopProcess) {
        return [ordered]@{
            target_app = 'opencode_app'
            target_executable = 'OpenCode.exe'
            enabled_file = 'open_desktop_pet_opencode_app_enabled.txt'
        }
    }
    return [ordered]@{
        target_app = 'terminal'
        target_executable = 'WindowsTerminal.exe'
        enabled_file = 'open_desktop_pet_opencode_terminal_enabled.txt'
    }
}

function Test-OpenCodeEnabled([string]$flagName, [string]$targetApp) {
    $candidates = @(Join-Path $integrationHome $flagName)
    if ($targetApp -eq 'terminal') {
        # Compatibility with the first terminal-only OpenCode build.
        $candidates += Join-Path $integrationHome 'open_desktop_pet_opencode_enabled.txt'
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        try {
            return (Get-Content -LiteralPath $candidate -Raw).Trim() -eq '1'
        } catch {
            return $false
        }
    }
    return $false
}

try {
    if ($args.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$args[0])) {
        Write-NotifyLog 'ignored reason=missing-event'
        exit 0
    }
    $target = Get-OpenCodeTarget
    if (-not (Test-OpenCodeEnabled $target.enabled_file $target.target_app)) {
        Write-NotifyLog 'ignored reason=desktop-pet-disabled'
        exit 0
    }

    $event = ConvertFrom-Json -InputObject ([string]$args[0])
    if ($null -eq $event -or [string]$event.type -notin @('agent-turn-complete', 'agent-error')) {
        Write-NotifyLog 'ignored reason=unsupported-event'
        exit 0
    }

    if (Test-Path -LiteralPath $portFile) {
        $configuredPort = [int](Get-Content -LiteralPath $portFile -Raw).Trim()
        if ($configuredPort -ge 1024 -and $configuredPort -le 65535) {
            $notifyPort = $configuredPort
        }
    }

    $payload = [ordered]@{
        schema_version = 1
        type = [string]$event.type
        source = 'opencode'
        agent = 'opencode'
        target_app = $target.target_app
        target_platform = $target.target_app
        target_executable = $target.target_executable
        event_id = "opencode:{0}:{1}:{2}" -f $target.target_app, [string]$event.session_id, [string]$event.turn_id
        thread_id = ''
        session_id = [string]$event.session_id
        turn_id = [string]$event.turn_id
        cwd = [string]$event.cwd
    } | ConvertTo-Json -Compress

    $udp = [System.Net.Sockets.UdpClient]::new()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$udp.Send($bytes, $bytes.Length, $notifyHost, $notifyPort)
    $udp.Dispose()
    Write-NotifyLog (
        "sent type={0} target={1} port={2}" -f
        [string]$event.type, $target.target_app, $notifyPort
    )
} catch {
    Write-NotifyLog ("failed error-type={0} message={1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
}

exit 0
