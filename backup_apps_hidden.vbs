' ============================================================
'  隐藏窗口启动器 —— 由计划任务 AutoDigitalBackupToG 调用。
'  窗口模式 0 = 完全隐藏，不弹 PowerShell 窗、不抢前台焦点。
'  可移植：自动推导本脚本所在目录。
' ============================================================
Dim fso, here, shell, pwsh, exe, exitCode
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If fso.FileExists(pwsh) Then
    exe = """" & pwsh & """"
Else
    exe = "powershell.exe"
End If
exitCode = shell.Run(exe & " -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup_apps.ps1""", 0, True)
WScript.Quit exitCode
