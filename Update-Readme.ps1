# Auto-update README.md: regenerate the file list between markers, then git commit + push.
# ASCII-only source. Chinese in README comes from file data, not from this script.
$ErrorActionPreference = 'SilentlyContinue'
$dir    = $PSScriptRoot
$readme = Join-Path $dir 'README.md'

$files = Get-ChildItem $dir -File |
         Where-Object { $_.Name -ne 'README.md' -and $_.Extension -ne '.tmp' } |
         Sort-Object Name
$rows = @('| File | Size | Modified |', '|------|------|----------|')
foreach ($f in $files) {
    $rows += ('| `{0}` | {1} B | {2} |' -f $f.Name, $f.Length, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
}
$block = ($rows -join "`r`n")

$s = '<!-- FILES:START -->'
$e = '<!-- FILES:END -->'
if (Test-Path $readme) { $content = Get-Content $readme -Raw -Encoding UTF8 } else { $content = '' }

if ($content -match [regex]::Escape($s) -and $content -match [regex]::Escape($e)) {
    $new = [regex]::Replace($content, "(?s)$([regex]::Escape($s)).*?$([regex]::Escape($e))", "$s`r`n$block`r`n$e")
} else {
    $new = $content.TrimEnd() + "`r`n`r`n## File list (auto-generated)`r`n$s`r`n$block`r`n$e`r`n"
}
[IO.File]::WriteAllText($readme, $new, (New-Object System.Text.UTF8Encoding $false))

Push-Location $dir
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git commit -m ("docs: auto-update README file list ({0})" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) | Out-Null
    git push origin main | Out-Null
    Write-Host "  README updated & pushed." -ForegroundColor Green
} else {
    Write-Host "  No changes to commit." -ForegroundColor Gray
}
Pop-Location
