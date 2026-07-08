# ==========================================
# 软件列表备份脚本
# ==========================================

$ErrorActionPreference = 'Stop'

try {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "White"
    Clear-Host
} catch {
    # Non-interactive scheduled task hosts can reject RawUI cursor operations.
}

$TargetDrive = "H:\"
$AutoBackupDirName = '80_' + (-join @([char]0x81EA, [char]0x52A8, [char]0x5907, [char]0x4EFD, [char]0x533A))
$SoftwareEnvDirName = -join @([char]0x8F6F, [char]0x4EF6, [char]0x73AF, [char]0x5883)
$BackupDir = Join-Path (Join-Path $TargetDrive $AutoBackupDirName) $SoftwareEnvDirName
$MinimumFreeBytes = [UInt64](2GB)
$MutexWaitSeconds = 1800

. (Join-Path $PSScriptRoot 'HDriveSafety.ps1')
. (Join-Path $PSScriptRoot 'EnvRedaction.ps1')

function Pause-Exit {
    param([int]$Code = 0)
    exit $Code
}

function Write-HDriveStatusHost {
    param([pscustomobject]$Status)

    foreach ($line in (Format-CodexHDriveStatus -Status $Status)) {
        Write-Host "     $line" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  📦 软件列表备份" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# 1. 驱动器检查
Write-Host "  🔍 检查 H: 驱动器..." -NoNewline
$initialStatus = Get-CodexHDriveStatus -DriveLetter 'H' -MinimumFreeBytes $MinimumFreeBytes
if (-not $initialStatus.IsMounted) {
    Write-Host " ❌ 未挂载，已跳过" -ForegroundColor Red
    Pause-Exit
}
Write-Host " ✅" -ForegroundColor Green
Write-HDriveStatusHost -Status $initialStatus

try {
    Write-Host "  🔒 等待 H: 写入锁..." -NoNewline
    Invoke-CodexHDriveWriteLock -TimeoutSeconds $MutexWaitSeconds -ScriptBlock {
        Write-Host " ✅" -ForegroundColor Green

        $lockedStatus = Get-CodexHDriveStatus -DriveLetter 'H' -MinimumFreeBytes $MinimumFreeBytes
        Write-HDriveStatusHost -Status $lockedStatus
        Assert-CodexHDriveWritable -Status $lockedStatus

        # 2. 创建备份目录
        if (-not (Test-Path -LiteralPath $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir | Out-Null
            Write-Host "  📁 已创建目录: $BackupDir" -ForegroundColor DarkGray
        }

        # 3. 注册表软件清单
        Write-Host "  📋 导出已安装软件列表..." -NoNewline
        $RegPaths = @(
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } |
            Select-Object DisplayName, DisplayVersion |
            Sort-Object DisplayName |
            Out-File -FilePath "$BackupDir\apps_latest.txt" -Encoding utf8 -Force
        Write-Host " ✅" -ForegroundColor Green

        # 4. 环境变量
        Write-Host "  🌐 导出环境变量..." -NoNewline
        $EnvLatestPath = Join-Path $BackupDir 'env_latest.txt'
        $EnvRedactedLatestPath = Join-Path $BackupDir 'env_redacted_latest.txt'
        Get-ChildItem Env:\ | Sort-Object Name | Format-List |
            Out-File -FilePath $EnvLatestPath -Encoding utf8 -Force
        Export-CodexRedactedEnvFile -InputPath $EnvLatestPath -OutputPath $EnvRedactedLatestPath | Out-Null
        Write-Host " ✅" -ForegroundColor Green

        # 5. Winget 清单
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "  🪟 导出 Winget 清单..." -NoNewline
            $WingetTarget = Join-Path $BackupDir 'winget_latest.json'
            $WingetTemp = Join-Path $env:TEMP ('winget_latest_{0}.json' -f ([guid]::NewGuid().ToString('N')))
            try {
                winget export -o $WingetTemp --include-versions --accept-source-agreements | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "winget export exited with code $LASTEXITCODE"
                }
                if (-not (Test-Path -LiteralPath $WingetTemp)) {
                    throw 'winget export did not create the expected JSON file'
                }
                $WingetTempItem = Get-Item -LiteralPath $WingetTemp
                if ($WingetTempItem.Length -le 0) {
                    throw 'winget export created an empty JSON file'
                }
                Copy-Item -LiteralPath $WingetTemp -Destination $WingetTarget -Force
            } finally {
                Remove-Item -LiteralPath $WingetTemp -Force -ErrorAction SilentlyContinue
            }
            Write-Host " ✅" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  winget 未安装，已跳过" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "  已拒绝/停止写入 H: $($_.Exception.Message)" -ForegroundColor Red
    Pause-Exit 3
}

Write-Host ""
Write-Host "  ✨ 备份完成  →  $BackupDir" -ForegroundColor Cyan
Pause-Exit
