#requires -Version 7.0

param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$enginePath = Join-Path $repoRoot 'Robocopy-Progress.ps1'
$downloadsScript = Join-Path $repoRoot 'Sync-DownloadsToG.ps1'
$documentsScript = Join-Path $repoRoot 'Sync-DocumentsToG.ps1'
$downloadsInstaller = Join-Path $repoRoot 'Install-DownloadsHotBackupTask.ps1'
$documentsInstaller = Join-Path $repoRoot 'Install-DocumentsHotBackupTask.ps1'
$downloadsLauncher = Join-Path $repoRoot 'Sync-DownloadsToG-Hidden.vbs'
$documentsLauncher = Join-Path $repoRoot 'Sync-DocumentsToG-Hidden.vbs'
$downloadsBat = Join-Path $repoRoot 'Sync-DownloadsToG.bat'
$documentsBat = Join-Path $repoRoot 'Sync-DocumentsToG.bat'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Invoke-BackupChild {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

foreach ($path in @(
    $enginePath, $downloadsScript, $documentsScript,
    $downloadsInstaller, $documentsInstaller,
    $downloadsLauncher, $documentsLauncher,
    $downloadsBat, $documentsBat
)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "required backup entry exists: $path"
}

foreach ($path in @($enginePath, $downloadsScript, $documentsScript)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -match '(?m)^#requires -Version 7\.0\s*$') "$path explicitly requires PowerShell 7"
    [void][scriptblock]::Create($text)
}

foreach ($path in @($downloadsLauncher, $documentsLauncher)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -notmatch '(?i)exe\s*=\s*"powershell\.exe"') "$path does not silently fall back to incompatible Windows PowerShell"
    Assert-True ($text -match 'WScript\.Quit') "$path propagates a deterministic exit code"
}

$documentsLauncherText = Get-Content -LiteralPath $documentsLauncher -Raw -Encoding utf8
foreach ($preciseSaveRoot in @(
    '\Saved Games',
    '\userdata',
    '\11bitstudios\Frostpunk2\Steam\Saved\SaveGames',
    '\11bitstudios\Frostpunk2Beta\Steam\Saved\SaveGames'
)) {
    Assert-True (
        $documentsLauncherText.Contains(
            $preciseSaveRoot,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) "Documents owner includes precise local-save root: $preciseSaveRoot"
}
Assert-True (
    $documentsLauncherText -match
        'HKCU\\Software\\Valve\\Steam\\SteamPath'
) 'Steam userdata source resolves the live Steam install root'
Assert-True (
    $documentsLauncherText -notmatch
        'RunDocumentsOwner\(\s*_\s*\r?\n\s*localAppData\s*,'
) 'Documents owner never backs up the whole LocalAppData root'
Assert-True (
    $documentsLauncherText -match
        'G:\\80_Backup\\Documents\\_SavedGames\\SteamUserdata'
) 'Steam userdata remains inside the existing Documents backup tree'
Assert-True (
    $documentsLauncherText -match
        'G:\\80_Backup\\Documents\\_SavedGames\\AppData\\Frostpunk2'
) 'precise AppData saves remain inside the existing Documents backup tree'
foreach ($mediaRoot in @('Pictures', 'Music', 'Videos', 'Media')) {
    Assert-True (
        $documentsLauncherText -match
            [regex]::Escape("E:\$mediaRoot")
    ) "Documents task includes the $mediaRoot known folder"
    Assert-True (
        $documentsLauncherText -match
            [regex]::Escape(
                "G:\80_Backup\PersonalMedia\$mediaRoot"
            )
    ) "$mediaRoot uses the single PersonalMedia backup tree"
}
Assert-True (
    @(
        [regex]::Matches(
            $documentsLauncherText,
            'G:\\80_Backup\\PersonalMedia\\'
        )
    ).Count -eq 4
) 'PersonalMedia has exactly four independently receipted roots'
Assert-True (
    $documentsLauncherText -match
        [regex]::Escape(
            'G:\80_Backup\ControlPlane\personal-media-media-hot-last.json'
        )
) 'E:\Media has an independent Documents-owner receipt'
$mediaOwnerBlock = [regex]::Match(
    $documentsLauncherText,
    '(?is)If\s+fso\.FolderExists\("E:\\Media"\)\s+Then(?<body>.*?)End\s+If'
)
Assert-True (
    $mediaOwnerBlock.Success
) 'missing E:\Media is skipped by the existing owner gate'
Assert-True (
    $mediaOwnerBlock.Groups['body'].Value -match
        'RunDocumentsOwner\s*\(' -and
    $mediaOwnerBlock.Groups['body'].Value -match
        'If\s+exitCode\s+<>\s+0\s+Then\s+WScript\.Quit\s+exitCode'
) 'E:\Media participates in the existing serial failure gate'
foreach ($personalRoot in @(
    [pscustomobject]@{
        Source = 'E:\Archive'
        Destination =
            'G:\80_Backup\Documents\_PersonalRoots\Archive'
        Receipt =
            'G:\80_Backup\ControlPlane\personal-root-archive-hot-last.json'
    },
    [pscustomobject]@{
        Source = 'E:\ClineAgent'
        Destination =
            'G:\80_Backup\Documents\_PersonalRoots\ClineAgent'
        Receipt =
            'G:\80_Backup\ControlPlane\personal-root-cline-agent-hot-last.json'
    }
)) {
    Assert-True (
        $documentsLauncherText.Contains(
            [string]$personalRoot.Source,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $documentsLauncherText.Contains(
            [string]$personalRoot.Destination,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $documentsLauncherText.Contains(
            [string]$personalRoot.Receipt,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) "Documents owner protects personal loose root: $($personalRoot.Source)"
}
Assert-True (
    $documentsLauncherText.Contains(
        'E:\DockerBackup\images',
        [StringComparison]::OrdinalIgnoreCase
    ) -and
    $documentsLauncherText.Contains(
        'G:\80_Backup\Docker\images',
        [StringComparison]::OrdinalIgnoreCase
    ) -and
    $documentsLauncherText.Contains(
        'G:\80_Backup\ControlPlane\docker-images-hot-last.json',
        [StringComparison]::OrdinalIgnoreCase
    )
) 'Documents owner also protects the bounded G-only custom-image fallback'

$downloadsLauncherText = Get-Content -LiteralPath $downloadsLauncher `
    -Raw -Encoding utf8
Assert-True (
    -not ($downloadsLauncherText.ToCharArray() | Where-Object {
        [int]$_ -gt 127
    }) -and
    $downloadsLauncherText -match
        'cnDownloads\s*=\s*ChrW\(&H4E0B\)\s*&\s*ChrW\(&H8F7D\)' -and
    $downloadsLauncherText.Contains(
        'alternateSource = "E:\" & cnDownloads',
        [StringComparison]::Ordinal
    ) -and
    $downloadsLauncherText -match
        'alternateDestination\s*=\s*downloadsDestination\s*&' -and
    $downloadsLauncherText -match
        [regex]::Escape(
            'G:\80_Backup\ControlPlane\downloads-cn-hot-last.json'
    )
) 'Downloads owner constructs Chinese paths without encoding-sensitive VBS literals'
$pathAssignmentLines = @(
    $downloadsLauncherText -split "`r?`n" |
        Where-Object {
            $_ -match '^(cnDownloads|cnAndInstallPackage|downloadsDestination|alternateSource|alternateDestination)\s*='
        }
)
Assert-True ($pathAssignmentLines.Count -eq 5) `
    'Downloads launcher exposes one closed set of ASCII-only path assignments'
$pathProbe = Join-Path ([IO.Path]::GetTempPath()) (
    'downloads-vbs-path-probe-{0}.vbs' -f [guid]::NewGuid().ToString('N')
)
try {
    $probeText = @(
        $pathAssignmentLines
        'Function CodeUnits(value)'
        '    result = ""'
        '    For index = 1 To Len(value)'
        '        If index > 1 Then result = result & ","'
        '        code = AscW(Mid(value, index, 1))'
        '        If code < 0 Then code = code + 65536'
        '        result = result & Hex(code)'
        '    Next'
        '    CodeUnits = result'
        'End Function'
        'WScript.Echo CodeUnits(alternateSource)'
        'WScript.Echo CodeUnits(downloadsDestination)'
        'WScript.Echo CodeUnits(alternateDestination)'
    ) -join "`r`n"
    [IO.File]::WriteAllText(
        $pathProbe,
        $probeText,
        [Text.Encoding]::ASCII
    )
    $pathProbeOutput = @(
        & "$env:SystemRoot\System32\cscript.exe" //nologo $pathProbe
    )
    $pathProbeExit = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $pathProbe -Force -ErrorAction SilentlyContinue
}
Assert-True (
    $pathProbeExit -eq 0 -and
    $pathProbeOutput.Count -eq 3 -and
    [string]$pathProbeOutput[0] -ceq (
        ('E:\下载'.ToCharArray() | ForEach-Object {
            '{0:X}' -f [int]$_
        }) -join ','
    ) -and
    [string]$pathProbeOutput[1] -ceq (
        ('G:\80_Backup\03_下载与安装包'.ToCharArray() | ForEach-Object {
            '{0:X}' -f [int]$_
        }) -join ','
    ) -and
    [string]$pathProbeOutput[2] -ceq (
        ((
                'G:\80_Backup\03_下载与安装包\_AlternateRoots\下载'
            ).ToCharArray() | ForEach-Object {
                '{0:X}' -f [int]$_
            }) -join ','
    )
) 'Windows Script Host resolves the ASCII-only launcher assignments to exact Unicode paths'
Assert-True (
    [regex]::Matches(
        $downloadsLauncherText,
        'exitCode\s*=\s*RunDownloadsOwner\s*\('
    ).Count -eq 2 -and
    $downloadsLauncherText -match
        'If\s+exitCode\s+<>\s+0\s+Then\s+WScript\.Quit\s+exitCode'
) 'both Downloads roots share one serial fail-closed owner task'
Assert-True (
    $documentsLauncherText -notmatch '(?i)\bH:\\'
) 'Documents owner never writes H'

foreach ($path in @($downloadsBat, $documentsBat)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-True ($text -notmatch '(?i)powershell\.exe') "$path does not silently fall back to incompatible Windows PowerShell"
}

$downloadsDefinition = & $downloadsInstaller -DefinitionOnly
$documentsDefinition = & $documentsInstaller -DefinitionOnly
foreach ($item in @(
    [pscustomobject]@{ Name = 'Downloads'; Definition = $downloadsDefinition },
    [pscustomobject]@{ Name = 'Documents'; Definition = $documentsDefinition }
)) {
    $start = ([datetimeoffset]$item.Definition.Triggers[0].StartBoundary).ToLocalTime()
    Assert-True ($start.Hour -eq 21 -and $start.Minute -eq 35) "$($item.Name) hot backup defaults to 21:35"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hot-backup-core-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $source = Join-Path $tempRoot 'source'
    $destination = Join-Path $tempRoot 'destination'
    $quarantine = Join-Path $tempRoot 'quarantine'
    $control = Join-Path $tempRoot 'control'
    $logs = Join-Path $tempRoot 'logs'
    foreach ($path in @($source, $destination, $quarantine, $control, $logs)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    [IO.File]::WriteAllText((Join-Path $source 'current.txt'), "current`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $destination 'deleted-at-source.txt'), "stale`n", [Text.UTF8Encoding]::new($false))
    $receipt = Join-Path $control 'downloads.json'
    $common = @(
        '-Source', $source,
        '-Destination', $destination,
        '-QuarantineRoot', $quarantine,
        '-ReceiptPath', $receipt,
        '-LogDir', $logs,
        '-MinimumFreeBytes', '0',
        '-MutexName', "Local\HotBackupCore-$PID",
        '-Quiet',
        '-QuarantineFileThreshold', '0',
        '-QuarantineRatioThreshold', '0'
    )

    $first = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    Assert-True ($first.ExitCode -eq 0) "first incremental run succeeds: $($first.Output -join ' | ')"
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'current.txt') -PathType Leaf) 'new source file is copied'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'deleted-at-source.txt'))) 'source deletion leaves the hot destination'
    $quarantined = @(Get-ChildItem -LiteralPath $quarantine -Recurse -File -Filter 'deleted-at-source.txt')
    Assert-True ($quarantined.Count -eq 1) 'source deletion enters quarantine even above the legacy threshold in quiet mode'

    $second = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    Assert-True ($second.ExitCode -eq 0) "second incremental run succeeds: $($second.Output -join ' | ')"
    $secondReceipt = Get-Content -LiteralPath $receipt -Raw -Encoding utf8 | ConvertFrom-Json -Depth 10
    Assert-True ([int64]$secondReceipt.copy_files -eq 0) 'unchanged second run copies zero files'
    Assert-True ($secondReceipt.status -eq 'complete') 'unchanged second run is complete'
    Assert-True (
        $null -ne $secondReceipt.failed_files -and
        @($secondReceipt.failed_files).Count -eq 0
    ) 'successful receipt records an explicit empty failed-files closure'

    $lockedPath = Join-Path $source 'locked.txt'
    [IO.File]::WriteAllText($lockedPath, "locked`n", [Text.UTF8Encoding]::new($false))
    $lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $lockedRun = Invoke-BackupChild -Script $downloadsScript -Arguments $common
    } finally {
        $lock.Dispose()
    }
    Assert-True ($lockedRun.ExitCode -eq 0) "file-in-use does not abort the backup set: $($lockedRun.Output -join ' | ')"
    $lockedReceipt = Get-Content -LiteralPath $receipt -Raw -Encoding utf8 | ConvertFrom-Json -Depth 10
    Assert-True ($lockedReceipt.status -eq 'success_with_skips') 'file-in-use produces success_with_skips'
    Assert-True (@($lockedReceipt.failed_files | Where-Object category -eq 'file_in_use').Count -ge 1) 'file-in-use is categorized in the receipt'

    $receiptBlocker = Join-Path $control 'receipt-is-a-directory'
    New-Item -ItemType Directory -Path $receiptBlocker | Out-Null
    $badReceiptArgs = @($common)
    $receiptIndex = [array]::IndexOf($badReceiptArgs, '-ReceiptPath')
    $badReceiptArgs[$receiptIndex + 1] = $receiptBlocker
    $badReceipt = Invoke-BackupChild -Script $downloadsScript -Arguments $badReceiptArgs
    Assert-True ($badReceipt.ExitCode -ne 0) 'receipt write failure returns a nonzero task result'

    . $enginePath
    $accessDenied = ConvertFrom-RobocopyOutputLine -Line '2026/07/26 21:35:00 错误 5 (0x00000005) 正在复制文件 C:\fixture\denied.txt'
    Assert-True ($accessDenied.Category -eq 'access_denied') 'access-denied output is categorized'
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

Write-Host 'OK hot-backup core tests passed.'
