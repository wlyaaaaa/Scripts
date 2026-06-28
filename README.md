# Scripts —— 个人常用脚本集

一堆 Windows 上的小工具脚本(备份、音频、微信双开、自动推送等)。大多**双击对应的 `.bat` / `.vbs` 就能用**;`.ps1` 由这些包装器带 `-ExecutionPolicy Bypass` 调起,不用手动设策略。

> ⚠️ 部分脚本里有**本机专属的硬编码路径/设备 ID**(下表「需改」列标了),换机器要先改。

## 脚本清单 / 怎么用

| 脚本 | 作用 | 怎么用 | 需改 |
|------|------|--------|------|
| `修复音响声音.bat` | 把系统默认播放设备**强制切回板载音响**(Realtek 2nd output),蓝牙/HDMI/虚拟声卡抢了默认时一键夺回。**普通权限、无需 UAC**。 | 双击 | — |
| `Set-DefaultAudio.ps1` | 上面那条的核心(被 `.bat` 调起)。 | 一般不单独跑 | **音频设备 ID 是本机专属**(脚本里 `$TargetId`),换机器/换声卡要替换 |
| `微信双开.vbs` | 启动**两个微信实例**(Weixin 4.x 登录窗无单实例锁)。 | 双击 | 微信路径 `C:\Program Files\Tencent\Weixin\Weixin.exe` |
| `backup_apps.bat` | 备份**已装软件清单 + 环境变量 + winget 清单**到 `H:\My_Digital_Backup`(带窗口、有 pause)。 | 双击 | 目标盘 `H:\`(脚本里 `$TargetDrive`) |
| `backup_apps.ps1` | 上面那条的核心。 | 一般不单独跑 | 同上 |
| `backup_apps_hidden.vbs` | **无窗口**跑备份,供计划任务 `AutoDigitalBackupToH` 调用。 | 加进计划任务,或双击静默跑 | — |
| `检查运行状态.vbs` | 弹窗显示 `TimeAudit` 的运行状态。 | 双击 | 依赖 `E:\TimeAudit\check_status_gui.ps1`(不在本仓库) |
| `auto_push.bat` | **一键把本仓库 git add/commit/push** 到 `origin main`(无改动则跳过)。 | 双击 | — |
| `auto_push.vbs` | **无窗口**跑 `auto_push.bat`,可挂计划任务定时自动备份本仓库到 GitHub。 | 加进计划任务,或双击静默跑 | — |

## 自动推送(可选)
想让这个脚本仓库改了就自动同步到 GitHub:把 `auto_push.vbs` 加进**任务计划程序**(触发器自定,如登录时/每天),它会无窗口跑 `git add -A → commit "auto: 时间" → push origin main`。

## 提示
- `.ps1` 单独跑会被执行策略拦,**走配套的 `.bat`/`.vbs`**(已带 `Bypass`)最省事。
- `修复音响声音` 里的设备 ID 怎么换:在 PowerShell 用支持列设备的工具(如 `AudioDeviceCmdlets`)查到目标输出端点的 ID,替换 `Set-DefaultAudio.ps1` 里的 `$TargetId` 即可。
