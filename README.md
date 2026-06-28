# Scripts —— 个人常用脚本集

Windows 小工具脚本集。下面这些**双击就能用**:

## ✅ 能直接用(双击)

| 双击这个 | 作用 | 备注 |
|------|------|------|
| **`修复音响声音.bat`** | 默认声音被蓝牙/HDMI/虚拟声卡抢走时,**一键切回板载音响**(无需管理员) | 音频设备 ID 为本机专属,换机器需改 `Set-DefaultAudio.ps1` 里的 `$TargetId` |
| **`微信双开.vbs`** | **开两个微信实例**(Weixin 4.x) | 微信路径写死在脚本里:`C:\Program Files\Tencent\Weixin\Weixin.exe` |
| **`auto_push.bat`** | 把本仓库**一键 commit + push 到 GitHub** | 无改动则自动跳过 |
| **`backup_apps.bat`** | 备份**已装软件清单 + 环境变量 + winget 清单** 到 `H:\My_Digital_Backup` | **要先插 `H:` 盘**,否则自动跳过 |

## 其他(非开箱即用)

- `Set-DefaultAudio.ps1`、`backup_apps.ps1` —— 上面两个 `.bat` 的内核,不单独跑。
- `backup_apps_hidden.vbs`、`auto_push.vbs` —— 上面对应功能的**无窗口版**,挂「任务计划程序」定时跑用。
- `检查运行状态.vbs` —— 弹窗看 TimeAudit 状态,**依赖 `E:\TimeAudit\check_status_gui.ps1`**(不在本仓库)。

> `.ps1` 单独运行会被执行策略拦;走配套的 `.bat`/`.vbs`(已带 `-ExecutionPolicy Bypass`)即可。
