#requires -Version 7.0

param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$enginePath = Join-Path $repoRoot 'Robocopy-Progress.ps1'
$downloadsScript = Join-Path $repoRoot 'Sync-DownloadsToG.ps1'
$documentsScript = Join-Path $repoRoot 'Sync-DocumentsToG.ps1'
$downloadsInstaller = Join-Path $repoRoot 'Install-DownloadsHotBackupTask.ps1'
$documentsInstaller = Join-Path $repoRoot 'Install-DocumentsHotBackupTask.ps1'
$downloadsLauncher = Join-Path $repoRoot 'Sync-DownloadsToG-Hidden.vbs'
$documentsLauncher = Join-Path $repoRoot 'Sync-DocumentsToG-Hidden.vbs'
$downloadsBat = Join-Path $repoRoot 'Sync-DownloadsToG.bat'
$documentsBat = Join-Path $repoRoot 'Sync-DocumentsToG.bat'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Invoke-BackupChild {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

foreach ($path in @(
    $enginePath, $downloadsScript, $documentsScript,
    $downloadsInstaller, $documentsInstaller,
    $downloadsLauncher, $documentsLauncher,
    $downloadsBat, $documentsBat
)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "required backup entry exists: $path"
}

foreach ($path in @($enginePath, $downloadsScript, $documentsScript)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -match '(?m)^#requires -Version 7\.0\s*$') "$path explicitly requires PowerShell 7"
    [void][scriptblock]::Create($text)
}

foreach ($path in @($downloadsLauncher, $documentsLauncher)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -notmatch '(?i)exe\s*=\s*"powershell\.exe"') "$path does not silently fall back to incompatible Windows PowerShell"
    Assert-True ($text -match 'WScript\.Quit') "$path propagates a deterministic exit code"
}

foreach ($path in @($downloadsBat, $documentsBat)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -notmatch '(?i)powershell\.exe') "$path does not silently fall back to incompatible Windows PowerShell"
}

$downloadsDefinition = & $downloadsInstaller -DefinitionOnly
$documentsDefinition = & $documentsInstaller -DefinitionOnly
foreach ($item in @(
    [pscustomobject]@{ Name = 'Downloads'; Definition = $downloadsDefinition },
    [pscustomobject]@{ Name = 'Documents'; Definition = $documentsDefinition }
)) {
    $start = ([datetimeoffset]$item.Definition.Triggers[0].StartBoundary).ToLocalTime()
    Assert-True ($start.Hour -eq 21 -and $start.Minute -eq 35) "$($item.Name) hot backup defaults to 21:35"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hot-backup-core-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $source = Join-Path $tempRoot 'source'
    $destination = Join-Path $tempRoot 'destination'
    $quarantine = Join-Path $tempRoot 'quarantine'
    $control = Join-Path $tempRoot 'control'
    $logs = Join-Path $tempRoot 'logs'
    foreach ($path in @($source, $destination, $quarantine, $control, $logs)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    [IO.File]::WriteAllText((Join-Path $source 'current.txt'), "current`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $destination 'deleted-at-source.txt'), "stale`n", [Text.UTF8Encoding]::new($false))
    $receipt = Join-Path $control 'downloads.json'
    $common = @(
        '-Source', $source,
        '-Destination', $destination,
        '-QuarantineRoot', $quarantine,
        '-ReceiptPath', $receipt,
        '-LogDir', $logs,
        '-MinimumFreeBytes', '0',
        '-MutexName', "Local\HotBackupCore-$PID",
        '-Quiet',
        '-QuarantineFileThreshold', '0',
        '-QuarantineRatioThreshold', '0'
    )

    $first = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    Assert-True ($first.ExitCode -eq 0) "first incremental run succeeds: $($first.Output -join ' | ')"
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'current.txt') -PathType Leaf) 'new source file is copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'deleted-at-source.txt'))) 'source deletion leaves the hot destination'
    $quarantined = @(Get-ChildItem -LiteralPath $quarantine -Recurse -File -Filter 'deleted-at-source.txt')
    Assert-True ($quarantined.Count -eq 1) 'source deletion enters quarantine even above the legacy threshold in quiet mode'

    $second = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    Assert-True ($second.ExitCode -eq 0) "second incremental run succeeds: $($second.Output -join ' | ')"
    $secondReceipt = Get-Content -LiteralPath $receipt -Raw -Encoding utf8 | ConvertFrom-Json -Depth 10
    Assert-True ([int64]$secondReceipt.copy_files -eq 0) 'unchanged second run copies zero files'
    Assert-True ($secondReceipt.status -eq 'complete') 'unchanged second run is complete'

    $lockedPath = Join-Path $source 'locked.txt'
    [IO.File]::WriteAllText($lockedPath, "locked`n", [Text.UTF8Encoding]::new($false))
    $lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $lockedRun = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    } finally {
        $lock.Dispose()
    }
    Assert-True ($lockedRun.ExitCode -eq 0) "file-in-use does not abort the backup set: $($lockedRun.Output -join ' | ')"
    $lockedReceipt = Get-Content -LiteralPath $receipt -Raw -Encoding utf8 | ConvertFrom-Json -Depth 10
    Assert-True ($lockedReceipt.status -eq 'success_with_skips') 'file-in-use produces success_with_skips'
    Assert-True (@($lockedReceipt.failed_files | Where-Object category -eq 'file_in_use').Count -ge 1) 'file-in-use is categorized in the receipt'

    $receiptBlocker = Join-Path $control 'receipt-is-a-directory'
    New-Item -ItemType Directory -Path $receiptBlocker | Out-Null
    $badReceiptArgs = @($common)
    $receiptIndex = [array]::IndexOf($badReceiptArgs, '-ReceiptPath')
    $badReceiptArgs[$receiptIndex + 1] = $receiptBlocker
    $badReceipt = Invoke-BackupChild -Script $downloadsScript -Arguments $badReceiptArgs
    Assert-True ($badReceipt.ExitCode -ne 0) 'receipt write failure returns a nonzero task result'

    . $enginePath
    $accessDenied = ConvertFrom-RobocopyOutputLine -Line '2026/07/26 21:35:00 错误 5 (0x00000005) 正在复制文件 C:\fixture\denied.txt'
    Assert-True ($accessDenied.Category -eq 'access_denied') 'access-denied output is categorized'
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host 'OK hot-backup core tests passed.'
