import ctypes
import ctypes.wintypes as wt
import sys

sys.stdout.reconfigure(encoding="utf-8")
u = ctypes.windll.user32
pids = {int(p) for p in sys.argv[1:]}
res = []


def cb(h, l):
    pid = wt.DWORD()
    u.GetWindowThreadProcessId(h, ctypes.byref(pid))
    if pid.value not in pids:
        return True
    n = ctypes.create_unicode_buffer(512)
    u.GetWindowTextW(h, n, 512)
    cls = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(h, cls, 256)
    r = wt.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    res.append((pid.value, cls.value, n.value, bool(u.IsWindowVisible(h)),
                r.right - r.left, r.bottom - r.top, r.left, r.top))
    return True


u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p,
                                 ctypes.c_void_p)(cb), 0)
for r in res:
    print(r)
