# Scripts —— 个人常用脚本集

Windows 小工具脚本集。下面这些**双击就能用**:

## ✅ 能直接用(双击)

| 双击这个 | 作用 | 备注 |
|------|------|------|
| **`修复音响声音.bat`** | 默认声音被蓝牙/HDMI/虚拟声卡抢走时,**一键切回板载音响**(无需管理员) | 音频设备 ID 为本机专属,换机器需改 `Set-DefaultAudio.ps1` 里的 `$TargetId` |
| **`微信双开.vbs`** | **开两个微信实例**(Weixin 4.x) | 微信路径写死在脚本里:`C:\Program Files\Tencent\Weixin\Weixin.exe` |
| **`释放卡住按键.bat`** | **一键释放卡住/粘滞的键盘修饰键**(Ctrl/Alt/Shift/Win) | 解决由于自动化键鼠模拟、远程控制或系统粘滞导致的键盘无响应、按键卡死或乱快捷键问题 |
| **`IPv6状态.bat`** | **看 IPv6 现在开没开**(各网卡 + 有没有 IPv6 上网默认路由) | 只读,不改任何东西 |
| **`IPv6切换.bat`** | **一键开/关 IPv6**(自动 UAC 提权)。关=全走 IPv4 经代理(Google/翻墙稳),开=IPv6 直连可用 | 只切**上网网卡**,**不动 `natpierce`**(公网穿要用它的 IPv6) |
| **`更新README.bat`** | **自动刷新本 README 的文件清单**(下面 `## File list` 那段)并 commit + push | 描述区是手写的,只自动更新文件列表 |
| **`auto_push.bat`** | 把本仓库**一键 commit + push 到 GitHub** | 即使工作区干净也会推送已有 ahead；behind/diverged 或已有人工 staged 会阻断，成功前实时确认远端 OID |
| **`backup_apps.bat`** | 备份**已装软件清单 + 环境变量 + winget 清单** 到 `G:\80_Backup\软件环境` | G盘在线热备，可由计划任务直接访问 |
| **`Sync-DownloadsToG.bat`** | 把系统下载目录 `E:\Downloads` 同步到在线热备 `G:\80_Backup\03_下载与安装包` | 只复制/更新，**不删除 G 盘旧文件**；H 冷备统一由 PCConfig 人工执行 G→H |

## 其他(非开箱即用)

- `Set-DefaultAudio.ps1`、`backup_apps.ps1`、`IPv6-Status.ps1`、`IPv6-Toggle.ps1`、`Update-Readme.ps1` —— 上面那些 `.bat` 的内核,不单独跑。
- `backup_apps_hidden.vbs`、`auto_push.vbs` —— 对应功能的**无窗口版**,挂「任务计划程序」定时跑用。
- `Sync-DownloadsToG.ps1`、`Sync-DownloadsToG-Hidden.vbs` —— 下载目录到 G 热备的人工/可调度入口；可先跑 `Sync-DownloadsToG.ps1 -ListOnly`。任何 H 冷备只能从已验收的 G 热备经 PCConfig 人工流程复制。
- `Install-DownloadsHotBackupTask.ps1` —— 幂等安装 `DownloadsHotBackup-Daily`：每天 21:35 通过 `wscript.exe` 隐藏运行；错过时补跑，失败后每 15 分钟重试（最多 3 次），拒绝并发实例，2 小时超时，不依赖网络、不唤醒电脑。
- `HDriveSafety.ps1` —— 写入 H 盘前的公共护栏: 检查 dirty / `Full Repair Needed`、剩余空间,并用 `Global\CodexHDriveUsbWriteLock` 防并发写入; H 盘状态不安全时拒绝写入。
- `检查运行状态.vbs` —— 弹窗看 TimeAudit 状态,**依赖 `E:\Projects\Tools\TimeAudit\check_status_gui.ps1`**(不在本仓库)。

电脑关机时计划任务不会运行；`StartWhenAvailable` 会在下次开机并登录后补跑一次，不会重放每个错过的日周期。安装或刷新任务：

```powershell
pwsh -NoProfile -File .\Install-DownloadsHotBackupTask.ps1
```

自动推送与下载任务定义的回归测试：

```powershell
pwsh -NoProfile -File .\tests\Test-AutoPushAndDownloadsTask.ps1
```

> 关于 IPv6:很多被墙的服务(Google/Antigravity 等)会**优先走 IPv6 直连**,而代理只接管 IPv4 → IPv6 流量裸奔撞墙超时。**登录 Google 系应用前,用 `IPv6状态.bat` 看一眼,开着就 `IPv6切换.bat` 关掉**,登录完想要 IPv6 再切回来。

> `.ps1` 单独运行会被执行策略拦;走配套的 `.bat`(已带 `-ExecutionPolicy Bypass`)即可。

## File list (auto-generated)
<!-- FILES:START -->
| File | Size | Modified |
|------|------|----------|
| `.gitignore` | 62 B | 2026-07-07 19:43 |
| `更新README.bat` | 103 B | 2026-06-28 21:10 |
| `检查运行状态.vbs` | 1773 B | 2026-06-15 11:04 |
| `释放卡住按键.bat` | 50 B | 2026-07-01 02:03 |
| `微信双开.vbs` | 855 B | 2026-06-19 10:42 |
| `修复音响声音.bat` | 201 B | 2026-06-28 15:41 |
| `auto_push.bat` | 134 B | 2026-06-19 11:00 |
| `auto_push.vbs` | 157 B | 2026-07-05 22:43 |
| `backup_apps_hidden.vbs` | 846 B | 2026-07-07 20:07 |
| `backup_apps.bat` | 135 B | 2026-06-19 11:07 |
| `backup_apps.ps1` | 4036 B | 2026-07-07 21:06 |
| `HDriveSafety.ps1` | 6129 B | 2026-07-07 20:56 |
| `Install-DownloadsHotBackupTask.ps1` | 计划任务安装器 | 当前 |
| `IPv6-Status.ps1` | 913 B | 2026-06-28 21:08 |
| `IPv6-Toggle.ps1` | 1384 B | 2026-06-28 21:08 |
| `IPv6切换.bat` | 256 B | 2026-06-28 21:10 |
| `IPv6状态.bat` | 101 B | 2026-06-28 21:10 |
| `release_keyboard.py` | 481 B | 2026-07-01 02:03 |
| `Set-DefaultAudio-Hidden.vbs` | 425 B | 2026-07-05 22:37 |
| `Set-DefaultAudio.ps1` | 1817 B | 2026-06-28 15:41 |
| `Sync-DownloadsToG-Hidden.vbs` | 热备隐藏入口 | 当前 |
| `Sync-DownloadsToG.bat` | 热备双击入口 | 当前 |
| `Sync-DownloadsToG.ps1` | 下载目录 G 热备脚本 | 当前 |
| `Update-Readme.ps1` | 1599 B | 2026-06-28 21:09 |
<!-- FILES:END -->
