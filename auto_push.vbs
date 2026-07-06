Dim shell, exitCode
Set shell = CreateObject("WScript.Shell")
exitCode = shell.Run("cmd.exe /c ""E:\Scripts\auto_push.bat""", 0, True)
WScript.Quit exitCode
