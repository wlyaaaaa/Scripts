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

$TargetDrive = "G:\"
$AutoBackupDirName = '80_Backup'
$SoftwareEnvDirName = -join @([char]0x8F6F, [char]0x4EF6, [char]0x73AF, [char]0x5883)
$AutoBackupRoot = Join-Path $TargetDrive $AutoBackupDirName
$BackupDir = Join-Path $AutoBackupRoot $SoftwareEnvDirName
$DockerImageBackupDir = Join-Path (Join-Path $AutoBackupRoot 'Docker') 'images'
$DockerImagesToSave = @(
    'timeaudit-audit-ingest:latest'
)
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

function Get-CodexFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

Write-Host ""
Write-Host "  📦 软件列表备份" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# 1. 驱动器检查
Write-Host "  🔍 检查 G: 热备盘..." -NoNewline
$initialStatus = Get-CodexHDriveStatus -DriveLetter 'G' -MinimumFreeBytes $MinimumFreeBytes
if (-not $initialStatus.IsMounted) {
    Write-Host " ❌ 未挂载，已跳过" -ForegroundColor Red
    Pause-Exit
}
Write-Host " ✅" -ForegroundColor Green
Write-HDriveStatusHost -Status $initialStatus

try {
    Write-Host "  🔒 等待 G: 热备写入锁..." -NoNewline
    Invoke-CodexHDriveWriteLock -TimeoutSeconds $MutexWaitSeconds -ScriptBlock {
        Write-Host " ✅" -ForegroundColor Green

        $lockedStatus = Get-CodexHDriveStatus -DriveLetter 'G' -MinimumFreeBytes $MinimumFreeBytes
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
        $EnvTempPath = Join-Path $env:TEMP ('env_latest_{0}.txt' -f ([guid]::NewGuid().ToString('N')))
        try {
            Get-ChildItem Env:\ | Sort-Object Name | Format-List |
                Out-File -FilePath $EnvTempPath -Encoding utf8 -Force
            Export-CodexRedactedEnvFile -InputPath $EnvTempPath -OutputPath $EnvRedactedLatestPath | Out-Null
            @(
                'Plaintext environment variables are intentionally not retained here.',
                'Use env_redacted_latest.txt for routine review.',
                'Use DevConfigBackup _system\env-user.reg, _system\env-machine.reg, and _system\path-machine.txt for recovery.'
            ) | Out-File -FilePath $EnvLatestPath -Encoding utf8 -Force
        } finally {
            Remove-Item -LiteralPath $EnvTempPath -Force -ErrorAction SilentlyContinue
        }
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

        # 6. Docker 本地自建镜像
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            Write-Host "  🐳 备份 Docker 本地镜像..." -NoNewline
            New-Item -ItemType Directory -Path $DockerImageBackupDir -Force | Out-Null
            $dockerManifest = @()
            foreach ($image in $DockerImagesToSave) {
                $imageId = (& docker image inspect $image --format '{{.Id}}' 2>$null)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($imageId)) {
                    $dockerManifest += [pscustomobject]@{
                        Image = $image
                        Status = 'missing'
                        SavedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    }
                    continue
                }

                $safeName = ($image -replace '[^A-Za-z0-9_.-]', '_')
                $targetTar = Join-Path $DockerImageBackupDir "$safeName.latest.tar"
                $tempTar = "$targetTar.tmp"
                Remove-Item -LiteralPath $tempTar -Force -ErrorAction SilentlyContinue

                & docker image save $image -o $tempTar
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempTar)) {
                    throw "docker image save failed for $image"
                }
                $tempItem = Get-Item -LiteralPath $tempTar
                if ($tempItem.Length -le 0) {
                    throw "docker image save produced an empty archive for $image"
                }
                Move-Item -LiteralPath $tempTar -Destination $targetTar -Force
                $hash = Get-CodexFileSha256 -Path $targetTar
                $targetItem = Get-Item -LiteralPath $targetTar
                $dockerManifest += [pscustomobject]@{
                    Image = $image
                    ImageId = $imageId
                    Archive = $targetItem.Name
                    Bytes = $targetItem.Length
                    Sha256 = $hash
                    SavedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    Restore = "docker image load -i `"$($targetItem.Name)`""
                    Status = 'saved'
                }
            }
            $dockerManifest | ConvertTo-Json -Depth 5 |
                Out-File -FilePath (Join-Path $DockerImageBackupDir 'manifest_latest.json') -Encoding utf8 -Force
            Write-Host " ✅" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  docker 未安装，已跳过 Docker 镜像备份" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "  已拒绝/停止写入 G: $($_.Exception.Message)" -ForegroundColor Red
    Pause-Exit 3
}

Write-Host ""
Write-Host "  ✨ 备份完成  →  $BackupDir" -ForegroundColor Cyan
Pause-Exit
