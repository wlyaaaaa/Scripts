Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If Not fso.FileExists(pwsh) Then
    WScript.Quit 70
End If
exe = """" & pwsh & """"
cmd = exe & " -NoProfile -ExecutionPolicy Bypass -File """ & here & "\Sync-DownloadsToG.ps1"" -Quiet"
exitCode = shell.Run(cmd, 0, True)
WScript.Quit exitCode
