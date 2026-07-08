param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-Text {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "Assertion failed: $Name"
    }

    Write-Host "PASS: $Name"
}

$syncScript = Join-Path $RepoRoot 'Sync-DownloadsToH.ps1'
$backupScript = Join-Path $RepoRoot 'backup_apps.ps1'
$hiddenLauncher = Join-Path $RepoRoot 'Sync-DownloadsToH-Hidden.vbs'
$autoPushBatch = Join-Path $RepoRoot 'auto_push.bat'
$autoPushLauncher = Join-Path $RepoRoot 'auto_push.vbs'
$helperScript = Join-Path $RepoRoot 'HDriveSafety.ps1'
$readme = Join-Path $RepoRoot 'README.md'

$syncText = Get-Content -LiteralPath $syncScript -Raw
$backupText = Get-Content -LiteralPath $backupScript -Raw
$hiddenText = Get-Content -LiteralPath $hiddenLauncher -Raw
$autoPushBatchText = Get-Content -LiteralPath $autoPushBatch -Raw
$autoPushLauncherText = Get-Content -LiteralPath $autoPushLauncher -Raw
$helperText = Get-Content -LiteralPath $helperScript -Raw
$readmeText = Get-Content -LiteralPath $readme -Raw
$allText = @($syncText, $backupText, $hiddenText, $autoPushBatchText, $autoPushLauncherText, $helperText, $readmeText) -join "`n"

$syncTokens = $null
$syncErrors = $null
$backupTokens = $null
$backupErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($syncScript, [ref]$syncTokens, [ref]$syncErrors) | Out-Null
[System.Management.Automation.Language.Parser]::ParseFile($backupScript, [ref]$backupTokens, [ref]$backupErrors) | Out-Null
$helperTokens = $null
$helperErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($helperScript, [ref]$helperTokens, [ref]$helperErrors) | Out-Null
Assert-Text 'Sync-DownloadsToH.ps1 parses' ($syncErrors.Count -eq 0)
Assert-Text 'backup_apps.ps1 parses' ($backupErrors.Count -eq 0)
Assert-Text 'HDriveSafety.ps1 parses' ($helperErrors.Count -eq 0)

$backupBytes = [IO.File]::ReadAllBytes($backupScript)
Assert-Text 'backup_apps.ps1 keeps UTF-8 BOM for Windows PowerShell 5.1' (
    $backupBytes.Length -gt 3 -and
    $backupBytes[0] -eq 0xEF -and
    $backupBytes[1] -eq 0xBB -and
    $backupBytes[2] -eq 0xBF
)

Assert-Text 'VBS waits for PowerShell child process' ($hiddenText -match 'shell\.Run\s+cmd,\s*0,\s*True')
Assert-Text 'auto_push.bat works from its own directory' ($autoPushBatchText -match '%~dp0')
Assert-Text 'auto_push.vbs resolves its own directory' (
    $autoPushLauncherText -match 'WScript\.ScriptFullName' -and
    $autoPushLauncherText -match 'GetParentFolderName'
)
$oldRootPattern = [regex]::Escape(('E:' + [IO.Path]::DirectorySeparatorChar + 'Scripts'))
Assert-Text 'launchers avoid old Scripts root' ($allText -notmatch $oldRootPattern)

Assert-Text 'shared H drive mutex is present' ($helperText -match 'Global\\CodexHDriveUsbWriteLock')
Assert-Text 'dirty H volume is checked' ($helperText -match 'DirtyBitSet|Dirty|Full Repair Needed')
Assert-Text 'Get-Volume health gate is present' ($helperText -match 'HealthStatus|OperationalStatus')
Assert-Text 'free space guard is present' ($helperText -match 'FreeBytes|MinimumFreeBytes')
Assert-Text 'Sync script dot-sources safety helper' ($syncText -match 'HDriveSafety\.ps1')
Assert-Text 'backup_apps dot-sources safety helper' ($backupText -match 'HDriveSafety\.ps1')
Assert-Text 'backup_apps returns failure when H write is rejected' ($backupText -match 'Pause-Exit\s+3')
Assert-Text 'ListOnly does not create H destination directory' ($syncText -match 'if \(-not \$ListOnly\)\s*\{\s*New-Item')

Assert-Text 'ListOnly mode reports H drive status without dirty rejection' (
    $syncText -match '\$ListOnly' -and
    $syncText -match 'ListOnly.*dirty|dirty.*ListOnly|DirtyBitSet'
)

Assert-Text 'README documents H drive guardrails' (
    $readmeText -match 'dirty|Full Repair Needed|CodexHDriveUsbWriteLock|剩余空间|并发'
)

Assert-Text 'H drive helper avoids Repair-Volume on exFAT USB' ($helperText -notmatch 'Repair-Volume')
Assert-Text 'old backup path has no residual references' ($allText -notmatch 'My_Digital_Backup')
