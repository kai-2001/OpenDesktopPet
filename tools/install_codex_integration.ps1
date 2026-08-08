param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $env:USERPROFILE '.codex'
} else {
    $env:CODEX_HOME
}
$configPath = Join-Path $codexHome 'config.toml'
$installedNotifyScript = Join-Path $codexHome 'open_desktop_pet_notify.ps1'
$sourceNotifyScript = Join-Path $PSScriptRoot 'codex_notify.ps1'
$installMarker = Join-Path $codexHome 'open_desktop_pet_codex_installed.txt'
$escapedScriptPath = $installedNotifyScript.Replace('\', '\\')
$notifyBridgeFileName = [IO.Path]::GetFileName($installedNotifyScript)

function Get-NotifyAssignments([string]$text) {
    $assignments = @()
    $searchIndex = 0
    $pattern = '(?m)^[ \t]*notify[ \t]*='
    $notifyRegex = [regex]::new($pattern)
    while ($searchIndex -lt $text.Length) {
        $match = $notifyRegex.Match($text, $searchIndex)
        if (-not $match.Success) {
            break
        }
        $openIndex = $text.IndexOf('[', $match.Index + $match.Length)
        if ($openIndex -lt 0) {
            break
        }

        $depth = 0
        $inString = $false
        $escaped = $false
        $closeIndex = -1
        for ($index = $openIndex; $index -lt $text.Length; $index++) {
            $character = $text[$index]
            if ($inString) {
                if ($escaped) {
                    $escaped = $false
                } elseif ($character -eq '\') {
                    $escaped = $true
                } elseif ($character -eq '"') {
                    $inString = $false
                }
                continue
            }
            if ($character -eq '"') {
                $inString = $true
            } elseif ($character -eq '[') {
                $depth++
            } elseif ($character -eq ']') {
                $depth--
                if ($depth -eq 0) {
                    $closeIndex = $index + 1
                    break
                }
            }
        }
        if ($closeIndex -lt 0) {
            break
        }

        $blockEnd = $closeIndex
        while ($blockEnd -lt $text.Length -and $text[$blockEnd] -match '[ \t]') {
            $blockEnd++
        }
        if ($blockEnd + 1 -lt $text.Length -and
            $text.Substring($blockEnd, 2) -eq "`r`n") {
            $blockEnd += 2
        } elseif ($blockEnd -lt $text.Length -and $text[$blockEnd] -eq "`n") {
            $blockEnd++
        }
        $assignments += [pscustomobject]@{
            Start = $match.Index
            End = $blockEnd
            Text = $text.Substring($match.Index, $blockEnd - $match.Index)
        }
        $searchIndex = $blockEnd
    }
    return $assignments
}

function Remove-NotifyAssignments(
    [string]$text,
    [object[]]$assignments,
    [object]$keep
) {
    for ($index = $assignments.Count - 1; $index -ge 0; $index--) {
        $assignment = $assignments[$index]
        if ($null -ne $keep -and $assignment.Start -eq $keep.Start) {
            continue
        }
        $text = $text.Remove($assignment.Start, $assignment.End - $assignment.Start)
    }
    return $text
}

New-Item -ItemType Directory -Force -Path $codexHome | Out-Null

if ($Uninstall) {
    if (Test-Path -LiteralPath $configPath) {
        $configText = Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
        $assignments = @(Get-NotifyAssignments $configText)
        $updatedText = Remove-NotifyAssignments $configText $assignments $null
        Set-Content -LiteralPath $configPath -Value $updatedText -Encoding UTF8
    }
    if (Test-Path -LiteralPath $installedNotifyScript) {
        Remove-Item -LiteralPath $installedNotifyScript -Force
    }
    if (Test-Path -LiteralPath $installMarker) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    Write-Output "Removed Codex notification configuration: $configPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceNotifyScript)) {
    throw "Notification bridge not found: $sourceNotifyScript"
}

Copy-Item -LiteralPath $sourceNotifyScript -Destination $installedNotifyScript -Force
$notifyBlock = @(
    'notify = ['
    '  "powershell.exe",'
    '  "-NoProfile",'
    '  "-File",'
    "  `"$escapedScriptPath`""
    ']'
) -join [Environment]::NewLine

$configText = if (Test-Path -LiteralPath $configPath) {
    Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
} else {
    ''
}

$assignments = @(Get-NotifyAssignments $configText)
$existingNotify = $assignments |
    Where-Object { $_.Text -match [regex]::Escape($notifyBridgeFileName) } |
    Select-Object -First 1
if ($null -ne $existingNotify) {
    # Codex's Computer Use wrapper already calls the desktop-pet bridge through
    # --previous-notify. Keep that complete chain and remove duplicate entries.
    $keptNotifyBlock = $existingNotify.Text.Trim()
    $configText = Remove-NotifyAssignments $configText $assignments $null

    # Normalize the kept notify key back to the TOML root. This also repairs
    # older installations that placed notify after a table declaration.
    $firstTable = [regex]::Match($configText, '(?m)^[ \t]*\[')
    $lineBreak = [Environment]::NewLine
    if ($firstTable.Success) {
        $rootSettings = $configText.Substring(0, $firstTable.Index).TrimEnd()
        $tableSettings = $configText.Substring($firstTable.Index).Trim("`r", "`n")
        $configText = if ([string]::IsNullOrWhiteSpace($rootSettings)) {
            $keptNotifyBlock + $lineBreak + $lineBreak + $tableSettings
        } else {
            $rootSettings + $lineBreak + $lineBreak + $keptNotifyBlock + $lineBreak + $lineBreak + $tableSettings
        }
    } else {
        $configText = $configText.TrimEnd() + $lineBreak + $lineBreak + $keptNotifyBlock
    }
} else {
    $backupPath = "$configPath.open-desktop-pet-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($assignments.Count -gt 0) {
        Copy-Item -LiteralPath $configPath -Destination $backupPath
        Write-Output "Backed up the previous Codex configuration to: $backupPath"
        $configText = Remove-NotifyAssignments $configText $assignments $null
    }

    # Insert the desktop-pet notify at the TOML root, before the first table.
    $firstTable = [regex]::Match($configText, '(?m)^[ \t]*\[')
    $lineBreak = [Environment]::NewLine
    if ($firstTable.Success) {
        $rootSettings = $configText.Substring(0, $firstTable.Index).TrimEnd()
        $tableSettings = $configText.Substring($firstTable.Index).Trim("`r", "`n")
        $configText = if ([string]::IsNullOrWhiteSpace($rootSettings)) {
            $notifyBlock + $lineBreak + $lineBreak + $tableSettings
        } else {
            $rootSettings + $lineBreak + $lineBreak + $notifyBlock + $lineBreak + $lineBreak + $tableSettings
        }
    } else {
        $rootSettings = $configText.TrimEnd()
        $configText = if ([string]::IsNullOrWhiteSpace($rootSettings)) {
            $notifyBlock
        } else {
            $rootSettings + $lineBreak + $lineBreak + $notifyBlock
        }
    }
}

Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
Set-Content -LiteralPath $installMarker -Value '1' -Encoding ASCII
Write-Output "Codex notification installed: $configPath"
Write-Output "Notification bridge: $installedNotifyScript"
Write-Output 'Restart VS Code or Codex to apply the configuration.'
