param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$autoPushBat = Join-Path $repoRoot 'auto_push.bat'
$autoPushGuard = Join-Path $repoRoot 'auto_push_guard.ps1'
$taskInstaller = Join-Path $repoRoot 'Install-DownloadsHotBackupTask.ps1'
$hiddenLauncher = Join-Path $repoRoot 'Sync-DownloadsToG-Hidden.vbs'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Git([string]$WorkingDirectory, [string[]]$Arguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $WorkingDirectory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

function New-GitFixture([string]$Root, [string]$Name) {
    $fixtureRoot = Join-Path $Root $Name
    $remote = Join-Path $fixtureRoot 'remote.git'
    $seed = Join-Path $fixtureRoot 'seed'
    $work = Join-Path $fixtureRoot 'work'

    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    & git init --bare $remote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize bare test remote: $remote" }
    & git init -b main $seed | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize test seed: $seed" }
    Invoke-Git $seed @('config', 'user.name', 'Backup Automation Test')
    Invoke-Git $seed @('config', 'user.email', 'backup-automation-test@example.invalid')
    Copy-Item -LiteralPath $autoPushBat -Destination (Join-Path $seed 'auto_push.bat')
    Copy-Item -LiteralPath $autoPushGuard -Destination (Join-Path $seed 'auto_push_guard.ps1')
    [IO.File]::WriteAllText(
        (Join-Path $seed 'baseline.txt'),
        "baseline`n",
        [Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $seed @('add', '-A')
    Invoke-Git $seed @('commit', '-m', 'baseline')
    Invoke-Git $seed @('remote', 'add', 'origin', $remote)
    Invoke-Git $seed @('push', '-u', 'origin', 'main')
    Invoke-Git $remote @('symbolic-ref', 'HEAD', 'refs/heads/main')
    & git clone $remote $work | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to clone test remote: $remote" }
    Invoke-Git $work @('config', 'user.name', 'Backup Automation Test')
    Invoke-Git $work @('config', 'user.email', 'backup-automation-test@example.invalid')

    return [PSCustomObject]@{
        Remote = $remote
        Work   = $work
    }
}

function Add-Commit([string]$Repo, [string]$FileName, [string]$Content) {
    [IO.File]::WriteAllText(
        (Join-Path $Repo $FileName),
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $Repo @('add', '--', $FileName)
    Invoke-Git $Repo @('commit', '-m', "test $FileName")
}

function Invoke-AutoPush([string]$Repo) {
    Push-Location $Repo
    try {
        & cmd.exe /d /c '.\auto_push.bat' | Out-Host
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Get-RemoteMainOid([string]$Repo) {
    $line = [string](Invoke-Git $Repo @('ls-remote', '--exit-code', 'origin', 'refs/heads/main') | Select-Object -First 1)
    return ($line -split '\s+')[0]
}

function Write-GitHook([string]$Remote, [string]$Name, [string]$Content) {
    $hook = Join-Path $Remote "hooks\$Name"
    [IO.File]::WriteAllText($hook, $Content, [Text.UTF8Encoding]::new($false))
}

Assert-True (Test-Path -LiteralPath $autoPushBat -PathType Leaf) 'Missing auto_push.bat.'
Assert-True (Test-Path -LiteralPath $autoPushGuard -PathType Leaf) 'Missing auto_push_guard.ps1.'
Assert-True (Test-Path -LiteralPath $hiddenLauncher -PathType Leaf) 'Missing hidden Downloads launcher.'
Assert-True (Test-Path -LiteralPath $taskInstaller -PathType Leaf) 'Missing Downloads hot-backup task installer.'

$installerText = Get-Content -LiteralPath $taskInstaller -Raw -Encoding utf8
Assert-True ($installerText -match '(?s)Register-ScheduledTask.+-Force') 'Task installer must be idempotent through forced registration of the audited definition.'
$definition = & $taskInstaller -DefinitionOnly -DailyAt '21:35'
Assert-True ($null -ne $definition) 'Task installer did not return a definition.'
Assert-True ($definition.Actions.Count -eq 1) 'Downloads task must have exactly one action.'
Assert-True ([IO.Path]::GetFileName([string]$definition.Actions[0].Execute) -ieq 'wscript.exe') 'Downloads task must use wscript.exe for a hidden window.'
Assert-True ([string]$definition.Actions[0].Arguments -eq "`"$hiddenLauncher`"") 'Downloads task action must target the repository-relative hidden launcher.'
Assert-True ($definition.Triggers.Count -eq 1 -and $definition.Triggers[0].DaysInterval -eq 1) 'Downloads task must have one daily trigger.'
Assert-True ($definition.Settings.StartWhenAvailable -eq $true) 'Downloads task must catch up after a missed schedule.'
Assert-True ($definition.Settings.RestartCount -eq 3) 'Downloads task must retry three times.'
Assert-True ([string]$definition.Settings.RestartInterval -eq 'PT15M') 'Downloads task retry interval must be 15 minutes.'
Assert-True ([string]$definition.Settings.MultipleInstances -eq 'IgnoreNew') 'Downloads task must ignore overlapping starts.'
Assert-True ([string]$definition.Settings.ExecutionTimeLimit -eq 'PT2H') 'Downloads task execution limit must be two hours.'
Assert-True ($definition.Settings.RunOnlyIfNetworkAvailable -eq $false) 'Downloads task must not depend on network availability.'
Assert-True ($definition.Settings.WakeToRun -eq $false) 'Downloads task must not wake this workstation.'
Assert-True ([string]$definition.Principal.LogonType -eq 'Interactive') 'Downloads task must use the logged-on desktop user token.'
Assert-True ([string]$definition.Principal.RunLevel -eq 'Limited') 'Downloads task does not need elevation.'
$launcherText = Get-Content -LiteralPath $hiddenLauncher -Raw -Encoding utf8
Assert-True ($launcherText -match 'shell\.Run\(cmd,\s*0,\s*True\)') 'Downloads VBS launcher must run PowerShell hidden and wait for its exit code.'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("scripts-backup-automation-tests-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $dirty = New-GitFixture $tempRoot 'dirty-worktree'
    [IO.File]::WriteAllText(
        (Join-Path $dirty.Work 'dirty.txt'),
        "created by auto push`n",
        [Text.UTF8Encoding]::new($false)
    )
    $dirtyExit = Invoke-AutoPush $dirty.Work
    Assert-True ($dirtyExit -eq 0) "Dirty-worktree auto commit/push failed with exit code $dirtyExit."
    Assert-True (-not ((Invoke-Git $dirty.Work @('status', '--porcelain')) -join '')) 'Successful auto push must leave the worktree clean.'
    $dirtyLocal = [string](Invoke-Git $dirty.Work @('rev-parse', 'HEAD') | Select-Object -First 1)
    Assert-True ((Get-RemoteMainOid $dirty.Work) -eq $dirtyLocal) 'Dirty-worktree auto push did not make the fresh remote OID equal local HEAD.'

    $preStaged = New-GitFixture $tempRoot 'pre-staged-user-change'
    [IO.File]::WriteAllText(
        (Join-Path $preStaged.Work 'user-staged.txt'),
        "user-owned staged change`n",
        [Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $preStaged.Work @('add', '--', 'user-staged.txt')
    $preStagedBefore = (Invoke-Git $preStaged.Work @('diff', '--cached', '--binary')) -join "`n"
    $preStagedRemoteBefore = Get-RemoteMainOid $preStaged.Work
    $preStagedExit = Invoke-AutoPush $preStaged.Work
    Assert-True ($preStagedExit -eq 32) "Pre-staged changes must be refused with exit code 32, got $preStagedExit."
    $preStagedAfter = (Invoke-Git $preStaged.Work @('diff', '--cached', '--binary')) -join "`n"
    Assert-True ($preStagedAfter -eq $preStagedBefore) 'Refusing auto push must preserve the user-owned staged index exactly.'
    Assert-True ((Get-RemoteMainOid $preStaged.Work) -eq $preStagedRemoteBefore) 'Pre-staged user changes must not be pushed.'

    $ahead = New-GitFixture $tempRoot 'ahead-clean'
    Add-Commit $ahead.Work 'ahead.txt' "local ahead`n"
    $aheadExit = Invoke-AutoPush $ahead.Work
    Assert-True ($aheadExit -eq 0) "Clean-ahead auto push failed with exit code $aheadExit."
    $aheadLocal = [string](Invoke-Git $ahead.Work @('rev-parse', 'HEAD') | Select-Object -First 1)
    Assert-True ((Get-RemoteMainOid $ahead.Work) -eq $aheadLocal) 'Clean-ahead auto push did not make the fresh remote OID equal local HEAD.'

    $sensitiveAhead = New-GitFixture $tempRoot 'sensitive-ahead'
    $sensitiveRemoteBefore = Get-RemoteMainOid $sensitiveAhead.Work
    Add-Commit $sensitiveAhead.Work '.env' "safe-looking-but-blocked-path=true`n"
    $sensitiveExit = Invoke-AutoPush $sensitiveAhead.Work
    Assert-True ($sensitiveExit -ne 0) 'Existing ahead commits must still pass the public-repository sensitive-content guard.'
    Assert-True ((Get-RemoteMainOid $sensitiveAhead.Work) -eq $sensitiveRemoteBefore) 'Sensitive existing-ahead commit must not reach the remote.'

    $behind = New-GitFixture $tempRoot 'behind'
    $behindWriter = Join-Path (Split-Path $behind.Work) 'writer'
    & git clone $behind.Remote $behindWriter | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone behind writer.' }
    Invoke-Git $behindWriter @('config', 'user.name', 'Backup Automation Test')
    Invoke-Git $behindWriter @('config', 'user.email', 'backup-automation-test@example.invalid')
    Add-Commit $behindWriter 'remote.txt' "remote ahead`n"
    Invoke-Git $behindWriter @('push', 'origin', 'main')
    $behindExit = Invoke-AutoPush $behind.Work
    Assert-True ($behindExit -ne 0) 'Behind auto push must fail closed.'

    $diverged = New-GitFixture $tempRoot 'diverged'
    Add-Commit $diverged.Work 'local.txt' "local side`n"
    $divergedWriter = Join-Path (Split-Path $diverged.Work) 'writer'
    & git clone $diverged.Remote $divergedWriter | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone diverged writer.' }
    Invoke-Git $divergedWriter @('config', 'user.name', 'Backup Automation Test')
    Invoke-Git $divergedWriter @('config', 'user.email', 'backup-automation-test@example.invalid')
    Add-Commit $divergedWriter 'remote.txt' "remote side`n"
    Invoke-Git $divergedWriter @('push', 'origin', 'main')
    $divergedExit = Invoke-AutoPush $diverged.Work
    Assert-True ($divergedExit -ne 0) 'Diverged auto push must fail closed.'

    $rejected = New-GitFixture $tempRoot 'push-rejected'
    Add-Commit $rejected.Work 'rejected.txt' "must not push`n"
    Write-GitHook $rejected.Remote 'pre-receive' "#!/bin/sh`necho rejected-by-test >&2`nexit 1`n"
    $rejectedExit = Invoke-AutoPush $rejected.Work
    Assert-True ($rejectedExit -ne 0) 'A rejected git push must return a nonzero exit code.'

    $rewound = New-GitFixture $tempRoot 'post-receive-rewind'
    $remoteBefore = Get-RemoteMainOid $rewound.Work
    Add-Commit $rewound.Work 'rewound.txt' "server rewinds after accepting`n"
    Write-GitHook $rewound.Remote 'post-receive' "#!/bin/sh`nwhile read old new ref; do`n  git update-ref ""`$ref"" ""`$old"" ""`$new""`ndone`nexit 0`n"
    $rewoundExit = Invoke-AutoPush $rewound.Work
    Assert-True ($rewoundExit -ne 0) 'Auto push must fail if a fresh remote read does not equal local HEAD after an apparently successful push.'
    Assert-True ((Get-RemoteMainOid $rewound.Work) -eq $remoteBefore) 'Post-receive rewind fixture did not restore the old remote OID.'
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host 'OK auto-push and Downloads scheduled-task automation tests passed.'
