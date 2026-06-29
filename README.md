# Scripts —— 个人常用脚本集

Windows 小工具脚本集。下面这些**双击就能用**:

## ✅ 能直接用(双击)

| 双击这个 | 作用 | 备注 |
|------|------|------|
| **`修复音响声音.bat`** | 默认声音被蓝牙/HDMI/虚拟声卡抢走时,**一键切回板载音响**(无需管理员) | 音频设备 ID 为本机专属,换机器需改 `Set-DefaultAudio.ps1` 里的 `$TargetId` |
| **`微信双开.vbs`** | **开两个微信实例**(Weixin 4.x) | 微信路径写死在脚本里:`C:\Program Files\Tencent\Weixin\Weixin.exe` |
| **`IPv6状态.bat`** | **看 IPv6 现在开没开**(各网卡 + 有没有 IPv6 上网默认路由) | 只读,不改任何东西 |
| **`IPv6切换.bat`** | **一键开/关 IPv6**(自动 UAC 提权)。关=全走 IPv4 经代理(Google/翻墙稳),开=IPv6 直连可用 | 只切**上网网卡**,**不动 `natpierce`**(公网穿要用它的 IPv6) |
| **`更新README.bat`** | **自动刷新本 README 的文件清单**(下面 `## File list` 那段)并 commit + push | 描述区是手写的,只自动更新文件列表 |
| **`auto_push.bat`** | 把本仓库**一键 commit + push 到 GitHub** | 无改动则自动跳过 |
| **`backup_apps.bat`** | 备份**已装软件清单 + 环境变量 + winget 清单** 到 `H:\My_Digital_Backup` | **要先插 `H:` 盘**,否则自动跳过 |

## 其他(非开箱即用)

- `Set-DefaultAudio.ps1`、`backup_apps.ps1`、`IPv6-Status.ps1`、`IPv6-Toggle.ps1`、`Update-Readme.ps1` —— 上面那些 `.bat` 的内核,不单独跑。
- `backup_apps_hidden.vbs`、`auto_push.vbs` —— 对应功能的**无窗口版**,挂「任务计划程序」定时跑用。
- `检查运行状态.vbs` —— 弹窗看 TimeAudit 状态,**依赖 `E:\TimeAudit\check_status_gui.ps1`**(不在本仓库)。

> 关于 IPv6:很多被墙的服务(Google/Antigravity 等)会**优先走 IPv6 直连**,而代理只接管 IPv4 → IPv6 流量裸奔撞墙超时。**登录 Google 系应用前,用 `IPv6状态.bat` 看一眼,开着就 `IPv6切换.bat` 关掉**,登录完想要 IPv6 再切回来。

> `.ps1` 单独运行会被执行策略拦;走配套的 `.bat`(已带 `-ExecutionPolicy Bypass`)即可。

## File list (auto-generated)
<!-- FILES:START -->
<!-- FILES:END -->
