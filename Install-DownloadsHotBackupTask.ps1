[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TaskName = 'DownloadsHotBackup-Daily',
    [string]$TaskPath = '\',
    [datetime]$DailyAt = [datetime]::Today.AddHours(21).AddMinutes(35),
    [string]$UserId = "$env:USERDOMAIN\$env:USERNAME",
    [switch]$DefinitionOnly
)

$ErrorActionPreference = 'Stop'

$launcher = Join-Path $PSScriptRoot 'Sync-DownloadsToG-Hidden.vbs'
$backupScript = Join-Path $PSScriptRoot 'Sync-DownloadsToG.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Hidden launcher is missing: $launcher"
}
if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
    throw "Downloads hot-backup script is missing: $backupScript"
}

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$action = New-ScheduledTaskAction `
    -Execute $wscript `
    -Argument "`"$launcher`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $DailyAt
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 15) `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType Interactive `
    -RunLevel Limited
$description = 'Daily additive E:\Downloads to G hot backup. Hidden launcher; catches up after missed runs; never writes H.'
$definition = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $description

if ($DefinitionOnly) {
    return $definition
}

$target = "$TaskPath$TaskName"
if (-not $PSCmdlet.ShouldProcess($target, 'Register or replace scheduled task with the audited definition')) {
    return $definition
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskPath `
    -InputObject $definition `
    -Force | Out-Null

$registered = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
$registeredAction = @($registered.Actions)
$registeredTrigger = @($registered.Triggers)
if ($registeredAction.Count -ne 1 -or
    [IO.Path]::GetFileName([string]$registeredAction[0].Execute) -ine 'wscript.exe' -or
    [string]$registeredAction[0].Arguments -ne "`"$launcher`"" -or
    $registeredTrigger.Count -ne 1 -or
    [int]$registeredTrigger[0].DaysInterval -ne 1 -or
    -not $registered.Settings.StartWhenAvailable -or
    [int]$registered.Settings.RestartCount -ne 3 -or
    [string]$registered.Settings.RestartInterval -ne 'PT15M' -or
    [string]$registered.Settings.MultipleInstances -ne 'IgnoreNew' -or
    [string]$registered.Settings.ExecutionTimeLimit -ne 'PT2H' -or
    $registered.Settings.RunOnlyIfNetworkAvailable -or
    $registered.Settings.WakeToRun) {
    throw "Scheduled task readback does not match the required Downloads hot-backup policy: $target"
}

Write-Host "[OK] $target is installed and verified."
$registered
