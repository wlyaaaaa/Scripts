Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If fso.FileExists(pwsh) Then
    exe = """" & pwsh & """"
Else
    exe = "powershell.exe"
End If
cmd = exe & " -NoProfile -ExecutionPolicy Bypass -File """ & here & "\Sync-DownloadsToG.ps1"""
exitCode = shell.Run(cmd, 0, True)
WScript.Quit exitCode

