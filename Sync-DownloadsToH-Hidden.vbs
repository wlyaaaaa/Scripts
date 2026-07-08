Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If fso.FileExists(pwsh) Then
    exe = """" & pwsh & """"
Else
    exe = "powershell.exe"
End If

cmd = exe & " -NoProfile -ExecutionPolicy Bypass -File ""E:\Scripts\Sync-DownloadsToH.ps1"" -RefreshList ""E:\Scripts\state\h-downloads-known-bad-20260707.csv"""
shell.Run cmd, 0, False
