# ==========================================
# 软件列表备份脚本
# ==========================================

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

$TargetDrive = "H:\"
$BackupDir   = "H:\My_Digital_Backup"

function Pause-Exit { exit }

Write-Host ""
Write-Host "  📦 软件列表备份" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# 1. 驱动器检查
Write-Host "  🔍 检查 H: 驱动器..." -NoNewline
if (-not (Test-Path $TargetDrive)) {
    Write-Host " ❌ 未挂载，已跳过" -ForegroundColor Red
    Pause-Exit
}
Write-Host " ✅" -ForegroundColor Green

# 2. 创建备份目录
if (-not (Test-Path $BackupDir)) {
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
Get-ChildItem Env:\ | Sort-Object Name | Format-List |
    Out-File -FilePath "$BackupDir\env_latest.txt" -Encoding utf8 -Force
Write-Host " ✅" -ForegroundColor Green

# 5. Winget 清单
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "  🪟 导出 Winget 清单..." -NoNewline
    winget export -o "$BackupDir\winget_latest.json" --include-versions --accept-source-agreements | Out-Null
    Write-Host " ✅" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  winget 未安装，已跳过" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ✨ 备份完成  →  $BackupDir" -ForegroundColor Cyan
Pause-Exit
