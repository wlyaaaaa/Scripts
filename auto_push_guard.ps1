param(
    [switch]$VerifyRemote
)

$ErrorActionPreference = 'Stop'

function Invoke-Git([string[]]$Arguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $PSScriptRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

function Get-LocalHeadOid {
    return ([string](Invoke-Git @('rev-parse', '--verify', 'HEAD') | Select-Object -First 1)).Trim()
}

function Get-FreshRemoteMainOid {
    $line = ([string](Invoke-Git @('ls-remote', '--exit-code', 'origin', 'refs/heads/main') | Select-Object -First 1)).Trim()
    if ($line -notmatch '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})\s+refs/heads/main$') {
        throw "Unable to parse fresh origin/main OID from: $line"
    }
    return $Matches[1].ToLowerInvariant()
}

if ($VerifyRemote) {
    $localOid = (Get-LocalHeadOid).ToLowerInvariant()
    $remoteOid = Get-FreshRemoteMainOid
    if ($remoteOid -ne $localOid) {
        Write-Error "Fresh origin/main OID $remoteOid does not equal local HEAD $localOid."
        exit 22
    }
    Write-Host "[OK] fresh origin/main OID equals local HEAD: $localOid"
    exit 0
}

$blockedNamePatterns = @(
    '(^|/)\.env($|\.)',
    '(^|/).*\.pem$',
    '(^|/).*\.key$',
    '(^|/).*\.p12$',
    '(^|/).*\.pfx$',
    '(^|/)id_rsa$',
    '(^|/)id_ed25519$'
)

$sensitiveWords = @(
    ('client' + '_secret'),
    ('api' + '[_-]?' + 'key'),
    ('access' + '[_-]?' + 'token'),
    ('refresh' + '[_-]?' + 'token'),
    ('pass' + 'word')
)

$blockedContentPatterns = @(
    ('BEGIN [A-Z ]*PRIVATE ' + 'KEY'),
    ('\bghp_' + '[A-Za-z0-9_]{20,}'),
    ('\bsk-' + '[A-Za-z0-9_-]{20,}'),
    ('\bAKIA' + '[0-9A-Z]{16}\b'),
    ('\bxox' + '[baprs]-[A-Za-z0-9-]{20,}'),
    ('(?i)\b(' + ($sensitiveWords -join '|') + ')\s*[:=]')
)

function Assert-SafeGitDelta(
    [string[]]$Names,
    [string]$Diff,
    [string]$Context
) {
    foreach ($name in $Names) {
        $normalized = $name -replace '\\', '/'
        foreach ($pattern in $blockedNamePatterns) {
            if ($normalized -match $pattern) {
                Write-Error "Blocked sensitive file path in $Context`: $name"
                exit 10
            }
        }
    }

    $addedLines = @($Diff -split "`n" | Where-Object {
        $_ -match '^\+' -and $_ -notmatch '^\+\+\+'
    })
    foreach ($pattern in $blockedContentPatterns) {
        $hit = $addedLines | Select-String -Pattern $pattern | Select-Object -First 1
        if ($hit) {
            Write-Error "Blocked sensitive content pattern in $Context`: $pattern"
            exit 11
        }
    }
}

$branch = ([string](Invoke-Git @('symbolic-ref', '--quiet', '--short', 'HEAD') | Select-Object -First 1)).Trim()
if ($branch -ne 'main') {
    Write-Error "Auto push is restricted to branch main; current branch is $branch."
    exit 12
}

$names = @(Invoke-Git @('diff', '--cached', '--name-only'))
$diff = (Invoke-Git @('diff', '--cached', '--', '.')) -join "`n"
Assert-SafeGitDelta -Names $names -Diff $diff -Context 'staged changes'

Invoke-Git @(
    'fetch',
    '--no-tags',
    'origin',
    '+refs/heads/main:refs/remotes/origin/main'
) | Out-Null
$countsLine = ([string](Invoke-Git @(
    'rev-list',
    '--left-right',
    '--count',
    'HEAD...refs/remotes/origin/main'
)) | Select-Object -First 1).Trim()
$parts = @($countsLine -split '\s+')
if ($parts.Count -ne 2) {
    throw "Unable to parse ahead/behind counts from: $countsLine"
}
$ahead = [int]$parts[0]
$behind = [int]$parts[1]
if ($ahead -gt 0 -and $behind -gt 0) {
    Write-Error "Local main has diverged from origin/main (ahead=$ahead, behind=$behind). Resolve manually."
    exit 21
}
if ($behind -gt 0) {
    Write-Error "Local main is behind origin/main by $behind commit(s). Integrate remote changes before auto push."
    exit 20
}
if ($ahead -gt 0) {
    $aheadRange = 'refs/remotes/origin/main..HEAD'
    $aheadNames = @(Invoke-Git @('diff', '--name-only', $aheadRange))
    $aheadDiff = (Invoke-Git @('diff', '--unified=0', $aheadRange, '--', '.')) -join "`n"
    Assert-SafeGitDelta -Names $aheadNames -Diff $aheadDiff -Context 'existing ahead commits'
}

Write-Host "[OK] Git preflight passed (ahead=$ahead, behind=$behind)."
exit 0
