param(
    [switch]$ListOnly,
    [string]$RefreshList,
    [UInt64]$MinimumFreeBytes = [UInt64](2GB),
    [int]$MutexWaitSeconds = 1800
)

# Sync the Windows Downloads folder to the USB drive without deleting old USB files.

$ErrorActionPreference = 'Stop'

$Source = 'E:\Downloads'
$TargetDrive = 'H:\'
$DownloadFolderName = -join @(
    [char] 0x4E0B,
    [char] 0x8F7D,
    [char] 0x4E0E,
    [char] 0x5B89,
    [char] 0x88C5,
    [char] 0x5305
)
$Destination = Join-Path $TargetDrive "03_$DownloadFolderName"
$LogDir = Join-Path $PSScriptRoot 'logs'
if ([string]::IsNullOrWhiteSpace($RefreshList)) {
    $RefreshList = Join-Path $PSScriptRoot 'state\h-downloads-known-bad-20260707.csv'
}

. (Join-Path $PSScriptRoot 'HDriveSafety.ps1')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "downloads-to-h-$Stamp.log"

function Write-LogLine {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Write-HDriveStatusLog {
    param(
        [pscustomobject]$Status,
        [string]$Label
    )

    Write-LogLine $Label
    foreach ($line in (Format-CodexHDriveStatus -Status $Status)) {
        Write-LogLine "  $line"
    }
}

function Invoke-DownloadsSync {
    if (-not $ListOnly) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }

    $RobocopyArgs = @(
        $Source,
        $Destination,
        '/E',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/R:0',
        '/W:0',
        '/XJ',
        '/FFT',
        '/NP',
        '/MT:1',
        '/J',
        "/LOG+:$LogFile"
    )

    if ($ListOnly) {
        $RobocopyArgs += '/L'
    }

    Write-LogLine "Robocopy args: $($RobocopyArgs -join ' ')"
    $null = & robocopy @RobocopyArgs
    $code = $LASTEXITCODE

    Write-LogLine "Robocopy exit code: $code"

    if ($code -ge 8) {
        Write-LogLine "Sync completed with errors."
        return $code
    }

    if ($RefreshList -and (Test-Path -LiteralPath $RefreshList)) {
        $refreshRows = Import-Csv -LiteralPath $RefreshList
        Write-LogLine "Refresh list entries: $($refreshRows.Count)"

        if ($ListOnly) {
            foreach ($row in $refreshRows) {
                $sourceFile = Join-Path $Source $row.Rel
                $destFile = Join-Path $Destination $row.Rel
                Write-LogLine "Would refresh: $sourceFile -> $destFile"
            }
        } else {
            $refreshErrors = 0
            foreach ($row in $refreshRows) {
                $sourceFile = Join-Path $Source $row.Rel
                $destFile = Join-Path $Destination $row.Rel

                try {
                    if (-not (Test-Path -LiteralPath $sourceFile)) {
                        Write-LogLine "Refresh source missing: $sourceFile"
                        $refreshErrors++
                        continue
                    }

                    $destDir = Split-Path -Parent $destFile
                    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    Copy-Item -LiteralPath $sourceFile -Destination $destFile -Force

                    $srcItem = Get-Item -LiteralPath $sourceFile -Force
                    $dstItem = Get-Item -LiteralPath $destFile -Force
                    $dstItem.LastWriteTime = $srcItem.LastWriteTime
                    Write-LogLine "Refreshed: $($row.Rel)"
                } catch {
                    Write-LogLine "Refresh failed: $($row.Rel) :: $($_.Exception.Message)"
                    $refreshErrors++
                }
            }

            if ($refreshErrors -gt 0) {
                Write-LogLine "Refresh completed with $refreshErrors error(s)."
                return 8
            }

            $donePath = "$RefreshList.done-$Stamp"
            Move-Item -LiteralPath $RefreshList -Destination $donePath -Force
            Write-LogLine "Refresh list completed and moved to: $donePath"
        }
    } else {
        Write-LogLine "No refresh list found."
    }

    Write-LogLine "Sync completed successfully."
    return 0
}

Write-LogLine "Downloads sync starting."
Write-LogLine "Mode: $(if ($ListOnly) { 'ListOnly' } else { 'Copy' })"
Write-LogLine "Source: $Source"
Write-LogLine "Destination: $Destination"
Write-LogLine "Refresh list: $RefreshList"
Write-LogLine "Minimum free bytes: $MinimumFreeBytes"
Write-LogLine "Mutex: $script:CodexHDriveMutexName"

$initialStatus = Get-CodexHDriveStatus -DriveLetter 'H' -MinimumFreeBytes $MinimumFreeBytes
Write-HDriveStatusLog -Status $initialStatus -Label 'Initial H drive status:'

if (-not (Test-Path -LiteralPath $Source)) {
    Write-LogLine "Source is missing. Nothing copied."
    exit 2
}

if (-not $initialStatus.IsMounted) {
    Write-LogLine "H: is not mounted. Skipping."
    exit 0
}

if ($ListOnly) {
    if ($initialStatus.DirtyBitSet -eq $true) {
        Write-LogLine "ListOnly: H: dirty bit is set; continuing because no H: write is requested."
    }

    if ($initialStatus.FullRepairNeeded) {
        Write-LogLine "ListOnly: H: reports Full Repair Needed; continuing because no H: write is requested."
    }

    if ($null -eq $initialStatus.DirtyBitSet -or $initialStatus.RepairCheckStatus -in @('Unavailable', 'Error')) {
        Write-LogLine "ListOnly: H: health status is partially unknown; continuing because no H: write is requested."
    }

    $exitCode = Invoke-DownloadsSync
    exit $exitCode
}

try {
    Write-LogLine "Waiting for H drive mutex: $script:CodexHDriveMutexName"
    $exitCode = Invoke-CodexHDriveWriteLock -TimeoutSeconds $MutexWaitSeconds -ScriptBlock {
        Write-LogLine "Acquired H drive mutex: $script:CodexHDriveMutexName"
        $lockedStatus = Get-CodexHDriveStatus -DriveLetter 'H' -MinimumFreeBytes $MinimumFreeBytes
        Write-HDriveStatusLog -Status $lockedStatus -Label 'Locked H drive status:'
        Assert-CodexHDriveWritable -Status $lockedStatus
        Invoke-DownloadsSync
    }
    exit $exitCode
} catch {
    Write-LogLine "Refusing H: write. $($_.Exception.Message)"
    exit 3
}
