Option Explicit

Dim sh, fso, scriptDir, launcher, command, exitCode
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = fso.BuildPath(scriptDir, "Invoke-WeChatDualLaunch.ps1")

If Not fso.FileExists(launcher) Then
    MsgBox "Launcher not found:" & vbCrLf & launcher, vbExclamation, "WeChat dual-open"
    WScript.Quit 1
End If

command = "pwsh.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & _
    Quote(launcher)
exitCode = sh.Run(command, 0, True)

Set sh = Nothing
Set fso = Nothing
WScript.Quit exitCode

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
