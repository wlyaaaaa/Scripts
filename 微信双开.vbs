' ============================================================
'  WeChat dual-open  (Weixin 4.x)  -- double-click to run
'  Weixin 4.1.x has no single-instance lock at the login
'  window, so each launch opens an independent instance.
'  Start two copies sequentially with a short gap.
'  ASCII-only on purpose: .vbs is read in the system codepage.
' ============================================================
Option Explicit

Dim sh, fso, exe, p
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

exe = "C:\Program Files\Tencent\Weixin\Weixin.exe"

If Not fso.FileExists(exe) Then
    MsgBox "Weixin not found at:" & vbCrLf & exe, vbExclamation, "WeChat dual-open"
    WScript.Quit 1
End If

p = """" & exe & """"

sh.Run p, 1, False
WScript.Sleep 2000
sh.Run p, 1, False

Set sh  = Nothing
Set fso = Nothing
