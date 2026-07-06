' Hidden launcher for the PinDefaultAudio-Speaker scheduled task.
Dim fso, shell, here, command, exitCode

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\Set-DefaultAudio.ps1"""
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
