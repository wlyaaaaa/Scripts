#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [Alias('ExecutablePath')]
    [string]$WeChatPath = (Join-Path $env:ProgramFiles 'Tencent\Weixin\Weixin.exe'),

    [Parameter()]
    [string]$ProcessName,

    [Parameter()]
    [Alias('TargetCount')]
    [ValidateRange(1, 32)]
    [int]$DesiredInstances = 2,

    [Parameter()]
    [ValidateRange(0.0, 60.0)]
    [double]$BetweenLaunchDelaySeconds = 1.5,

    [Parameter()]
    [ValidateRange(0.0, 60.0)]
    [double]$StartupTimeoutSeconds = 5.0,

    [Parameter()]
    [ValidateRange(0.0, 60.0)]
    [double]$StabilizationSeconds = 1.5,

    [Parameter()]
    [ValidateRange(10, 5000)]
    [int]$ObservationPollMilliseconds = 100,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$MaxLaunchAttempts = 0,

    [Parameter()]
    [string[]]$LaunchArgumentList = @(),

    [Parameter()]
    [string]$MutexName = 'Local\Scripts-WeChatDualLaunch',

    [Parameter()]
    [ValidateRange(0, 60000)]
    [int]$MutexTimeoutMilliseconds = 10000,

    [Parameter()]
    [string]$ReceiptPath,

    [Parameter()]
    [switch]$Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$effectiveLaunchIntervalMilliseconds = [int][Math]::Round(
    $BetweenLaunchDelaySeconds * 1000
)
$effectiveStartupTimeoutMilliseconds = [int][Math]::Round(
    $StartupTimeoutSeconds * 1000
)
$effectiveStableObservationMilliseconds = [int][Math]::Round(
    $StabilizationSeconds * 1000
)
$effectiveSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId

function Get-HealthyTopLevelProcessIds {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$SessionId
    )

    $cimProcesses = @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter ("Name = '{0}.exe' AND SessionId = {1}" -f $Name, $SessionId) `
            -Property ProcessId, ParentProcessId, Name, SessionId `
            -ErrorAction Stop
    )
    if ($cimProcesses.Count -eq 0) {
        return @()
    }

    $allIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($cimProcess in $cimProcesses) {
        [void]$allIds.Add([int]$cimProcess.ProcessId)
    }

    $healthyIds = [Collections.Generic.List[int]]::new()
    foreach ($cimProcess in $cimProcesses) {
        $processId = [int]$cimProcess.ProcessId
        $parentProcessId = [int]$cimProcess.ParentProcessId
        if ($allIds.Contains($parentProcessId)) {
            continue
        }

        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        try {
            $process.Refresh()
            if ($process.HasExited) {
                continue
            }
            if (-not $process.ProcessName.Equals($Name, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if ($process.Threads.Count -le 0) {
                continue
            }
            if ($process.HandleCount -le 0) {
                continue
            }

            $healthyIds.Add($processId)
        } catch {
            # A process that cannot be refreshed is not healthy enough to count.
        } finally {
            $process.Dispose()
        }
    }

    return $healthyIds.ToArray()
}

function Test-HealthyCountStable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][int]$MinimumCount,
        [Parameter(Mandatory = $true)][int]$DurationMilliseconds,
        [Parameter(Mandatory = $true)][int]$PollMilliseconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($DurationMilliseconds)
    $lastCount = 0
    do {
        $lastCount = @(
            Get-HealthyTopLevelProcessIds -Name $Name -SessionId $SessionId
        ).Count
        if ($lastCount -lt $MinimumCount) {
            return [pscustomobject]@{
                Stable = $false
                Count = $lastCount
            }
        }

        if ($DurationMilliseconds -eq 0) {
            break
        }

        $remaining = [int][Math]::Ceiling(
            ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds
        )
        if ($remaining -le 0) {
            break
        }
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remaining))
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    return [pscustomobject]@{
        Stable = $true
        Count = $lastCount
    }
}

function Wait-HealthyCountAtLeast {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][int]$MinimumCount,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory = $true)][int]$PollMilliseconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $lastCount = 0
    do {
        $lastCount = @(
            Get-HealthyTopLevelProcessIds -Name $Name -SessionId $SessionId
        ).Count
        if ($lastCount -ge $MinimumCount) {
            return [pscustomobject]@{
                Reached = $true
                Count = $lastCount
            }
        }

        if ($TimeoutMilliseconds -eq 0) {
            break
        }
        $remaining = [int][Math]::Ceiling(
            ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds
        )
        if ($remaining -le 0) {
            break
        }
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remaining))
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    return [pscustomobject]@{
        Reached = $false
        Count = $lastCount
    }
}

function Write-AtomicJsonReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw 'ReceiptPath must include a valid parent directory.'
    }

    [void][IO.Directory]::CreateDirectory($directory)
    $temporaryPath = Join-Path $directory (
        '.{0}.{1}.tmp' -f [IO.Path]::GetFileName($fullPath),
        [guid]::NewGuid().ToString('N')
    )
    try {
        [IO.File]::WriteAllText(
            $temporaryPath,
            $Content + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
        [IO.File]::Move($temporaryPath, $fullPath, $true)
    } finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }

    return $fullPath
}

function New-LaunchResult {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedExecutablePath
    )

    return [ordered]@{
        schema = 'scripts.wechat-dual-launch.v1'
        status = 'not_started'
        success = $false
        exit_code = 1
        started_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        finished_at_utc = $null
        executable_path = $RequestedExecutablePath
        working_directory = $null
        process_name = $null
        desired_instances = $DesiredInstances
        target_count = $DesiredInstances
        between_launch_delay_seconds = $effectiveLaunchIntervalMilliseconds / 1000.0
        startup_timeout_seconds = $effectiveStartupTimeoutMilliseconds / 1000.0
        stabilization_seconds = $effectiveStableObservationMilliseconds / 1000.0
        session_id = $effectiveSessionId
        initial_count = 0
        final_count = 0
        launched_count = 0
        attempt_count = 0
        stability_verified = $false
        launched_process_ids = @()
        max_launch_attempts = 0
        mutex_name = $MutexName
        receipt_status = 'not_requested'
        receipt_path = $null
        error = $null
    }
}

function Invoke-DualLaunch {
    $result = New-LaunchResult -RequestedExecutablePath $WeChatPath
    $mutex = $null
    $ownsMutex = $false
    $launchedIds = [Collections.Generic.List[int]]::new()

    try {
        if ([string]::IsNullOrWhiteSpace($MutexName)) {
            throw 'MutexName must not be empty.'
        }

        $createdNew = $false
        $mutex = [System.Threading.Mutex]::new(
            $false,
            $MutexName,
            [ref]$createdNew
        )
        try {
            $ownsMutex = $mutex.WaitOne($MutexTimeoutMilliseconds)
        } catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            $result.status = 'mutex_timeout'
            $result.exit_code = 3
            $result.error = 'The named launch mutex could not be acquired before the timeout.'
            return $result
        }

        if (-not (Test-Path -LiteralPath $WeChatPath -PathType Leaf)) {
            $result.status = 'executable_missing'
            $result.exit_code = 2
            $result.error = 'The WeChat executable was not found.'
            return $result
        }

        $resolvedExecutable = (Resolve-Path -LiteralPath $WeChatPath).Path
        $workingDirectory = [IO.Path]::GetDirectoryName($resolvedExecutable)
        $effectiveProcessName = $ProcessName
        if ([string]::IsNullOrWhiteSpace($effectiveProcessName)) {
            $effectiveProcessName = [IO.Path]::GetFileNameWithoutExtension(
                $resolvedExecutable
            )
        } elseif ($effectiveProcessName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $effectiveProcessName = [IO.Path]::GetFileNameWithoutExtension(
                $effectiveProcessName
            )
        }
        if ([string]::IsNullOrWhiteSpace($effectiveProcessName)) {
            throw 'ProcessName could not be derived from WeChatPath.'
        }
        if ($effectiveProcessName -notmatch '^[A-Za-z0-9._-]+$') {
            throw 'ProcessName contains unsupported characters.'
        }
        $effectiveMaxLaunchAttempts = $MaxLaunchAttempts
        if ($effectiveMaxLaunchAttempts -eq 0) {
            $effectiveMaxLaunchAttempts = [Math]::Min(100, $DesiredInstances + 2)
        }

        $result.executable_path = $resolvedExecutable
        $result.working_directory = $workingDirectory
        $result.process_name = $effectiveProcessName
        $result.max_launch_attempts = $effectiveMaxLaunchAttempts

        $currentCount = @(
            Get-HealthyTopLevelProcessIds `
                -Name $effectiveProcessName `
                -SessionId $effectiveSessionId
        ).Count
        $result.initial_count = $currentCount
        $stableTargetReached = $false

        if ($currentCount -ge $DesiredInstances) {
            $initialObservation = Test-HealthyCountStable `
                -Name $effectiveProcessName `
                -SessionId $effectiveSessionId `
                -MinimumCount $DesiredInstances `
                -DurationMilliseconds $effectiveStableObservationMilliseconds `
                -PollMilliseconds $ObservationPollMilliseconds
            $currentCount = $initialObservation.Count
            $stableTargetReached = $initialObservation.Stable
        }

        while (
            -not $stableTargetReached -and
            $result.attempt_count -lt $effectiveMaxLaunchAttempts
        ) {
            $currentCount = @(
                Get-HealthyTopLevelProcessIds `
                    -Name $effectiveProcessName `
                    -SessionId $effectiveSessionId
            ).Count
            if ($currentCount -ge $DesiredInstances) {
                $recoveryObservation = Test-HealthyCountStable `
                    -Name $effectiveProcessName `
                    -SessionId $effectiveSessionId `
                    -MinimumCount $DesiredInstances `
                    -DurationMilliseconds $effectiveStableObservationMilliseconds `
                    -PollMilliseconds $ObservationPollMilliseconds
                $currentCount = $recoveryObservation.Count
                if ($recoveryObservation.Stable) {
                    $stableTargetReached = $true
                    break
                }
            }

            $result.attempt_count++
            $expectedCount = [Math]::Min($DesiredInstances, $currentCount + 1)
            try {
                if ($LaunchArgumentList.Count -gt 0) {
                    $startedProcess = Start-Process `
                        -FilePath $resolvedExecutable `
                        -ArgumentList $LaunchArgumentList `
                        -WorkingDirectory $workingDirectory `
                        -PassThru
                } else {
                    $startedProcess = Start-Process `
                        -FilePath $resolvedExecutable `
                        -WorkingDirectory $workingDirectory `
                        -PassThru
                }
                $launchedIds.Add([int]$startedProcess.Id)
                $startedProcess.Dispose()
            } catch {
                $result.error = $_.Exception.Message
                continue
            }

            if ($effectiveLaunchIntervalMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $effectiveLaunchIntervalMilliseconds
            }

            $appearance = Wait-HealthyCountAtLeast `
                -Name $effectiveProcessName `
                -SessionId $effectiveSessionId `
                -MinimumCount $expectedCount `
                -TimeoutMilliseconds $effectiveStartupTimeoutMilliseconds `
                -PollMilliseconds $ObservationPollMilliseconds
            $currentCount = $appearance.Count
            if (-not $appearance.Reached) {
                continue
            }

            $observation = Test-HealthyCountStable `
                -Name $effectiveProcessName `
                -SessionId $effectiveSessionId `
                -MinimumCount $expectedCount `
                -DurationMilliseconds $effectiveStableObservationMilliseconds `
                -PollMilliseconds $ObservationPollMilliseconds
            $currentCount = $observation.Count
            $stableTargetReached = (
                $observation.Stable -and
                $currentCount -ge $DesiredInstances
            )
        }

        $result.launched_process_ids = $launchedIds.ToArray()
        $result.launched_count = $launchedIds.Count
        $result.stability_verified = $stableTargetReached
        $result.final_count = @(
            Get-HealthyTopLevelProcessIds `
                -Name $effectiveProcessName `
                -SessionId $effectiveSessionId
        ).Count

        if (
            $stableTargetReached -and
            $result.final_count -ge $DesiredInstances
        ) {
            $result.status = 'complete'
            $result.exit_code = 0
            $result.error = $null
        } else {
            $result.status = 'target_not_reached'
            $result.exit_code = 4
            if ([string]::IsNullOrWhiteSpace([string]$result.error)) {
                $result.error = 'The target healthy process count was not reached within the launch-attempt limit.'
            }
        }
    } catch {
        $result.status = 'error'
        $result.exit_code = 1
        $result.error = $_.Exception.Message
    } finally {
        $result.finished_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        $result.success = ($result.exit_code -eq 0)
        if (-not [string]::IsNullOrWhiteSpace($ReceiptPath)) {
            $result.receipt_path = $ReceiptPath
            if (-not $ownsMutex -and $result.status -eq 'mutex_timeout') {
                $result.receipt_status = 'skipped_mutex_timeout'
            } else {
                try {
                    $result.receipt_status = 'written'
                    $result.receipt_path = [IO.Path]::GetFullPath($ReceiptPath)
                    $receiptJson = $result | ConvertTo-Json -Depth 10 -Compress
                    [void](Write-AtomicJsonReceipt `
                        -Path $ReceiptPath `
                        -Content $receiptJson
                    )
                } catch {
                    $result.receipt_status = 'write_failed'
                    $result.error = $_.Exception.Message
                    $result.exit_code = 5
                    $result.success = $false
                }
            }
        }

        if ($ownsMutex -and $null -ne $mutex) {
            try {
                $mutex.ReleaseMutex()
            } catch {
                # Preserve the primary operation result.
            }
        }
        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
    }

    return $result
}

$launchResult = Invoke-DualLaunch

$outputJson = $launchResult | ConvertTo-Json -Depth 10 -Compress
if ($Json) {
    [Console]::Out.WriteLine($outputJson)
} else {
    if ($launchResult.success) {
        Write-Host (
            'WeChat instances ready: {0}/{1}; launched: {2}.' -f
            $launchResult.final_count,
            $launchResult.target_count,
            $launchResult.launched_count
        )
    } else {
        Write-Error (
            'WeChat dual launch failed ({0}): {1}' -f
            $launchResult.status,
            $launchResult.error
        ) -ErrorAction Continue
    }
}

exit ([int]$launchResult.exit_code)
