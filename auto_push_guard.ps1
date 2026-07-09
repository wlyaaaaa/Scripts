$ErrorActionPreference = 'Stop'

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

$names = @(git diff --cached --name-only)
foreach ($name in $names) {
    $normalized = $name -replace '\\', '/'
    foreach ($pattern in $blockedNamePatterns) {
        if ($normalized -match $pattern) {
            Write-Error "Blocked staged sensitive file path: $name"
            exit 10
        }
    }
}

$diff = git diff --cached -- .
$addedLines = @($diff -split "`n" | Where-Object {
    $_ -match '^\+' -and $_ -notmatch '^\+\+\+'
})

foreach ($pattern in $blockedContentPatterns) {
    $hit = $addedLines | Select-String -Pattern $pattern | Select-Object -First 1
    if ($hit) {
        Write-Error "Blocked staged sensitive content pattern: $pattern"
        exit 11
    }
}

exit 0
