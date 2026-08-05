# Scripts —— 个人常用脚本集

Windows 小工具脚本集。下面这些**双击就能用**:

## ✅ 能直接用(双击)

| 双击这个 | 作用 | 备注 |
|------|------|------|
| **`修复音响声音.bat`** | 默认声音被蓝牙/HDMI/虚拟声卡抢走时,**一键切回板载音响**(无需管理员) | 音频设备 ID 为本机专属,换机器需改 `Set-DefaultAudio.ps1` 里的 `$TargetId` |
| **`微信双开.vbs`** | **把健康的微信实例补足到两个**(Weixin 4.x) | 无控制台、相对路径调用 PowerShell 内核；已有两个时不会重复启动 |
| **`释放卡住按键.bat`** | **一键释放卡住/粘滞的键盘修饰键**(Ctrl/Alt/Shift/Win) | 解决由于自动化键鼠模拟、远程控制或系统粘滞导致的键盘无响应、按键卡死或乱快捷键问题 |
| **`IPv6状态.bat`** | **看 IPv6 现在开没开**(各网卡 + 有没有 IPv6 上网默认路由) | 只读,不改任何东西 |
| **`IPv6切换.bat`** | **一键开/关 IPv6**(自动 UAC 提权)。关=全走 IPv4 经代理(Google/翻墙稳),开=IPv6 直连可用 | 只切**上网网卡**,**不动 `natpierce`**(公网穿要用它的 IPv6) |
| **`更新README.bat`** | **自动刷新本 README 的文件清单**(下面 `## File list` 那段)并 commit + push | 描述区是手写的,只自动更新文件列表 |
| **`auto_push.bat`** | 把本仓库**一键 commit + push 到 GitHub** | 即使工作区干净也会推送已有 ahead；behind/diverged 或已有人工 staged 会阻断，成功前实时确认远端 OID |
| **`backup_apps.bat`** | 备份**已装软件清单 + 环境变量 + winget 清单** 到 `G:\80_Backup\软件环境` | G盘在线热备，可由计划任务直接访问 |
| **`Sync-DownloadsToG.bat`** | 把系统下载目录 `E:\Downloads` 增量同步到在线热备 `G:\80_Backup\03_下载与安装包` | 显示百分比、速度、文件数和 ETA；源端删除项进入 30 天隔离区；H 冷备统一由 PCConfig 人工执行 G→H |
| **`Sync-DocumentsToG.bat`** | 把系统文档目录 `E:\Documents` 增量同步到在线热备 `G:\80_Backup\Documents` | 同一任务还串行纳管个人媒体根；与 Downloads 共用进度与隔离引擎 |

## 其他(非开箱即用)

- `Set-DefaultAudio.ps1`、`backup_apps.ps1`、`IPv6-Status.ps1`、`IPv6-Toggle.ps1`、`Update-Readme.ps1` —— 上面那些 `.bat` 的内核,不单独跑。
- `Invoke-WeChatDualLaunch.ps1` —— 微信双开内核。默认目标为 2，只统计当前 Windows 会话中有线程、有句柄且父进程不是同名进程的健康顶层实例；使用命名互斥串行补足，并在每次启动后有限等待实例出现、再连续观察稳定性。已有两个也先通过稳定门。启动尝试有明确上限，不做坐标点击、自动登录、凭据处理或无限重启。
- `backup_apps_hidden.vbs`、`auto_push.vbs` —— 对应功能的**无窗口版**,挂「任务计划程序」定时跑用。
- `Sync-DownloadsToG.ps1` / `Sync-DocumentsToG.ps1` —— Downloads、Documents 到 G 的增量热备内核；同一个 Documents 任务还精确纳管两个 Saved Games 根、Steam `userdata` 和现场发现的 Frostpunk 2 正式版/测试版 `SaveGames`，并把 `E:\Pictures`、`E:\Music`、`E:\Videos`、`E:\Media` 四个个人媒体根分别写入唯一的 `G:\80_Backup\PersonalMedia` 树。每个媒体根都有独立回执；源不存在时安全跳过，任一实际调用失败都会使现有任务失败。不整包复制 AppData，也不另建任务。手动 `.bat` 入口显示进度，隐藏 VBS 供计划任务使用。源端删除项始终先移入 `G:\80_Backup\_quarantine`，保留 30 天；文件占用或访问拒绝记入凭证并在下次重试，不中断其他文件。任何 H 冷备只能从已验收的 G 热备经 PCConfig 人工流程复制。
- `Install-DownloadsHotBackupTask.ps1` / `Install-DocumentsHotBackupTask.ps1` —— 幂等安装两个每天 21:35 的隐藏热备任务；共享全局互斥锁，实际复制按顺序执行。错过时补跑，失败后每 15 分钟重试（最多 3 次），不依赖网络、不唤醒电脑。
- `HDriveSafety.ps1` —— 写入 H 盘前的公共护栏: 检查 dirty / `Full Repair Needed`、剩余空间,并用 `Global\CodexHDriveUsbWriteLock` 防并发写入; H 盘状态不安全时拒绝写入。
- `检查运行状态.vbs` —— 弹窗看 TimeAudit 状态,**依赖 `E:\Projects\Tools\TimeAudit\check_status_gui.ps1`**(不在本仓库)。

电脑关机时计划任务不会运行；`StartWhenAvailable` 会在下次开机并登录后补跑一次，不会重放每个错过的日周期。安装或刷新任务：

```powershell
pwsh -NoProfile -File .\Install-DownloadsHotBackupTask.ps1
pwsh -NoProfile -File .\Install-DocumentsHotBackupTask.ps1
```

仓库回归测试：

```powershell
pwsh -NoProfile -File .\tests\Test-AutoPushAndDownloadsTask.ps1
pwsh -NoProfile -File .\tests\Test-HotBackupCore.ps1
pwsh -NoProfile -File .\tests\Test-WeChatDualLaunch.ps1
```

微信启动器也可直接调用；以下六个参数是供快捷方式、计划任务或其他仓库集成的稳定接口：

```powershell
pwsh -NoProfile -File .\Invoke-WeChatDualLaunch.ps1 `
  -WeChatPath 'C:\Program Files\Tencent\Weixin\Weixin.exe' `
  -DesiredInstances 2 `
  -BetweenLaunchDelaySeconds 1.5 `
  -StabilizationSeconds 1.5 `
  -ReceiptPath "$env:LOCALAPPDATA\Scripts\wechat-dual-launch-last.json" `
  -Json
```

`-ReceiptPath` 可省略；指定时在命名互斥内使用同目录临时文件加原子替换写入 JSON，互斥超时不会无锁覆盖已有回执。程序不存在、互斥超时或在有限尝试内未达到目标都会返回非零退出码，并且不会持续重启微信。冷启动或进程接力较慢时，可另用 `-StartupTimeoutSeconds` 调整单次启动后等待实例出现的有限时长（默认 5 秒）。

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
| `微信双开.vbs` | 微信双开无窗口相对路径入口 | 当前 |
| `修复音响声音.bat` | 201 B | 2026-06-28 15:41 |
| `Invoke-WeChatDualLaunch.ps1` | 微信双开幂等启动内核 | 当前 |
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
| `Sync-DocumentsToG-Hidden.vbs` | 文档热备隐藏入口 | 当前 |
| `Sync-DocumentsToG.bat` | 文档热备双击入口 | 当前 |
| `Sync-DocumentsToG.ps1` | 文档目录 G 热备脚本 | 当前 |
| `Update-Readme.ps1` | 1599 B | 2026-06-28 21:09 |
| `tests\Test-WeChatDualLaunch.ps1` | 微信双开确定性回归测试 | 当前 |
<!-- FILES:END -->
