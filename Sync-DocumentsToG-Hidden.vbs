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

Function RunDocumentsOwner(sourcePath, destinationPath, receiptPath)
    cmd = exe & " -NoProfile -ExecutionPolicy Bypass -File " & _
        Q(here & "\Sync-DocumentsToG.ps1") & _
        " -Source " & Q(sourcePath) & _
        " -Destination " & Q(destinationPath) & _
        " -ReceiptPath " & Q(receiptPath) & _
        " -Quiet"
    RunDocumentsOwner = shell.Run(cmd, 0, True)
End Function

' Keep every root inside the existing Documents owner and G/H Documents tree.
' E:\Documents already includes My Games. The two Saved Games roots are
' separate live folders on this PC, so preserve both without scanning AppData.
exitCode = RunDocumentsOwner( _
    "E:\Documents", _
    "G:\80_Backup\Documents", _
    "G:\80_Backup\ControlPlane\documents-hot-last.json")
If exitCode <> 0 Then WScript.Quit exitCode

If fso.FolderExists("E:\Saved Games") Then
    exitCode = RunDocumentsOwner( _
        "E:\Saved Games", _
        "G:\80_Backup\Documents\_SavedGames\E", _
        "G:\80_Backup\ControlPlane\saved-games-e-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

userSavedGames = shell.ExpandEnvironmentStrings("%USERPROFILE%") & _
    "\Saved Games"
If fso.FolderExists(userSavedGames) Then
    exitCode = RunDocumentsOwner( _
        userSavedGames, _
        "G:\80_Backup\Documents\_SavedGames\UserProfile", _
        "G:\80_Backup\ControlPlane\saved-games-user-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

WScript.Quit 0
