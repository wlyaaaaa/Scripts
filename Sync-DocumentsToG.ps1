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
    [string[]]$ExcludeNamePatterns = @('~$*', '.~lock.*'),
    [string[]]$ExcludeDirPatterns = @('xwechat_files', '.tmp.driveupload', 'BaiduNetdiskTmp', 'CloudCache')
)

# Hot-backup the Windows Documents folder to G with a quarantine-cooling mirror
# (same engine and policy as Sync-DownloadsToG.ps1):
#   incremental copy is truly incremental; source deletions shrink the backup too,
#   but removed destination items are first moved into
#   G:\80_Backup\_quarantine\Documents-<stamp>\ and only permanently pruned after
#   -QuarantineRetentionDays days.
# Excluded by design: WeChat xwechat_files (covered by the dedicated WeChat backup
# chain) and cloud/upload staging caches (.tmp.driveupload, BaiduNetdiskTmp,
# CloudCache). Office owner/lock files (~$*, .~lock.*) are transient and skipped.
# File-in-use handling: bounded robocopy retries (/R:2 /W:5), then the locked file
# is skipped, categorized, listed in the receipt and retried next run.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$Source = 'E:\Documents'
$Destination = 'G:\80_Backup\Documents'
$QuarantineRoot = 'G:\80_Backup\_quarantine'
$ReceiptPath = 'G:\80_Backup\ControlPlane\documents-hot-last.json'
$LogDir = Join-Path $PSScriptRoot 'logs'
$MutexName = 'Global\CodexGHotBackupWriteLock'
$ProgressEnginePath = Join-Path $PSScriptRoot 'Robocopy-Progress.ps1'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "documents-to-g-$Stamp.log"

function Write-LogLine([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Assert-GHotWritable {
    $volume = Get-Volume -DriveLetter G -ErrorAction Stop
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
    foreach ($dir in @(Get-ChildItem -LiteralPath $QuarantineRoot -Directory -Filter 'Documents-*' -Force -ErrorAction SilentlyContinue)) {
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

$createdNew = $false
$mutex = [Threading.Mutex]::new($false, $MutexName, [ref]$createdNew)
$hasLock = $false
try {
    if (-not $ListOnly) {
        Remove-ExpiredQuarantine
        $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexWaitSeconds))
        if (-not $hasLock) { throw "Timed out waiting for $MutexName." }
        $null = New-Item -ItemType Directory -Path $Destination -Force
    }

    Write-LogLine "Documents hot backup: $Source -> $Destination (incremental + quarantine-cooling mirror)"
    $mirrorArgs = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/FFT', '/XJ', '/MT:4')
    foreach ($pat in $ExcludeNamePatterns) { $mirrorArgs += @('/XF', $pat) }
    foreach ($pat in $ExcludeDirPatterns) { $mirrorArgs += @('/XD', $pat) }

    $extras = Get-MirrorExtras -Source $Source -Destination $Destination -ExcludeNamePatterns $ExcludeNamePatterns -ExcludeDirPatterns $ExcludeDirPatterns
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
            schema = 'documents.hot-backup-plan.v1'
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
        $doQuarantine = $true
        if ($overThreshold -and -not $ForceQuarantine) {
            if ($Quiet) {
                $doQuarantine = $false
                $quarantineDeferred = $true
                Write-LogLine "WARN: quarantine规模超阈值 ($extraFileCount files > $QuarantineFileThreshold or ratio > $QuarantineRatioThreshold); deferred in silent run. Review and rerun manually with -ForceQuarantine."
            } else {
                $answer = Read-Host "隔离规模较大：$extraFileCount 个文件 / $extraDirCount 个目录将移入隔离区。确认执行? (y/N)"
                if ($answer -ne 'y' -and $answer -ne 'Y') {
                    $doQuarantine = $false
                    $quarantineDeferred = $true
                    Write-LogLine 'Quarantine declined by operator for this run; copy continues.'
                }
            }
        }

        if ($doQuarantine) {
            $quarantineDir = Join-Path $QuarantineRoot "Documents-$Stamp"
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
    }

    $copyArgs = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/FFT', '/XJ', '/R:2', '/W:5', '/MT:4', '/J')
    foreach ($pat in $ExcludeNamePatterns) { $copyArgs += @('/XF', $pat) }
    foreach ($pat in $ExcludeDirPatterns) { $copyArgs += @('/XD', $pat) }
    Write-LogLine "Robocopy run starting (log: $LogFile)"
    $run = Invoke-RobocopyWithProgress -Source $Source -Destination $Destination -RobocopyArgs $copyArgs `
        -Activity 'Documents 热备 → G' -TotalFiles $scan.CopyFiles -TotalBytes $scan.CopyBytes -Quiet:$Quiet
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
} catch {
    $syncError = $_
    $status = 'failed'
} finally {
    if ($hasLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

$receipt = [pscustomobject]@{
    schema = 'documents.hot-backup-receipt.v1'
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
    failed_files = if ($run) { @($run.FailedFiles | ForEach-Object { [pscustomobject]@{ code = $_.Code; category = $_.Category; path = $_.Path } }) } else { @() }
    sync_error = if ($syncError) { $syncError.Exception.Message } else { $null }
}
try {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $ReceiptPath) -Force
    [IO.File]::WriteAllText($ReceiptPath, ($receipt | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
} catch {
    Write-LogLine "WARN: failed to write receipt ${ReceiptPath}: $($_.Exception.Message)"
}
Write-LogLine "Status: $status"
if ($syncError) { throw $syncError }
exit $exitCode
