$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$helper = Join-Path $scriptDir 'EnvRedaction.ps1'
. $helper

$fakeOpenAiKey = 'sk-' + 'testOnlyNotARealSecret0000000000'
$fakeGitHubToken = 'ghp_' + 'testOnlyNotARealSecret0000000000'
$fakeJwt = 'eyJhbGciOiJIUzI1NiJ9' + '.eyJ0ZXN0IjoiZmFrZSJ9' + '.fakeSignature'

$sample = @(
    'Path: C:\Windows;C:\Tools',
    "OPENAI_API_KEY: $fakeOpenAiKey",
    "GH_TOKEN: $fakeGitHubToken",
    'PLAIN_SETTING: enabled',
    "JWT_SAMPLE: $fakeJwt"
)

$redacted = ConvertTo-CodexRedactedEnvLines -Lines $sample

if ($redacted[0] -ne 'Path: C:\Windows;C:\Tools') {
    throw 'Expected PATH-like value to be preserved.'
}

if ($redacted[1] -ne 'OPENAI_API_KEY: <REDACTED:restore-from-credential-backup-or-rotate>') {
    throw 'Expected API key variable to be redacted by name.'
}

if ($redacted[2] -ne 'GH_TOKEN: <REDACTED:restore-from-credential-backup-or-rotate>') {
    throw 'Expected token variable to be redacted by name.'
}

if ($redacted[3] -ne 'PLAIN_SETTING: enabled') {
    throw 'Expected ordinary setting to be preserved.'
}

if ($redacted[4] -ne 'JWT_SAMPLE: <REDACTED:restore-from-credential-backup-or-rotate>') {
    throw 'Expected JWT-shaped value to be redacted.'
}

$summary = Get-CodexEnvRedactionSummary -Lines $sample
if ($summary.EntryCount -ne 5 -or $summary.SensitiveCount -ne 3) {
    throw "Unexpected summary counts: entries=$($summary.EntryCount), sensitive=$($summary.SensitiveCount)"
}

$formatListSample = @(
    'Name  : Path',
    'Value : C:\Windows;C:\Tools',
    '',
    'Name  : OPENAI_API_KEY',
    "Value : $fakeOpenAiKey",
    '',
    'Name  : PLAIN_SETTING',
    'Value : enabled'
)

$formatListRedacted = ConvertTo-CodexRedactedEnvLines -Lines $formatListSample

if ($formatListRedacted[1] -ne 'Value : C:\Windows;C:\Tools') {
    throw 'Expected Format-List PATH-like value to be preserved.'
}

if ($formatListRedacted[4] -ne 'Value : <REDACTED:restore-from-credential-backup-or-rotate>') {
    throw 'Expected Format-List secret value to be redacted.'
}

if ($formatListRedacted[7] -ne 'Value : enabled') {
    throw 'Expected Format-List ordinary value to be preserved.'
}

$formatListSummary = Get-CodexEnvRedactionSummary -Lines $formatListSample
if ($formatListSummary.EntryCount -ne 3 -or $formatListSummary.SensitiveCount -ne 1) {
    throw "Unexpected Format-List summary counts: entries=$($formatListSummary.EntryCount), sensitive=$($formatListSummary.SensitiveCount)"
}

$wrappedFormatListSample = @(
    'Name  : OPENAI_API_KEY',
    ('Value : ' + $fakeOpenAiKey.Substring(0, 16)),
    ('        ' + $fakeOpenAiKey.Substring(16)),
    '',
    'Name  : LONG_PATH',
    'Value : C:\Windows;C:\Tools;',
    '        E:\Tools\bin'
)

$wrappedFormatListRedacted = ConvertTo-CodexRedactedEnvLines -Lines $wrappedFormatListSample

if ($wrappedFormatListRedacted[1] -ne 'Value : <REDACTED:restore-from-credential-backup-or-rotate>') {
    throw 'Expected wrapped Format-List secret value to be redacted.'
}

if ($wrappedFormatListRedacted[2] -ne '') {
    throw 'Expected wrapped secret continuation line to be removed.'
}

if ($wrappedFormatListRedacted[4] -ne 'Value : C:\Windows;C:\Tools;') {
    throw 'Expected wrapped non-secret first line to be preserved.'
}

if ($wrappedFormatListRedacted[5] -ne '        E:\Tools\bin') {
    throw 'Expected wrapped non-secret continuation line to be preserved.'
}

Write-Output 'EnvRedaction.Tests passed'
