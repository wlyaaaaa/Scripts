param(
    [switch]$ListOnly,
    [UInt64]$MinimumFreeBytes = [UInt64](2GB),
    [int]$MutexWaitSeconds = 1800
)

# Hot-backup the Windows Downloads folder to G without deleting old G files.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$Source = 'E:\Downloads'
$Destination = 'G:\80_Backup\03_下载与安装包'
$LogDir = Join-Path $PSScriptRoot 'logs'
$MutexName = 'Global\CodexGHotBackupWriteLock'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "downloads-to-g-$Stamp.log"

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

if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Source is missing: $Source" }
Assert-GHotWritable

$createdNew = $false
$mutex = [Threading.Mutex]::new($false, $MutexName, [ref]$createdNew)
$hasLock = $false
try {
    $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexWaitSeconds))
    if (-not $hasLock) { throw "Timed out waiting for $MutexName." }
    if (-not $ListOnly) { $null = New-Item -ItemType Directory -Path $Destination -Force }
    $arguments = @($Source,$Destination,'/E','/COPY:DAT','/DCOPY:DAT','/R:0','/W:0','/XJ','/FFT','/NP','/MT:4','/J',"/LOG+:$LogFile")
    if ($ListOnly) { $arguments += '/L' }
    Write-LogLine "Downloads hot backup: $Source -> $Destination"
    & robocopy @arguments
    $exitCode = $LASTEXITCODE
    Write-LogLine "Robocopy exit code: $exitCode"
    if ($exitCode -ge 8) { exit $exitCode }
    exit 0
} finally {
    if ($hasLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
