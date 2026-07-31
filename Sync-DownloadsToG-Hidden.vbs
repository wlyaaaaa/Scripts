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

' Keep the launcher ASCII-only. Windows Script Host may decode an unmarked
' UTF-8 .vbs file with the active ANSI code page, corrupting literal Chinese
' paths before PowerShell ever sees them.
cnDownloads = ChrW(&H4E0B) & ChrW(&H8F7D)
cnAndInstallPackage = ChrW(&H4E0E) & ChrW(&H5B89) & ChrW(&H88C5) & ChrW(&H5305)
downloadsDestination = "G:\80_Backup\03_" & cnDownloads & cnAndInstallPackage
alternateSource = "E:\" & cnDownloads
alternateDestination = downloadsDestination & "\_AlternateRoots\" & cnDownloads

exitCode = RunDownloadsOwner( _
    "E:\Downloads", _
    downloadsDestination, _
    "G:\80_Backup\ControlPlane\downloads-hot-last.json")
If exitCode <> 0 Then WScript.Quit exitCode

' A second live Downloads root currently contains user-owned material.
' Keep it under the same owner and cold-copied Downloads tree, with a distinct
' scalar source/destination receipt. A missing root is normal after reinstall.
If fso.FolderExists(alternateSource) Then
    exitCode = RunDownloadsOwner( _
        alternateSource, _
        alternateDestination, _
        "G:\80_Backup\ControlPlane\downloads-cn-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

WScript.Quit 0
