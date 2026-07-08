param(
    [switch]$ListOnly,
    [string]$RefreshList = 'E:\Scripts\state\h-downloads-known-bad-20260707.csv'
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

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "downloads-to-h-$Stamp.log"

function Write-LogLine {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

Write-LogLine "Downloads sync starting."
Write-LogLine "Mode: $(if ($ListOnly) { 'ListOnly' } else { 'Copy' })"
Write-LogLine "Source: $Source"
Write-LogLine "Destination: $Destination"
Write-LogLine "Refresh list: $RefreshList"

if (-not (Test-Path -LiteralPath $Source)) {
    Write-LogLine "Source is missing. Nothing copied."
    exit 2
}

if (-not (Test-Path -LiteralPath $TargetDrive)) {
    Write-LogLine "H: is not mounted. Skipping."
    exit 0
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

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
& robocopy @RobocopyArgs
$code = $LASTEXITCODE

Write-LogLine "Robocopy exit code: $code"

if ($code -ge 8) {
    Write-LogLine "Sync completed with errors."
    exit $code
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
            exit 8
        }

        $donePath = "$RefreshList.done-$Stamp"
        Move-Item -LiteralPath $RefreshList -Destination $donePath -Force
        Write-LogLine "Refresh list completed and moved to: $donePath"
    }
} else {
    Write-LogLine "No refresh list found."
}

Write-LogLine "Sync completed successfully."
exit 0
