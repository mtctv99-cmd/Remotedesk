import ctypes
import ctypes.wintypes as wt
import sys

sys.stdout.reconfigure(encoding="utf-8")
u = ctypes.windll.user32
res = []


def cb(h, l):
    if not u.IsWindowVisible(h):
        return True
    n = ctypes.create_unicode_buffer(512)
    u.GetWindowTextW(h, n, 512)
    cls = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(h, cls, 256)
    if not n.value and not cls.value.startswith("FLUTTER"):
        return True
    r = wt.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    res.append((cls.value, n.value, r.right - r.left, r.bottom - r.top,
                r.left, r.top))
    return True


u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p,
                                 ctypes.c_void_p)(cb), 0)
for r in res:
    print(r)
