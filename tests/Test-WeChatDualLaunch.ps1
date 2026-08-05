#requires -Version 7.0

param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$launcherPath = Join-Path $repoRoot 'Invoke-WeChatDualLaunch.ps1'
$wrapperPath = Join-Path $repoRoot ([string]([char]0x5FAE) + [char]0x4FE1 + [char]0x53CC + [char]0x5F00 + '.vbs')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Invoke-LauncherChild {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(
        & pwsh -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $launcherPath @Arguments 2>&1
    )
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    $parsed = $null
    if ($text) {
        try {
            $parsed = $text | ConvertFrom-Json -Depth 20
        } catch {
            throw "Launcher did not emit one valid JSON document. Exit=$exitCode Output=$text"
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text
        Json = $parsed
    }
}

function Get-TestProcesses([string]$ProcessName) {
    return @(
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    -not $_.HasExited
                } catch {
                    $false
                }
            }
    )
}

Assert-True (Test-Path -LiteralPath $launcherPath -PathType Leaf) `
    'PowerShell launcher exists'
Assert-True (Test-Path -LiteralPath $wrapperPath -PathType Leaf) `
    'double-click VBS wrapper exists'

$launcherCommand = Get-Command $launcherPath
foreach ($parameterName in @(
    'WeChatPath',
    'DesiredInstances',
    'BetweenLaunchDelaySeconds',
    'StabilizationSeconds',
    'ReceiptPath',
    'Json'
)) {
    Assert-True $launcherCommand.Parameters.ContainsKey($parameterName) `
        "stable integration parameter exists: -$parameterName"
}

$launcherText = Get-Content -LiteralPath $launcherPath -Raw -Encoding utf8
$wrapperText = Get-Content -LiteralPath $wrapperPath -Raw -Encoding utf8
Assert-True (-not ($launcherText.ToCharArray() | Where-Object { [int]$_ -gt 127 })) `
    'PowerShell launcher is ASCII-only'
Assert-True ($launcherText -match '(?i)Start-Process[\s\S]*-WorkingDirectory') `
    'launcher supplies the executable directory as WorkingDirectory'
Assert-True (
    $launcherText -match '\.Threads\.Count' -and
    $launcherText -match '\.HandleCount' -and
    $launcherText -match 'Get-CimInstance' -and
    $launcherText -match 'ParentProcessId' -and
    $launcherText -match 'SessionId'
) 'health counting checks threads, handles, CIM parent IDs, and session scope'
Assert-True ($launcherText -match 'System\.Threading\.Mutex') `
    'launcher serializes concurrent invocations with a named mutex'
Assert-True ($launcherText -notmatch '(?i)SendKeys|mouse_event|SetCursorPos|\bClick\b') `
    'launcher has no coordinate or synthetic-input automation'
Assert-True (
    $wrapperText -match '(?i)BuildPath\s*\(\s*scriptDir\s*,\s*"Invoke-WeChatDualLaunch\.ps1"\s*\)' -and
    $wrapperText -notmatch '(?i)Program Files|Tencent\\Weixin\\Weixin\.exe' -and
    $wrapperText -match '(?i)\.Run\s*\(\s*command\s*,\s*0\s*,'
) 'VBS resolves the launcher relative to itself and runs it without a console'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'wechat-dual-launch-{0}-{1}' -f $PID, [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$processName = 'WcD' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$crashProcessName = 'WcF' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$topologyProcessName = 'WcT' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$handoffBootstrapName = 'WcB' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$handoffTargetName = 'WcH' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$initialExitProcessName = 'WcI' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$fakeExe = Join-Path $tempRoot ($processName + '.exe')
$crashExe = Join-Path $tempRoot ($crashProcessName + '.exe')
$topologyExe = Join-Path $tempRoot ($topologyProcessName + '.exe')
$handoffBootstrapExe = Join-Path $tempRoot ($handoffBootstrapName + '.exe')
$handoffTargetExe = Join-Path $tempRoot ($handoffTargetName + '.exe')
$initialExitExe = Join-Path $tempRoot ($initialExitProcessName + '.exe')
$logDir = Join-Path $tempRoot 'launch-log'
$receiptPath = Join-Path $tempRoot 'receipt.json'
$mutexName = 'Local\WeChatDualLaunchTest-' + [guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $logDir | Out-Null

try {
    $wrapperFixtureDirectory = Join-Path $tempRoot 'wrapper-fixture'
    New-Item -ItemType Directory -Path $wrapperFixtureDirectory | Out-Null
    $wrapperFixturePath = Join-Path $wrapperFixtureDirectory (
        [IO.Path]::GetFileName($wrapperPath)
    )
    $wrapperLauncherFixture = Join-Path $wrapperFixtureDirectory (
        'Invoke-WeChatDualLaunch.ps1'
    )
    $wrapperMarkerPath = Join-Path $tempRoot 'wrapper-marker.txt'
    Copy-Item -LiteralPath $wrapperPath -Destination $wrapperFixturePath
    $wrapperLauncherSource = @'
$markerPath = $env:WECHAT_DUAL_WRAPPER_MARKER
[IO.File]::WriteAllText(
    $markerPath,
    $PSScriptRoot,
    [Text.UTF8Encoding]::new($false)
)
exit 0
'@
    [IO.File]::WriteAllText(
        $wrapperLauncherFixture,
        $wrapperLauncherSource,
        [Text.UTF8Encoding]::new($false)
    )
    $env:WECHAT_DUAL_WRAPPER_MARKER = $wrapperMarkerPath
    & "$env:SystemRoot\System32\cscript.exe" //nologo $wrapperFixturePath
    $wrapperFixtureExitCode = $LASTEXITCODE
    Assert-True (
        $wrapperFixtureExitCode -eq 0 -and
        (Test-Path -LiteralPath $wrapperMarkerPath -PathType Leaf)
    ) 'VBS wrapper executes the sibling PowerShell launcher and propagates success'
    $wrapperRecordedDirectory = Get-Content `
        -LiteralPath $wrapperMarkerPath `
        -Raw `
        -Encoding utf8
    Assert-True (
        $wrapperRecordedDirectory.Equals(
            $wrapperFixtureDirectory,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) 'VBS wrapper resolves its sibling launcher independent of current directory'
    Remove-Item Env:WECHAT_DUAL_WRAPPER_MARKER -ErrorAction SilentlyContinue

    $missingName = 'WcM' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $missing = Invoke-LauncherChild -Arguments @(
        '-WeChatPath', (Join-Path $tempRoot 'missing.exe'),
        '-ProcessName', $missingName,
        '-DesiredInstances', '2',
        '-BetweenLaunchDelaySeconds', '0.02',
        '-StabilizationSeconds', '0.05',
        '-ObservationPollMilliseconds', '10',
        '-MutexName', ($mutexName + '-missing'),
        '-MutexTimeoutMilliseconds', '500',
        '-Json'
    )
    Assert-True ($missing.ExitCode -ne 0) `
        'missing executable fails closed'
    Assert-True ($missing.Json.status -eq 'executable_missing') `
        'missing executable reports a deterministic status'
    Assert-True ((Get-TestProcesses $missingName).Count -eq 0) `
        'missing executable starts no process'

    $compiler = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    Assert-True ([bool]$compiler) 'test fixture compiler is available'

    $sourcePath = Join-Path $tempRoot 'FakeWeChat.cs'
    $source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

internal static class Program
{
    [STAThread]
    private static int Main(string[] arguments)
    {
        string logDirectory = Environment.GetEnvironmentVariable("WECHAT_DUAL_TEST_LOG");
        if (!String.IsNullOrEmpty(logDirectory))
        {
            int processId = Process.GetCurrentProcess().Id;
            string markerPath = Path.Combine(logDirectory, "cwd-" + processId + ".txt");
            File.WriteAllText(markerPath, Environment.CurrentDirectory);
        }

        string handoffTarget = Environment.GetEnvironmentVariable("WECHAT_DUAL_TEST_HANDOFF_TARGET");
        if (!String.IsNullOrEmpty(handoffTarget) && arguments.Length == 0)
        {
            int handoffDelay = 0;
            Int32.TryParse(
                Environment.GetEnvironmentVariable("WECHAT_DUAL_TEST_HANDOFF_MS"),
                out handoffDelay
            );
            if (handoffDelay > 0)
            {
                Thread.Sleep(handoffDelay);
            }

            ProcessStartInfo targetInfo = new ProcessStartInfo();
            targetInfo.FileName = handoffTarget;
            targetInfo.Arguments = "--child";
            targetInfo.UseShellExecute = false;
            targetInfo.WorkingDirectory = Environment.CurrentDirectory;
            Process target = Process.Start(targetInfo);
            if (target != null)
            {
                target.Dispose();
            }
            return 0;
        }

        string spawnChild = Environment.GetEnvironmentVariable("WECHAT_DUAL_TEST_SPAWN_CHILD");
        if (String.Equals(spawnChild, "1", StringComparison.Ordinal) && arguments.Length == 0)
        {
            ProcessStartInfo childInfo = new ProcessStartInfo();
            childInfo.FileName = Process.GetCurrentProcess().MainModule.FileName;
            childInfo.Arguments = "--child";
            childInfo.UseShellExecute = false;
            childInfo.WorkingDirectory = Environment.CurrentDirectory;
            Process child = Process.Start(childInfo);
            if (child != null)
            {
                child.Dispose();
            }
        }

        int delayMilliseconds = 30000;
        string requestedDelay = Environment.GetEnvironmentVariable("WECHAT_DUAL_TEST_EXIT_MS");
        int parsedDelay;
        if (Int32.TryParse(requestedDelay, out parsedDelay) && parsedDelay >= 0)
        {
            delayMilliseconds = parsedDelay;
        }

        Thread.Sleep(delayMilliseconds);
        return 0;
    }
}
'@
    [IO.File]::WriteAllText(
        $sourcePath,
        $source,
        [Text.UTF8Encoding]::new($false)
    )
    & $compiler /nologo /target:winexe "/out:$fakeExe" $sourcePath
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fakeExe -PathType Leaf)) `
        'temporary independent-name fake executable compiles'

    $env:WECHAT_DUAL_TEST_LOG = $logDir
    $commonArguments = @(
        '-WeChatPath', $fakeExe,
        '-ProcessName', $processName,
        '-DesiredInstances', '2',
        '-BetweenLaunchDelaySeconds', '0.05',
        '-StartupTimeoutSeconds', '0.1',
        '-StabilizationSeconds', '0.2',
        '-ObservationPollMilliseconds', '25',
        '-MaxLaunchAttempts', '3',
        '-MutexName', $mutexName,
        '-MutexTimeoutMilliseconds', '1000',
        '-Json'
    )

    $first = Invoke-LauncherChild -Arguments @(
        $commonArguments[0..($commonArguments.Count - 2)]
        '-ReceiptPath'
        $receiptPath
        '-Json'
    )
    Assert-True ($first.ExitCode -eq 0) `
        "zero-to-two launch succeeds: $($first.Output)"
    Assert-True (
        $first.Json.status -eq 'complete' -and
        [int]$first.Json.initial_count -eq 0 -and
        [int]$first.Json.final_count -eq 2 -and
        [int]$first.Json.launched_count -eq 2 -and
        [bool]$first.Json.stability_verified
    ) 'zero-to-two result records exactly two serial launches'

    $running = @(Get-TestProcesses $processName)
    Assert-True ($running.Count -eq 2) `
        'zero-to-two run leaves exactly two fake processes'
    Assert-True (
        @($running | Where-Object {
            $_.Threads.Count -gt 0 -and $_.HandleCount -gt 0
        }).Count -eq 2
    ) 'both fake processes satisfy the health gate'

    $markerDeadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
    do {
        $markers = @(Get-ChildItem -LiteralPath $logDir -Filter 'cwd-*.txt' -File)
        if ($markers.Count -ge 2) { break }
        Start-Sleep -Milliseconds 50
    } while ([DateTimeOffset]::UtcNow -lt $markerDeadline)
    Assert-True ($markers.Count -eq 2) `
        'both fake processes record their working directory'
    $expectedWorkingDirectory = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    foreach ($marker in $markers) {
        $actualWorkingDirectory = (
            Get-Content -LiteralPath $marker.FullName -Raw -Encoding utf8
        ).TrimEnd('\')
        Assert-True (
            $actualWorkingDirectory.Equals(
                $expectedWorkingDirectory,
                [StringComparison]::OrdinalIgnoreCase
            )
        ) "fake process uses executable directory as WorkingDirectory: $($marker.Name)"
    }

    Assert-True (Test-Path -LiteralPath $receiptPath -PathType Leaf) `
        'optional receipt is written'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding utf8 |
        ConvertFrom-Json -Depth 20
    Assert-True (
        $receipt.status -eq 'complete' -and
        [int]$receipt.final_count -eq 2
    ) 'receipt matches the successful result'
    Assert-True (
        @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -File).Count -eq 0
    ) 'atomic receipt leaves no temporary file'

    $beforeIds = @(
        Get-TestProcesses $processName | Sort-Object Id | ForEach-Object Id
    )
    $second = Invoke-LauncherChild -Arguments @(
        $commonArguments[0..($commonArguments.Count - 2)]
        '-ReceiptPath'
        $receiptPath
        '-Json'
    )
    $afterIds = @(
        Get-TestProcesses $processName | Sort-Object Id | ForEach-Object Id
    )
    Assert-True ($second.ExitCode -eq 0) `
        "already-at-two launch succeeds: $($second.Output)"
    Assert-True (
        $second.Json.status -eq 'complete' -and
        [int]$second.Json.initial_count -eq 2 -and
        [int]$second.Json.final_count -eq 2 -and
        [int]$second.Json.launched_count -eq 0 -and
        [int]$second.Json.attempt_count -eq 0 -and
        [bool]$second.Json.stability_verified
    ) 'already-at-two run is idempotent'
    Assert-True (($beforeIds -join ',') -ceq ($afterIds -join ',')) `
        'idempotent run preserves the same process IDs'
    $replacementReceipt = Get-Content `
        -LiteralPath $receiptPath `
        -Raw `
        -Encoding utf8 |
        ConvertFrom-Json -Depth 20
    Assert-True (
        $replacementReceipt.status -eq 'complete' -and
        [int]$replacementReceipt.launched_count -eq 0
    ) 'atomic receipt replacement records the newer idempotent run'
    Assert-True (
        @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -File).Count -eq 0
    ) 'atomic receipt replacement leaves no temporary file'

    $receiptBeforeMutexTimeout = Get-Content `
        -LiteralPath $receiptPath `
        -Raw `
        -Encoding utf8
    $heldMutex = [Threading.Mutex]::new($false, $mutexName)
    $heldMutexOwned = $false
    try {
        $heldMutexOwned = $heldMutex.WaitOne(0)
        Assert-True $heldMutexOwned 'test owns the launch mutex before timeout probe'
        $mutexTimeout = Invoke-LauncherChild -Arguments @(
            '-WeChatPath', $fakeExe,
            '-ProcessName', $processName,
            '-DesiredInstances', '2',
            '-BetweenLaunchDelaySeconds', '0',
            '-StartupTimeoutSeconds', '0',
            '-StabilizationSeconds', '0',
            '-MutexName', $mutexName,
            '-MutexTimeoutMilliseconds', '100',
            '-ReceiptPath', $receiptPath,
            '-Json'
        )
    } finally {
        if ($heldMutexOwned) {
            $heldMutex.ReleaseMutex()
        }
        $heldMutex.Dispose()
    }
    $receiptAfterMutexTimeout = Get-Content `
        -LiteralPath $receiptPath `
        -Raw `
        -Encoding utf8
    Assert-True (
        $mutexTimeout.ExitCode -eq 3 -and
        $mutexTimeout.Json.status -eq 'mutex_timeout' -and
        $mutexTimeout.Json.receipt_status -eq 'skipped_mutex_timeout'
    ) 'mutex timeout fails closed without an unlocked shared-receipt write'
    Assert-True ($receiptAfterMutexTimeout -ceq $receiptBeforeMutexTimeout) `
        'mutex timeout preserves the receipt written by the mutex owner'

    Copy-Item -LiteralPath $fakeExe -Destination $crashExe
    $env:WECHAT_DUAL_TEST_EXIT_MS = '25'
    $boundedWatch = [Diagnostics.Stopwatch]::StartNew()
    $boundedFailure = Invoke-LauncherChild -Arguments @(
        '-WeChatPath', $crashExe,
        '-ProcessName', $crashProcessName,
        '-DesiredInstances', '2',
        '-BetweenLaunchDelaySeconds', '0.05',
        '-StartupTimeoutSeconds', '0.1',
        '-StabilizationSeconds', '0.2',
        '-ObservationPollMilliseconds', '25',
        '-MaxLaunchAttempts', '2',
        '-MutexName', ($mutexName + '-bounded-failure'),
        '-MutexTimeoutMilliseconds', '1000',
        '-Json'
    )
    $boundedWatch.Stop()
    Assert-True (
        $boundedFailure.ExitCode -ne 0 -and
        $boundedFailure.Json.status -eq 'target_not_reached' -and
        [int]$boundedFailure.Json.final_count -eq 0 -and
        [int]$boundedFailure.Json.attempt_count -eq 2 -and
        [int]$boundedFailure.Json.launched_count -eq 2 -and
        -not [bool]$boundedFailure.Json.stability_verified
    ) 'repeated early exits stop at the configured launch-attempt limit'
    Assert-True ($boundedWatch.Elapsed.TotalSeconds -lt 30) `
        'early-exit handling is bounded and does not restart forever'

    Copy-Item -LiteralPath $fakeExe -Destination $topologyExe
    Remove-Item Env:WECHAT_DUAL_TEST_EXIT_MS -ErrorAction SilentlyContinue
    $env:WECHAT_DUAL_TEST_SPAWN_CHILD = '1'
    $topologyParent = Start-Process `
        -FilePath $topologyExe `
        -WorkingDirectory $tempRoot `
        -PassThru
    $topologyParent.Dispose()
    $topologyDeadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
    do {
        $topologyBefore = @(Get-TestProcesses $topologyProcessName)
        if ($topologyBefore.Count -ge 2) { break }
        Start-Sleep -Milliseconds 50
    } while ([DateTimeOffset]::UtcNow -lt $topologyDeadline)
    Assert-True ($topologyBefore.Count -eq 2) `
        'topology fixture starts one parent and one same-name child'

    Remove-Item Env:WECHAT_DUAL_TEST_SPAWN_CHILD -ErrorAction SilentlyContinue
    $topology = Invoke-LauncherChild -Arguments @(
        '-WeChatPath', $topologyExe,
        '-ProcessName', $topologyProcessName,
        '-DesiredInstances', '2',
        '-BetweenLaunchDelaySeconds', '0.05',
        '-StabilizationSeconds', '0.2',
        '-ObservationPollMilliseconds', '25',
        '-MaxLaunchAttempts', '2',
        '-MutexName', ($mutexName + '-topology'),
        '-MutexTimeoutMilliseconds', '1000',
        '-Json'
    )
    Assert-True (
        $topology.ExitCode -eq 0 -and
        [int]$topology.Json.initial_count -eq 1 -and
        [int]$topology.Json.launched_count -eq 1 -and
        [int]$topology.Json.final_count -eq 2 -and
        [bool]$topology.Json.stability_verified
    ) 'same-name child is excluded from the healthy top-level count'
    Assert-True ((Get-TestProcesses $topologyProcessName).Count -eq 3) `
        'topology run has two top-level processes plus one same-name child'

    Copy-Item -LiteralPath $fakeExe -Destination $handoffBootstrapExe
    Copy-Item -LiteralPath $fakeExe -Destination $handoffTargetExe
    $env:WECHAT_DUAL_TEST_HANDOFF_TARGET = $handoffTargetExe
    $env:WECHAT_DUAL_TEST_HANDOFF_MS = '350'
    $handoff = Invoke-LauncherChild -Arguments @(
        '-WeChatPath', $handoffBootstrapExe,
        '-ProcessName', $handoffTargetName,
        '-DesiredInstances', '1',
        '-BetweenLaunchDelaySeconds', '0.02',
        '-StartupTimeoutSeconds', '1',
        '-StabilizationSeconds', '0.15',
        '-ObservationPollMilliseconds', '25',
        '-MaxLaunchAttempts', '1',
        '-MutexName', ($mutexName + '-handoff'),
        '-MutexTimeoutMilliseconds', '1000',
        '-Json'
    )
    Remove-Item Env:WECHAT_DUAL_TEST_HANDOFF_TARGET -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_HANDOFF_MS -ErrorAction SilentlyContinue
    Assert-True (
        $handoff.ExitCode -eq 0 -and
        [int]$handoff.Json.initial_count -eq 0 -and
        [int]$handoff.Json.launched_count -eq 1 -and
        [int]$handoff.Json.final_count -eq 1 -and
        [bool]$handoff.Json.stability_verified
    ) 'bounded startup wait accepts a delayed same-purpose process handoff'

    Copy-Item -LiteralPath $fakeExe -Destination $initialExitExe
    $env:WECHAT_DUAL_TEST_EXIT_MS = '2500'
    $initialExitProcess = Start-Process `
        -FilePath $initialExitExe `
        -WorkingDirectory $tempRoot `
        -PassThru
    $initialExitProcess.Dispose()
    $initialExitDeadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
    do {
        $initialExitRunning = @(Get-TestProcesses $initialExitProcessName)
        if ($initialExitRunning.Count -eq 1) { break }
        Start-Sleep -Milliseconds 50
    } while ([DateTimeOffset]::UtcNow -lt $initialExitDeadline)
    Assert-True ($initialExitRunning.Count -eq 1) `
        'initial-stability fixture is running before launcher invocation'
    $initialStability = Invoke-LauncherChild -Arguments @(
        '-WeChatPath', $initialExitExe,
        '-ProcessName', $initialExitProcessName,
        '-DesiredInstances', '1',
        '-BetweenLaunchDelaySeconds', '0.02',
        '-StartupTimeoutSeconds', '0.1',
        '-StabilizationSeconds', '3',
        '-ObservationPollMilliseconds', '50',
        '-MaxLaunchAttempts', '1',
        '-MutexName', ($mutexName + '-initial-stability'),
        '-MutexTimeoutMilliseconds', '1000',
        '-Json'
    )
    Remove-Item Env:WECHAT_DUAL_TEST_EXIT_MS -ErrorAction SilentlyContinue
    Assert-True (
        $initialStability.ExitCode -ne 0 -and
        $initialStability.Json.status -eq 'target_not_reached' -and
        [int]$initialStability.Json.initial_count -eq 1 -and
        [int]$initialStability.Json.attempt_count -eq 1 -and
        [int]$initialStability.Json.final_count -eq 0 -and
        -not [bool]$initialStability.Json.stability_verified
    ) 'initially satisfied target must remain healthy through stabilization'
} finally {
    Remove-Item Env:WECHAT_DUAL_WRAPPER_MARKER -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_EXIT_MS -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_SPAWN_CHILD -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_HANDOFF_TARGET -ErrorAction SilentlyContinue
    Remove-Item Env:WECHAT_DUAL_TEST_HANDOFF_MS -ErrorAction SilentlyContinue
    $fixtureProcessNames = @(
        $processName,
        $crashProcessName,
        $topologyProcessName,
        $handoffBootstrapName,
        $handoffTargetName,
        $initialExitProcessName
    )
    $resolvedTempForCleanup = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\') + '\'
    $cleanupIds = [Collections.Generic.List[int]]::new()
    $cleanupProcesses = @(
        Get-Process -Name $fixtureProcessNames -ErrorAction SilentlyContinue
    )
    foreach ($cleanupProcess in $cleanupProcesses) {
        try {
            $cleanupPath = $cleanupProcess.Path
            if (
                -not [string]::IsNullOrWhiteSpace($cleanupPath) -and
                [IO.Path]::GetFullPath($cleanupPath).StartsWith(
                    $resolvedTempForCleanup,
                    [StringComparison]::OrdinalIgnoreCase
                )
            ) {
                $cleanupIds.Add([int]$cleanupProcess.Id)
            }
        } catch {
            Write-Warning (
                'Skipping unverified cleanup PID {0}: {1}' -f
                $cleanupProcess.Id,
                $_.Exception.Message
            )
        } finally {
            $cleanupProcess.Dispose()
        }
    }
    if ($cleanupIds.Count -gt 0) {
        Stop-Process -Id $cleanupIds.ToArray() -Force -ErrorAction SilentlyContinue
        Wait-Process `
            -Id $cleanupIds.ToArray() `
            -Timeout 5 `
            -ErrorAction SilentlyContinue
    }

    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (
        $resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemp)
    ) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host 'OK WeChat dual-launch tests passed.'
