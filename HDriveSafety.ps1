[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$script:CodexHDriveMutexName = 'Global\CodexHDriveUsbWriteLock'

function ConvertTo-CodexByteText {
    param([object]$Bytes)

    if ($null -eq $Bytes) {
        return 'unknown'
    }

    $value = [double]$Bytes
    if ($value -ge 1GB) {
        return ('{0:N2} GiB' -f ($value / 1GB))
    }

    if ($value -ge 1MB) {
        return ('{0:N2} MiB' -f ($value / 1MB))
    }

    return ('{0:N0} bytes' -f $value)
}

function ConvertFrom-CodexDirtyQueryOutput {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    if ($Text -match '(?i)\bNOT\s+Dirty\b' -or $Text -match '未\s*设置为\s*脏') {
        return $false
    }

    if ($Text -match '(?i)\bis\s+Dirty\b|\bDirty\b' -or $Text -match '已\s*设置为\s*脏') {
        return $true
    }

    return $null
}

function Get-CodexHDriveStatus {
    param(
        [string]$DriveLetter = 'H',
        [UInt64]$MinimumFreeBytes = [UInt64](2GB)
    )

    $letter = $DriveLetter.TrimEnd(':', '\')
    $root = "$letter`:\"
    $status = [ordered]@{
        DriveLetter       = $letter
        Root              = $root
        IsMounted         = $false
        DirtyBitSet       = $null
        DirtyCheckOutput  = $null
        DirtyCheckError   = $null
        HealthStatus      = 'Unknown'
        OperationalStatus = @('Unknown')
        FullRepairNeeded  = $false
        FreeBytes         = $null
        MinimumFreeBytes  = $MinimumFreeBytes
        IsSpaceTooLow     = $null
        SpaceCheckError   = $null
    }

    if (-not (Test-Path -LiteralPath $root)) {
        return [pscustomobject]$status
    }

    $status.IsMounted = $true

    try {
        $drive = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction Stop
        $status.FreeBytes = [UInt64]$drive.Free
        $status.IsSpaceTooLow = ($status.FreeBytes -lt $MinimumFreeBytes)
    } catch {
        $status.SpaceCheckError = $_.Exception.Message
    }

    try {
        $dirtyOutput = & fsutil dirty query "$letter`:" 2>&1
        $dirtyExit = $LASTEXITCODE
        $dirtyText = ($dirtyOutput | ForEach-Object { $_.ToString() }) -join "`n"
        $status.DirtyCheckOutput = $dirtyText.Trim()

        if ($dirtyExit -ne 0) {
            throw "fsutil dirty query exited with code $dirtyExit"
        }

        $dirtyState = ConvertFrom-CodexDirtyQueryOutput $dirtyText
        if ($null -ne $dirtyState) {
            $status.DirtyBitSet = $dirtyState
        } else {
            $status.DirtyCheckError = 'Could not parse fsutil dirty query output.'
        }
    } catch {
        if ($status.DirtyCheckError) {
            $status.DirtyCheckError = "$($status.DirtyCheckError) $($_.Exception.Message)"
        } else {
            $status.DirtyCheckError = $_.Exception.Message
        }

        # Limited scheduled-task tokens may be unable to execute fsutil. Use the
        # read-only WMI volume flag as a fallback without weakening the H gate.
        try {
            $logical = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $letter) -ErrorAction Stop
            if ($null -ne $logical.VolumeDirty) {
                $status.DirtyBitSet = [bool]$logical.VolumeDirty
                $status.DirtyCheckError = $null
                $status.DirtyCheckOutput = 'Win32_LogicalDisk.VolumeDirty fallback'
            }
        } catch {}
    }

    try {
        if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
            $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
            $status.HealthStatus = [string]$volume.HealthStatus
            $ops = @($volume.OperationalStatus | ForEach-Object { [string]$_ })
            if ($ops.Count -gt 0) {
                $status.OperationalStatus = $ops
            }
            $opText = $status.OperationalStatus -join ','
            $status.FullRepairNeeded = ($opText -match 'Full Repair Needed|Spot Fix Needed|Needs Scan')
            if ($null -ne $volume.SizeRemaining) {
                $status.FreeBytes = [UInt64]$volume.SizeRemaining
                $status.IsSpaceTooLow = ($status.FreeBytes -lt $MinimumFreeBytes)
            }
        }
    } catch {
        $status.HealthStatus = 'Unknown'
        $status.OperationalStatus = @('Unknown')
    }

    [pscustomobject]$status
}

function Format-CodexHDriveStatus {
    param([pscustomobject]$Status)

    $dirty = if ($Status.DirtyBitSet -eq $true) {
        'Dirty'
    } elseif ($Status.DirtyBitSet -eq $false) {
        'Clean'
    } else {
        'Unknown'
    }

    $label = "$($Status.DriveLetter) drive"
    @(
        "$label mounted: $($Status.IsMounted)"
        "$label dirty bit: $dirty"
        "$label health: $($Status.HealthStatus)"
        "$label operational status: $($Status.OperationalStatus -join ',')"
        "$label free space: $(ConvertTo-CodexByteText $Status.FreeBytes) (minimum $(ConvertTo-CodexByteText $Status.MinimumFreeBytes))"
        $(if ($Status.DirtyCheckError) { "$label dirty check error: $($Status.DirtyCheckError)" })
        $(if ($Status.SpaceCheckError) { "$label space check error: $($Status.SpaceCheckError)" })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Assert-CodexHDriveWritable {
    param(
        [pscustomobject]$Status,
        [switch]$AllowUnknownDirty
    )

    $problems = [System.Collections.Generic.List[string]]::new()

    $drive = "$($Status.DriveLetter):"
    if (-not $Status.IsMounted) {
        $problems.Add("$drive is not mounted.")
    }

    if ($Status.DirtyBitSet -eq $true) {
        $problems.Add("$drive dirty bit is set.")
    } elseif ($null -eq $Status.DirtyBitSet -and -not $AllowUnknownDirty) {
        $problems.Add("$drive dirty status could not be verified. $($Status.DirtyCheckError)")
    }

    if ($Status.FullRepairNeeded) {
        $problems.Add("$drive reports Full Repair Needed.")
    }

    if ($Status.HealthStatus -and $Status.HealthStatus -notin @('Healthy', 'Unknown')) {
        $problems.Add("$drive health status is $($Status.HealthStatus).")
    }

    if ($null -eq $Status.FreeBytes) {
        $problems.Add("$drive free space could not be verified. $($Status.SpaceCheckError)")
    } elseif ($Status.IsSpaceTooLow) {
        $problems.Add("$drive free space is $(ConvertTo-CodexByteText $Status.FreeBytes), below minimum $(ConvertTo-CodexByteText $Status.MinimumFreeBytes).")
    }

    if ($problems.Count -gt 0) {
        throw [System.InvalidOperationException]::new("Refusing to write $drive. $($problems -join ' ')")
    }
}

function Invoke-CodexHDriveWriteLock {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 1800,
        [string]$MutexName = $script:CodexHDriveMutexName
    )

    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($false, $MutexName, [ref]$createdNew)
    $hasLock = $false

    try {
        $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
        if (-not $hasLock) {
            throw [System.TimeoutException]::new("Timed out waiting for mutex $MutexName after $TimeoutSeconds seconds.")
        }

        & $ScriptBlock
    } finally {
        if ($hasLock) {
            $mutex.ReleaseMutex()
        }

        $mutex.Dispose()
    }
}
