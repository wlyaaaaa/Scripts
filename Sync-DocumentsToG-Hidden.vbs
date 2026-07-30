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

' Steam userdata can contain game-owned local state that is not guaranteed to
' participate in Steam Cloud. Resolve the live install root, then keep the
' precise userdata subtree inside the existing Documents owner.
On Error Resume Next
steamPath = shell.RegRead("HKCU\Software\Valve\Steam\SteamPath")
If Err.Number <> 0 Or Len(steamPath) = 0 Then
    Err.Clear
    steamPath = shell.RegRead( _
        "HKLM\SOFTWARE\WOW6432Node\Valve\Steam\InstallPath")
End If
If Err.Number <> 0 Or Len(steamPath) = 0 Then
    Err.Clear
    steamPath = "C:\Program Files (x86)\Steam"
End If
On Error GoTo 0
steamUserData = Replace(steamPath, "/", "\") & "\userdata"
If fso.FolderExists(steamUserData) Then
    exitCode = RunDocumentsOwner( _
        steamUserData, _
        "G:\80_Backup\Documents\_SavedGames\SteamUserdata", _
        "G:\80_Backup\ControlPlane\saved-games-steam-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

' Preserve only the discovered game save closures in AppData, never the
' surrounding application profile, caches, logs, crash reports or whole tree.
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
frostpunk2Saves = localAppData & _
    "\11bitstudios\Frostpunk2\Steam\Saved\SaveGames"
If fso.FolderExists(frostpunk2Saves) Then
    exitCode = RunDocumentsOwner( _
        frostpunk2Saves, _
        "G:\80_Backup\Documents\_SavedGames\AppData\Frostpunk2", _
        "G:\80_Backup\ControlPlane\saved-games-frostpunk2-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

frostpunk2BetaSaves = localAppData & _
    "\11bitstudios\Frostpunk2Beta\Steam\Saved\SaveGames"
If fso.FolderExists(frostpunk2BetaSaves) Then
    exitCode = RunDocumentsOwner( _
        frostpunk2BetaSaves, _
        "G:\80_Backup\Documents\_SavedGames\AppData\Frostpunk2Beta", _
        "G:\80_Backup\ControlPlane\saved-games-frostpunk2-beta-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

' Pictures, Music and Videos are Windows known folders with user-authored data
' on E. They share this existing task and copy engine, but use one nonduplicate
' PersonalMedia tree so Documents remains a coherent restore root.
If fso.FolderExists("E:\Pictures") Then
    exitCode = RunDocumentsOwner( _
        "E:\Pictures", _
        "G:\80_Backup\PersonalMedia\Pictures", _
        "G:\80_Backup\ControlPlane\personal-media-pictures-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

If fso.FolderExists("E:\Music") Then
    exitCode = RunDocumentsOwner( _
        "E:\Music", _
        "G:\80_Backup\PersonalMedia\Music", _
        "G:\80_Backup\ControlPlane\personal-media-music-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

If fso.FolderExists("E:\Videos") Then
    exitCode = RunDocumentsOwner( _
        "E:\Videos", _
        "G:\80_Backup\PersonalMedia\Videos", _
        "G:\80_Backup\ControlPlane\personal-media-videos-hot-last.json")
    If exitCode <> 0 Then WScript.Quit exitCode
End If

WScript.Quit 0
