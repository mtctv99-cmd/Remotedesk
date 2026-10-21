import ctypes
import ctypes.wintypes as wt
import sys

sys.stdout.reconfigure(encoding="utf-8")
from PIL import ImageGrab

h = int(sys.argv[1], 0)
u = ctypes.windll.user32
u.ShowWindow(h, 9)  # SW_RESTORE
u.SetForegroundWindow(h)
ctypes.windll.kernel32.Sleep(700)
r = wt.RECT()
u.GetWindowRect(h, ctypes.byref(r))
print("rect", r.left, r.top, r.right, r.bottom,
      r.right - r.left, r.bottom - r.top)
if r.right <= r.left or r.bottom <= r.top:
    sys.exit(2)
img = ImageGrab.grab(bbox=(r.left, r.top, r.right, r.bottom),
                     all_screens=True)
img.save(sys.argv[2])
print("saved", sys.argv[2], img.size)
