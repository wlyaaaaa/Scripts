import win32api
import win32con
import sys

sys.stdout.reconfigure(encoding='utf-8')

# Modifier keys to release
keys = [
    win32con.VK_CONTROL,
    win32con.VK_MENU,  # Alt
    win32con.VK_SHIFT,
    win32con.VK_LWIN,
    win32con.VK_RWIN
]

print("Releasing stuck modifier keys (Ctrl, Alt, Shift, Win)...")
for key in keys:
    win32api.keybd_event(key, 0, win32con.KEYEVENTF_KEYUP, 0)
print("Done! If you still feel keyboard is stuck, try physically pressing the keys once.")
