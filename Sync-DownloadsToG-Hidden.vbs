Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
pwsh = shell.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If Not fso.FileExists(pwsh) Then
    WScript.Quit 70
End If
exe = """" & pwsh & """"

Function Q(value)
    Q = """" & value & """"
End Function

Function RunDownloadsOwner(sourcePath, destinationPath, receiptPath)
    cmd = exe & " -NoProfile -ExecutionPolicy Bypass -File " & _
        Q(here & "\Sync-DownloadsToG.ps1") & _
        " -Source " & Q(sourcePath) & _
        " -Destination " & Q(destinationPath) & _
        " -ReceiptPath " & Q(receiptPath) & _
        " -Quiet"
    RunDownloadsOwner = shell.Run(cmd, 0, True)
End Function

exitCode = RunDownloadsOwner( _
    "E:\Downloads", _
    "G:\80_Backup\03_下载与安装包", _
    "G:\80_Backup\ControlPlane\downloads-hot-last.json")
If exitCode <> 0 Then WScript.Quit exitCode

' A second live Downloads root currently contains user-owned material.
' Keep it under the same owner and cold-copied Downloads tree, with a distinct
' scalar source/destination receipt. A missing root is normal after reinstall.
If fso.FolderExists("E:\下载") Then
    exitCode = RunDownloadsOwner( _
        "E:\下载", _
        "G:\80_Backup\03_下载与安装包\_AlternateRoots\下载", _
        "G:\80_Backup\ControlPlane\downloads-cn-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

WScript.Quit 0
