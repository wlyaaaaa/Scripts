Dim shell, fso, here, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
exitCode = shell.Run("cmd.exe /c """ & here & "\auto_push.bat""", 0, True)
WScript.Quit exitCode
