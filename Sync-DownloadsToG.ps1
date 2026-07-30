[CmdletBinding()]
param(
    [switch]$ListOnly,
    [switch]$Quiet,
    [switch]$ForceQuarantine,
    [UInt64]$MinimumFreeBytes = [UInt64](2GB),
    [int]$MutexWaitSeconds = 1800,
    [int]$QuarantineRetentionDays = 30,
    [int]$QuarantineFileThreshold = 2000,
    [double]$QuarantineRatioThreshold = 0.3,
    [string[]]$ExcludeNamePatterns = @('*.crdownload', '*.part', '*.opdownload', '*.download'),
    [string]$Source = 'E:\Downloads',
    [string]$Destination = 'G:\80_Backup\03_下载与安装包',
    [string]$QuarantineRoot = 'G:\80_Backup\_quarantine',
    [string]$ReceiptPath = 'G:\80_Backup\ControlPlane\downloads-hot-last.json',
    [string]$LogDir = (Join-Path $PSScriptRoot 'logs'),
    [string]$MutexName = 'Global\CodexGHotBackupWriteLock',
    [string]$ProgressEnginePath = (Join-Path $PSScriptRoot 'Robocopy-Progress.ps1')
)

#requires -Version 7.0

# Hot-backup the Windows Downloads folder to G with a quarantine-cooling mirror:
#   incremental copy is truly incremental (only new/changed files cross the wire);
#   source deletions shrink the backup too, but removed destination items are first
#   moved into G:\80_Backup\_quarantine\Downloads-<stamp>\ (relative paths kept)
#   and only permanently pruned after -QuarantineRetentionDays days.
# File-in-use handling: bounded robocopy retries (/R:2 /W:5), then the locked file
# is skipped, categorized (file_in_use / access_denied), listed in the receipt and
# retried automatically on the next incremental run; benign skips never fail the task.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID
$LogFile = Join-Path $LogDir "downloads-to-g-$Stamp.log"

function Write-LogLine([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Assert-GHotWritable {
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destination))
    $driveLetter = $root.TrimEnd('\').TrimEnd(':')
    if ($driveLetter.Length -ne 1) { throw "Hot-backup destination must be on a local drive: $Destination" }
    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
    if ($volume.HealthStatus -notin @('Healthy','Unknown')) { throw "G health status is $($volume.HealthStatus)." }
    if (@($volume.OperationalStatus | Where-Object { $_ -notin @('OK','Unknown') }).Count -gt 0) {
        throw "G operational status is $($volume.OperationalStatus -join ',')."
    }
    if ([UInt64]$volume.SizeRemaining -lt $MinimumFreeBytes) {
        throw "G free space is below $MinimumFreeBytes bytes."
    }
}

function Remove-ExpiredQuarantine {
    if (-not (Test-Path -LiteralPath $QuarantineRoot -PathType Container)) { return }
    $cutoff = (Get-Date).AddDays(-$QuarantineRetentionDays)
    foreach ($dir in @(Get-ChildItem -LiteralPath $QuarantineRoot -Directory -Filter 'Downloads-*' -Force -ErrorAction SilentlyContinue)) {
        if ($dir.LastWriteTime -lt $cutoff) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                Write-LogLine "Quarantine retention pruned: $($dir.FullName)"
            } catch {
                Write-LogLine "WARN: failed to prune expired quarantine $($dir.FullName): $($_.Exception.Message)"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Source is missing: $Source" }
if (-not (Test-Path -LiteralPath $ProgressEnginePath -PathType Leaf)) { throw "Shared progress engine is missing: $ProgressEnginePath" }
. $ProgressEnginePath
Assert-GHotWritable

$status = 'complete'
$quarantineDeferred = $false
$quarantineDir = $null
$movedFiles = 0; $movedDirs = 0; $movedBytes = [Int64]0
$moveFailures = [Collections.Generic.List[object]]::new()
$run = $null
$syncError = $null
$scan = $null
$extras = $null
$exitCode = 0
$receiptError = $null

$createdNew = $false
$mutex = [Threading.Mutex]::new($false, $MutexName, [ref]$createdNew)
$hasLock = $false
try {
    if (-not $ListOnly) {
        $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexWaitSeconds))
        if (-not $hasLock) { throw "Timed out waiting for $MutexName." }
        Remove-ExpiredQuarantine
        $null = New-Item -ItemType Directory -Path $Destination -Force
    }

    Write-LogLine "Downloads hot backup: $Source -> $Destination (incremental + quarantine-cooling mirror)"
    $mirrorArgs = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/FFT', '/XJ', '/MT:4')
    foreach ($pat in $ExcludeNamePatterns) { $mirrorArgs += @('/XF', $pat) }

    $extras = Get-MirrorExtras -Source $Source -Destination $Destination -ExcludeNamePatterns $ExcludeNamePatterns
    if ($extras.SourceFileCount -eq 0) {
        throw "Source $Source appears to hold no files; refusing to mirror an empty source onto the backup."
    }
    $scan = Get-RobocopyScan -Source $Source -Destination $Destination -RobocopyArgs $mirrorArgs

    $extraFileCount = @($extras.ExtraFiles).Count
    $extraDirCount = @($extras.ExtraDirs).Count
    Write-LogLine ("Plan: copy {0} files ({1}); quarantine {2} files / {3} dirs; source files {4}, destination files {5}" -f
        $scan.CopyFiles, (Format-ByteSize -Bytes $scan.CopyBytes), $extraFileCount, $extraDirCount,
        $extras.SourceFileCount, $extras.DestinationFileCount)

    if ($ListOnly) {
        $plan = [pscustomobject]@{
            schema = 'downloads.hot-backup-plan.v1'
            source = $Source; destination = $Destination
            copy_files = $scan.CopyFiles; copy_bytes = $scan.CopyBytes
            quarantine_files = $extraFileCount; quarantine_dirs = $extraDirCount
            quarantine_sample = @(@($extras.ExtraDirs) + @($extras.ExtraFiles) | Select-Object -First 30)
            over_threshold = ($extraFileCount -gt $QuarantineFileThreshold -or
                ($extras.DestinationFileCount -gt 0 -and ($extraFileCount / $extras.DestinationFileCount) -gt $QuarantineRatioThreshold))
        }
        $plan | Format-List
        Write-LogLine 'ListOnly: no changes made.'
        exit 0
    }

    if ($extraFileCount -gt 0 -or $extraDirCount -gt 0) {
        $overThreshold = ($extraFileCount -gt $QuarantineFileThreshold) -or
            ($extras.DestinationFileCount -gt 0 -and
             (($extraFileCount / [math]::Max(1, $extras.DestinationFileCount)) -gt $QuarantineRatioThreshold))
        if ($overThreshold) {
            Write-LogLine "NOTICE: large source-deletion set ($extraFileCount files; ratio threshold $QuarantineRatioThreshold). Proceeding because quarantine is recoverable and source enumeration completed."
        }

        $quarantineDir = Join-Path $QuarantineRoot "Downloads-$Stamp"
        $sortedExtraDirs = @($extras.ExtraDirs | Sort-Object { $_.Length })
        $topExtraDirs = [Collections.Generic.List[string]]::new()
        foreach ($d in $sortedExtraDirs) {
            $isChild = $false
            foreach ($t in $topExtraDirs) { if ($d.StartsWith($t + '\', [StringComparison]::OrdinalIgnoreCase)) { $isChild = $true; break } }
            if (-not $isChild) { $topExtraDirs.Add($d) }
        }
        $rootExtraFiles = [Collections.Generic.List[string]]::new()
        foreach ($f in $extras.ExtraFiles) {
            $covered = $false
            foreach ($t in $topExtraDirs) { if ($f.StartsWith($t + '\', [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break } }
            if (-not $covered) { $rootExtraFiles.Add($f) }
        }

        foreach ($rel in @($topExtraDirs) + @($rootExtraFiles)) {
            $sourcePath = Join-Path $Destination $rel
            $targetPath = Join-Path $quarantineDir $rel
            try {
                $null = New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force
                $item = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
                $isFile = -not $item.PSIsContainer
                $size = if ($isFile) { [Int64]$item.Length } else { 0 }
                Move-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop
                if ($isFile) { $movedFiles++; $movedBytes += $size } else { $movedDirs++ }
            } catch {
                $moveFailures.Add([pscustomobject]@{ path = $sourcePath; error = $_.Exception.Message })
                Write-LogLine "WARN: quarantine move failed (kept in place, will retry next run): $sourcePath -- $($_.Exception.Message)"
            }
        }
        Write-LogLine "Quarantined $movedFiles files / $movedDirs dirs ($(Format-ByteSize -Bytes $movedBytes)) -> $quarantineDir"
    }

    $copyArgs = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/FFT', '/XJ', '/R:2', '/W:5', '/MT:4', '/J')
    foreach ($pat in $ExcludeNamePatterns) { $copyArgs += @('/XF', $pat) }
    Write-LogLine "Robocopy run starting (log: $LogFile)"
    $run = Invoke-RobocopyWithProgress -Source $Source -Destination $Destination -RobocopyArgs $copyArgs `
        -Activity 'Downloads 热备 → G' -TotalFiles $scan.CopyFiles -TotalBytes $scan.CopyBytes -Quiet:$Quiet
    $exitCode = $run.ExitCode
    Write-LogLine ("Robocopy exit code: {0}; copied {1} files ({2}) in {3}s, avg {4}/s" -f
        $exitCode, $run.FilesCopied, (Format-ByteSize -Bytes $run.BytesCopied),
        $run.DurationSeconds, (Format-ByteSize -Bytes $run.AvgBytesPerSec))

    if ($exitCode -ge 8) {
        $failed = @($run.FailedFiles)
        $allBenign = $failed.Count -gt 0 -and
            (@($failed | Where-Object { $_.Category -notin @('file_in_use', 'access_denied') }).Count -eq 0)
        if ($allBenign) {
            $status = 'success_with_skips'
            Write-LogLine "WARN: $($failed.Count) file(s) skipped because they were in use or access was denied; they will be retried next run."
            foreach ($f in $failed) { Write-LogLine "  skipped[$($f.Category)]: $($f.Path)" }
            $exitCode = 0
        } else {
            $status = 'failed'
        }
    } elseif (@($run.FailedFiles).Count -gt 0) {
        $status = 'success_with_skips'
    }
    if ($moveFailures.Count -gt 0 -and $status -eq 'complete') {
        $status = 'success_with_skips'
    }
    if ($status -ne 'failed') {
        # Robocopy 0..7 are success/informational states. Task Scheduler needs a
        # conventional process exit code, while the original code stays in receipt.
        $exitCode = 0
    }
} catch {
    $syncError = $_
    $status = 'failed'
} finally {
    if ($hasLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

$receipt = [pscustomobject]@{
    schema = 'downloads.hot-backup-receipt.v1'
    completed_utc = [DateTimeOffset]::UtcNow.ToString('o')
    status = $status
    source = $Source
    destination = $Destination
    copy_files = if ($run) { $run.FilesCopied } else { 0 }
    copy_bytes = if ($run) { $run.BytesCopied } else { 0 }
    duration_seconds = if ($run) { $run.DurationSeconds } else { 0 }
    avg_bytes_per_sec = if ($run) { $run.AvgBytesPerSec } else { 0 }
    robocopy_exit = if ($run) { $run.ExitCode } else { $null }
    quarantine_dir = $quarantineDir
    quarantined_files = $movedFiles
    quarantined_dirs = $movedDirs
    quarantined_bytes = $movedBytes
    quarantine_deferred = $quarantineDeferred
    quarantine_move_failures = $moveFailures.ToArray()
    failed_files = [object[]]@(
        if ($run) {
            @($run.FailedFiles) | ForEach-Object {
                [pscustomobject]@{
                    code = $_.Code
                    category = $_.Category
                    path = $_.Path
                }
            }
        }
    )
    sync_error = if ($syncError) { $syncError.Exception.Message } else { $null }
}
try {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ReceiptPath) -Force
    [IO.File]::WriteAllText($ReceiptPath, ($receipt | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
} catch {
    $receiptError = $_
    Write-LogLine "WARN: failed to write receipt ${ReceiptPath}: $($_.Exception.Message)"
}
Write-LogLine "Status: $status"
if ($receiptError) {
    if ($syncError) {
        throw "Backup failed ($($syncError.Exception.Message)) and receipt write failed ($($receiptError.Exception.Message))."
    }
    throw $receiptError
}
if ($syncError) { throw $syncError }
exit $exitCode
