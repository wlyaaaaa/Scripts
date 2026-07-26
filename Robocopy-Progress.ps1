#requires -Version 7.0

# Shared robocopy scan / progress engine for Codex backup scripts.
# Dot-source this file; it defines Get-RobocopyScan, Invoke-RobocopyWithProgress,
# Get-MirrorExtras and small formatting helpers.
# Robocopy console output on this machine is localized (zh-CN) and emitted in the
# system OEM codepage, so all capture goes through System.Diagnostics.Process with
# explicit OEM decoding. Parsers accept both zh-CN and en-US tokens.

$script:RobocopyOemEncoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

function Format-ByteSize {
  param([double]$Bytes)
  if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
  if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
  if ($Bytes -ge 1KB) { return '{0:N1} KB' -f ($Bytes / 1KB) }
  return ('{0:N0} B' -f $Bytes)
}

function Format-DurationText {
  param([double]$Seconds)
  if ($Seconds -lt 0) { return '--:--' }
  $ts = [TimeSpan]::FromSeconds([math]::Round($Seconds))
  if ($ts.TotalHours -ge 1) { return '{0}:{1:mm}:{2:ss}' -f [int]$ts.TotalHours, $ts, $ts }
  return '{0:mm}:{1:ss}' -f $ts, $ts
}

function ConvertTo-RobocopyFailureCategory {
  param([int]$Code)
  switch ($Code) {
    32  { return 'file_in_use' }
    5   { return 'access_denied' }
    112 { return 'disk_full' }
    3   { return 'path_not_found' }
    267 { return 'path_invalid' }
    default { return 'other' }
  }
}

function ConvertFrom-RobocopyOutputLine {
  # Returns $null for noise lines, or a parsed record:
  #   Kind: 'copy' | 'extra' | 'dir' | 'error' | 'summary'
  param([AllowNull()][string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

  $m = [regex]::Match($Line, '(?:错误|ERROR)\s+(?<code>\d+)\s+\(0x[0-9A-Fa-f]{8}\)\s+(?<msg>.+)$')
  if ($m.Success) {
    $path = $null
    $pm = [regex]::Match($m.Groups['msg'].Value, '(?<path>[A-Za-z]:\\.+?)\s*$')
    if ($pm.Success) { $path = $pm.Groups['path'].Value }
    $code = [int]$m.Groups['code'].Value
    return [pscustomobject]@{
      Kind = 'error'; Code = $code; Category = (ConvertTo-RobocopyFailureCategory -Code $code)
      Message = $m.Groups['msg'].Value; Path = $path; Raw = $Line
    }
  }

  $sm = [regex]::Match($Line, '^\s*(?<row>目录|文件|字节|Dirs|Files|Bytes)\s*:\s*(?<nums>[\d][\d\s]*)$')
  if ($sm.Success) {
    $nums = @([regex]::Matches($sm.Groups['nums'].Value, '\d+') | ForEach-Object { [int64]$_.Value })
    if ($nums.Count -ge 6) {
      $rowName = $sm.Groups['row'].Value
      $key = switch -Regex ($rowName) { '目录|Dirs' { 'Dirs' } '文件|Files' { 'Files' } default { 'Bytes' } }
      return [pscustomobject]@{
        Kind = 'summary'; Row = $key
        Total = $nums[0]; Copied = $nums[1]; Skipped = $nums[2]
        Mismatch = $nums[3]; Failed = $nums[4]; Extras = $nums[5]
      }
    }
    return $null
  }

  if ($Line.IndexOf("`t") -lt 0) { return $null }
  $parts = @($Line -split "`t" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  if ($parts.Count -lt 2) { return $null }
  $num = 0L
  if (-not [int64]::TryParse($parts[1], [ref]$num)) { return $null }
  $class = $parts[0]
  $name = if ($parts.Count -ge 3) { $parts[$parts.Count - 1] } else { $null }
  $isDir = ($class -match '目录|Dir')
  $isExtra = ($class -match '多余|EXTRA')
  $isCopyClass = ($class -match '新文件|已更改|较新|较旧|New File|Newer|Older|Changed|Tweaked|调整|Mismatched|不匹配')
  if ($isDir) { $kind = 'dir' }
  elseif ($isExtra) { $kind = 'extra' }
  elseif ($isCopyClass) { $kind = 'copy' }
  else { return $null }
  return [pscustomobject]@{ Kind = $kind; Class = $class; Size = $num; Name = $name; Raw = $Line }
}

function Get-RobocopyScan {
  <# List-only (/L) scan. Returns would-be copy totals (files/bytes) plus the
     authoritative summary table. Never mutates source or destination. #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string[]]$RobocopyArgs = @()
  )
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'robocopy'
  foreach ($a in @($Source, $Destination) + $RobocopyArgs + @('/L', '/BYTES', '/NJH', '/NP', '/R:0', '/W:0')) {
    $psi.ArgumentList.Add($a)
  }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = $script:RobocopyOemEncoding

  $p = [Diagnostics.Process]::Start($psi)
  $stderrTask = $p.StandardError.ReadToEndAsync()
  $copyFiles = 0L; $copyBytes = 0L
  $summary = @{}
  while (-not $p.StandardOutput.EndOfStream) {
    $rec = ConvertFrom-RobocopyOutputLine -Line $p.StandardOutput.ReadLine()
    if ($null -eq $rec) { continue }
    if ($rec.Kind -eq 'copy') { $copyFiles++; $copyBytes += [math]::Max([int64]0, $rec.Size) }
    elseif ($rec.Kind -eq 'summary') { $summary[$rec.Row] = $rec }
  }
  $p.WaitForExit()
  $stderr = $stderrTask.GetAwaiter().GetResult()

  return [pscustomobject]@{
    Source = $Source; Destination = $Destination
    ExitCode = $p.ExitCode; Stderr = $stderr
    CopyFiles = $copyFiles; CopyBytes = $copyBytes
    Summary = $summary
  }
}

function Get-MirrorExtras {
  <# Pure-PowerShell mirror diff: destination-relative files/dirs that no longer
     exist in the source. Reparse handling mirrors robocopy /XJ exactly: junctions
     and directory symbolic links are skipped; other reparse dirs (cloud-drive
     placeholder folders etc.) are traversed like ordinary directories. Any
     enumeration error aborts the mirror by throwing, so a partially readable
     source can never produce false extras. Exclusion name patterns are applied
     to both sides, matching robocopy /XF behavior. #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string[]]$ExcludeNamePatterns = @(),
    [string[]]$ExcludeDirPatterns = @()
  )

  function Get-TreeEntries([string]$Root, [string[]]$SkipDirPatterns) {
    $files = [Collections.Generic.List[string]]::new()
    $dirs = [Collections.Generic.List[string]]::new()
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
      $dir = $stack.Pop()
      $entries = @([IO.Directory]::EnumerateFileSystemEntries($dir))
      foreach ($entry in $entries) {
        $attr = [IO.File]::GetAttributes($entry)
        $isDir = (($attr -band [IO.FileAttributes]::Directory) -ne 0)
        $isReparse = (($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isDir) {
          $leaf = [IO.Path]::GetFileName($entry)
          $skipDir = $false
          foreach ($pat in $SkipDirPatterns) { if ($leaf -like $pat) { $skipDir = $true; break } }
          if ($skipDir) { continue }
        }
        if ($isReparse -and $isDir) {
          # robocopy /XJ skips junctions and directory symbolic links, but it
          # traverses other reparse dirs (e.g. cloud-drive placeholder folders)
          # as ordinary directories. Mirror that exact behavior so the extras
          # diff never fights the copier.
          $linkType = $null
          try { $linkType = (Get-Item -LiteralPath $entry -Force).LinkType } catch { $linkType = $null }
          if ($linkType -in @('Junction', 'SymbolicLink')) { continue }
        }
        $rel = $entry.Substring($Root.TrimEnd('\').Length).TrimStart('\')
        if ($isDir) {
          $dirs.Add($rel); $stack.Push($entry)
        } else {
          $files.Add($rel)
        }
      }
    }
    return @{ Files = $files; Dirs = $dirs }
  }

  function Test-ExcludedName([string]$RelativePath, [string[]]$Patterns) {
    $leaf = [IO.Path]::GetFileName($RelativePath.TrimEnd('\'))
    foreach ($pat in $Patterns) { if ($leaf -like $pat) { return $true } }
    return $false
  }

  $srcTree = Get-TreeEntries -Root $Source -SkipDirPatterns $ExcludeDirPatterns
  $dstTree = if (Test-Path -LiteralPath $Destination -PathType Container) {
    Get-TreeEntries -Root $Destination -SkipDirPatterns $ExcludeDirPatterns
  } else {
    @{ Files = [Collections.Generic.List[string]]::new(); Dirs = [Collections.Generic.List[string]]::new() }
  }

  $srcFiles = @{}
  foreach ($f in $srcTree.Files) { if (-not (Test-ExcludedName -RelativePath $f -Patterns $ExcludeNamePatterns)) { $srcFiles[$f] = $true } }
  $srcDirs = @{}
  foreach ($d in $srcTree.Dirs) { $srcDirs[$d] = $true }

  $extraFiles = [Collections.Generic.List[string]]::new()
  foreach ($f in $dstTree.Files) {
    if ((Test-ExcludedName -RelativePath $f -Patterns $ExcludeNamePatterns)) { continue }
    if (-not $srcFiles.ContainsKey($f)) { $extraFiles.Add($f) }
  }
  $extraDirs = [Collections.Generic.List[string]]::new()
  foreach ($d in $dstTree.Dirs) {
    if (-not $srcDirs.ContainsKey($d)) { $extraDirs.Add($d) }
  }

  return [pscustomobject]@{
    ExtraFiles = $extraFiles.ToArray()
    ExtraDirs = $extraDirs.ToArray()
    SourceFileCount = $srcTree.Files.Count
    DestinationFileCount = $dstTree.Files.Count
  }
}

function Invoke-RobocopyWithProgress {
  <# Runs robocopy for real, streaming parsed progress:
     - Write-Progress bar: percent by bytes, files done/total, rolling + average
       speed, ETA, current item. Disabled with -Quiet (scheduled/hidden runs).
     - Collects localized ERROR lines (e.g. code 32 file-in-use, 5 access-denied)
       into FailedFiles instead of aborting; caller decides exit-code policy.
     - Returns the authoritative localized summary table when present. #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [string[]]$RobocopyArgs = @(),
    [string]$Activity = 'Robocopy',
    [int64]$TotalFiles = 0,
    [int64]$TotalBytes = 0,
    [switch]$Quiet,
    [int]$ProgressId = 0,
    [int]$ProgressParentId = -1
  )

  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'robocopy'
  foreach ($a in @($Source, $Destination) + $RobocopyArgs + @('/BYTES', '/NJH', '/NP')) {
    $psi.ArgumentList.Add($a)
  }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = $script:RobocopyOemEncoding

  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  $p = [Diagnostics.Process]::Start($psi)
  $stderrTask = $p.StandardError.ReadToEndAsync()

  $filesDone = 0L; $bytesDone = 0L; $extrasSeen = 0L
  $copyIndex = @{}
  $failed = [Collections.Generic.List[object]]::new()
  $failedIndex = @{}
  $summary = @{}
  $samples = [Collections.Generic.List[object]]::new()
  $currentName = ''
  $lastProgressAt = [DateTime]::MinValue

  while (-not $p.StandardOutput.EndOfStream) {
    $rec = ConvertFrom-RobocopyOutputLine -Line $p.StandardOutput.ReadLine()
    if ($null -eq $rec) { continue }
    switch ($rec.Kind) {
      'copy' {
        # Robocopy re-emits the file line on every retry attempt, so progress
        # counts unique (size + relative name) completions, not raw lines.
        $ckey = '{0}|{1}' -f $rec.Size, $rec.Name
        if (-not $copyIndex.ContainsKey($ckey)) {
          $copyIndex[$ckey] = $true
          $filesDone++; $bytesDone += [math]::Max([int64]0, $rec.Size)
          $samples.Add([pscustomobject]@{ Elapsed = $stopwatch.Elapsed.TotalSeconds; Bytes = $bytesDone })
          $cutoff = $stopwatch.Elapsed.TotalSeconds - 20
          while ($samples.Count -gt 2 -and $samples[0].Elapsed -lt $cutoff) { $samples.RemoveAt(0) }
        }
        if ($rec.Name) { $currentName = $rec.Name }
      }
      'extra' { $extrasSeen++; if ($rec.Name) { $currentName = $rec.Name } }
      'error' {
        $fkey = if ($rec.Path) { $rec.Path } else { $rec.Raw }
        if (-not $failedIndex.ContainsKey($fkey)) { $failedIndex[$fkey] = $true; $failed.Add($rec) }
      }
      'summary' { $summary[$rec.Row] = $rec }
    }

    if (-not $Quiet) {
      $now = [DateTime]::UtcNow
      if (($now - $lastProgressAt).TotalMilliseconds -ge 250) {
        $lastProgressAt = $now
        $elapsed = $stopwatch.Elapsed.TotalSeconds
        $avgSpeed = if ($elapsed -gt 0.5) { $bytesDone / $elapsed } else { 0 }
        $windowSpeed = $avgSpeed
        if ($samples.Count -ge 2) {
          $span = $samples[$samples.Count - 1].Elapsed - $samples[0].Elapsed
          if ($span -gt 1) { $windowSpeed = ($samples[$samples.Count - 1].Bytes - $samples[0].Bytes) / $span }
        }
        $pct = 0
        if ($TotalBytes -gt 0) { $pct = [math]::Min(100, [math]::Floor(100.0 * $bytesDone / $TotalBytes)) }
        elseif ($TotalFiles -gt 0) { $pct = [math]::Min(100, [math]::Floor(100.0 * $filesDone / $TotalFiles)) }
        $remainingBytes = [math]::Max([int64]0, $TotalBytes - $bytesDone)
        $etaSeconds = if ($windowSpeed -gt 0 -and $TotalBytes -gt 0) { $remainingBytes / $windowSpeed } else { -1 }
        $status = '{0}/{1} 个文件 | 估算 {2}/{3} | 当前 {4}/s 平均 {5}/s' -f
          $filesDone, $TotalFiles,
          (Format-ByteSize -Bytes $bytesDone), (Format-ByteSize -Bytes $TotalBytes),
          (Format-ByteSize -Bytes $windowSpeed), (Format-ByteSize -Bytes $avgSpeed)
        $progressParams = @{
          Activity = $Activity; Id = $ProgressId; Status = $status
          PercentComplete = $pct; CurrentOperation = $currentName
        }
        if ($ProgressParentId -ge 0) { $progressParams['ParentId'] = $ProgressParentId }
        if ($etaSeconds -ge 0) { $progressParams['SecondsRemaining'] = [int]$etaSeconds }
        Write-Progress @progressParams
      }
    }
  }
  $p.WaitForExit()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  $stopwatch.Stop()

  if (-not $Quiet) {
    $completeParams = @{ Activity = $Activity; Id = $ProgressId; Completed = $true }
    if ($ProgressParentId -ge 0) { $completeParams['ParentId'] = $ProgressParentId }
    Write-Progress @completeParams
  }

  $duration = $stopwatch.Elapsed.TotalSeconds
  # During a copy Robocopy emits a file line before its final result, so the live
  # bar is necessarily an estimate. The final receipt must use Robocopy's summary
  # counters, which exclude files/bytes that ultimately failed.
  $copiedCount = if ($summary.ContainsKey('Files')) {
    [int64]$summary['Files'].Copied
  } else {
    [math]::Max([int64]0, $filesDone - $failed.Count)
  }
  $copiedBytes = if ($summary.ContainsKey('Bytes')) {
    [int64]$summary['Bytes'].Copied
  } else {
    $bytesDone
  }
  return [pscustomobject]@{
    Source = $Source; Destination = $Destination
    ExitCode = $p.ExitCode; Stderr = $stderr
    FilesCopied = $copiedCount; BytesCopied = $copiedBytes; ExtrasSeen = $extrasSeen
    FilesAttempted = $filesDone; BytesAttempted = $bytesDone
    FailedFiles = $failed.ToArray()
    Summary = $summary
    DurationSeconds = [math]::Round($duration, 3)
    AvgBytesPerSec = if ($duration -gt 0) { [math]::Round($copiedBytes / $duration, 0) } else { 0 }
    ProgressAccuracy = 'estimated_during_copy_authoritative_at_completion'
    CompletedUtc = [DateTimeOffset]::UtcNow.ToString('o')
  }
}
