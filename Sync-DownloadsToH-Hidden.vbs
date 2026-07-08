Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""E:\Scripts\Sync-DownloadsToH.ps1"" -RefreshList ""E:\Scripts\state\h-downloads-known-bad-20260707.csv"""
shell.Run cmd, 0, False
