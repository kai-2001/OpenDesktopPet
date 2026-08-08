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
$previousNotifyPath = Join-Path $codexHome 'open_desktop_pet_previous_notify.json'
$sourceNotifyScript = Join-Path $PSScriptRoot 'codex_notify.ps1'
$installMarker = Join-Path $codexHome 'open_desktop_pet_codex_installed.txt'
$escapedScriptPath = $installedNotifyScript.Replace('\', '\\')
$doubleEscapedScriptPath = $escapedScriptPath.Replace('\\', '\\\\')
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

function ConvertFrom-TomlStringArray([string]$text) {
    $matches = [regex]::Matches($text, '"((?:\\.|[^"\\])*)"')
    $values = @()
    foreach ($match in $matches) {
        $value = $match.Groups[1].Value
        $value = $value.Replace('\\', '\')
        $value = $value.Replace('\"', '"')
        $value = $value.Replace('\n', "`n")
        $value = $value.Replace('\r', "`r")
        $value = $value.Replace('\t', "`t")
        $values += $value
    }
    return $values
}

function ConvertTo-TomlBasicString([string]$value) {
    return $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
}

function New-NotifyBlock([object[]]$command) {
    $lines = @('notify = [')
    for ($index = 0; $index -lt $command.Count; $index++) {
        $comma = if ($index -lt $command.Count - 1) { ',' } else { '' }
        $lines += ('  "{0}"{1}' -f (ConvertTo-TomlBasicString ([string]$command[$index])), $comma)
    }
    $lines += ']'
    return $lines -join [Environment]::NewLine
}

function Insert-RootNotifyBlock([string]$text, [string]$notifyBlock) {
    $firstTable = [regex]::Match($text, '(?m)^[ \t]*\[')
    $lineBreak = [Environment]::NewLine
    if ($firstTable.Success) {
        $rootSettings = $text.Substring(0, $firstTable.Index).TrimEnd()
        $tableSettings = $text.Substring($firstTable.Index).Trim("`r", "`n")
        if ([string]::IsNullOrWhiteSpace($rootSettings)) {
            return $notifyBlock + $lineBreak + $lineBreak + $tableSettings
        }
        return $rootSettings + $lineBreak + $lineBreak + $notifyBlock + $lineBreak + $lineBreak + $tableSettings
    }
    $rootSettings = $text.TrimEnd()
    if ([string]::IsNullOrWhiteSpace($rootSettings)) {
        return $notifyBlock
    }
    return $rootSettings + $lineBreak + $lineBreak + $notifyBlock
}

function Save-PreviousNotifyCommand([string]$notifyText) {
    $command = @(ConvertFrom-TomlStringArray $notifyText)
    if ($command.Count -eq 0) {
        throw 'Existing Codex notify configuration could not be parsed.'
    }
    [pscustomobject]@{ command = $command } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $previousNotifyPath -Encoding UTF8
}

function Test-IsDesktopNotifyAssignment($assignment) {
    return $assignment.Text -match [regex]::Escape($escapedScriptPath) -or
        $assignment.Text -match [regex]::Escape($doubleEscapedScriptPath) -or
        $assignment.Text -match [regex]::Escape($installedNotifyScript)
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
        $desktopNotify = $assignments |
            Where-Object { Test-IsDesktopNotifyAssignment $_ } |
            Select-Object -First 1
        if ($null -ne $desktopNotify) {
            $restoredCommand = @()
            if (Test-Path -LiteralPath $previousNotifyPath) {
                try {
                    $restoredDocument = Get-Content -LiteralPath $previousNotifyPath -Raw -Encoding UTF8 |
                        ConvertFrom-Json
                    $restoredCommand = @($restoredDocument.command)
                } catch {
                    $restoredCommand = @()
                }
            }
            if ($restoredCommand.Count -gt 0) {
                $updatedText = Remove-NotifyAssignments $configText $assignments $null
                $updatedText = Insert-RootNotifyBlock $updatedText (New-NotifyBlock $restoredCommand)
                Set-Content -LiteralPath $configPath -Value $updatedText -Encoding UTF8
            } elseif ($desktopNotify.Text -notmatch '(?i)--previous-notify') {
                $updatedText = Remove-NotifyAssignments $configText $assignments $null
                Set-Content -LiteralPath $configPath -Value $updatedText -Encoding UTF8
            }
            # A pre-existing Computer Use wrapper may already contain its own
            # --previous-notify chain. Leave it intact when no sidecar exists.
        }
    }
    if (Test-Path -LiteralPath $installedNotifyScript) {
        Remove-Item -LiteralPath $installedNotifyScript -Force
    }
    if (Test-Path -LiteralPath $installMarker) {
        Remove-Item -LiteralPath $installMarker -Force
    }
    if (Test-Path -LiteralPath $previousNotifyPath) {
        Remove-Item -LiteralPath $previousNotifyPath -Force
    }
    Write-Output "Removed Codex notification configuration: $configPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceNotifyScript)) {
    throw "Notification bridge not found: $sourceNotifyScript"
}

Copy-Item -LiteralPath $sourceNotifyScript -Destination $installedNotifyScript -Force
$notifyBlock = New-NotifyBlock @(
    'powershell.exe',
    '-NoProfile',
    '-File',
    $installedNotifyScript
)

$configText = if (Test-Path -LiteralPath $configPath) {
    Get-Content -LiteralPath $configPath -Encoding UTF8 -Raw
} else {
    ''
}

$assignments = @(Get-NotifyAssignments $configText)
$existingNotify = $assignments |
    Where-Object { Test-IsDesktopNotifyAssignment $_ } |
    Select-Object -First 1
if ($null -ne $existingNotify) {
    # Codex's Computer Use wrapper already calls the desktop-pet bridge through
    # --previous-notify. Keep that complete chain and remove duplicate entries.
    $keptNotifyBlock = $existingNotify.Text.Trim()
    $configText = Remove-NotifyAssignments $configText $assignments $null
	$configText = Insert-RootNotifyBlock $configText $keptNotifyBlock
} else {
    $backupPath = "$configPath.open-desktop-pet-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($assignments.Count -gt 0) {
        Copy-Item -LiteralPath $configPath -Destination $backupPath
        Write-Output "Backed up the previous Codex configuration to: $backupPath"
		Save-PreviousNotifyCommand $assignments[0].Text
        $configText = Remove-NotifyAssignments $configText $assignments $null
    }
	$configText = Insert-RootNotifyBlock $configText $notifyBlock
}

Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
Set-Content -LiteralPath $installMarker -Value '1' -Encoding ASCII
Write-Output "Codex notification installed: $configPath"
Write-Output "Notification bridge: $installedNotifyScript"
Write-Output 'Restart VS Code or Codex to apply the configuration.'
