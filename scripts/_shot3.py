import ctypes
import ctypes.wintypes as wt
import sys

sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image

pid = int(sys.argv[1])
u = ctypes.windll.user32
g = ctypes.windll.gdi32
found = []


def cb(h, l):
    p = wt.DWORD()
    u.GetWindowThreadProcessId(h, ctypes.byref(p))
    cls = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(h, cls, 256)
    if p.value == pid and cls.value == "FLUTTER_RUNNER_WIN32_WINDOW":
        found.append(h)
    return True


u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p,
                                 ctypes.c_void_p)(cb), 0)
print("handles", found)
for h in found:
    u.ShowWindow(h, 9)
    ctypes.windll.kernel32.Sleep(1200)
    r = wt.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    w, ht = r.right - r.left, r.bottom - r.top
    print("hwnd", h, "rect", r.left, r.top, w, ht,
          "visible", bool(u.IsWindowVisible(h)),
          "iconic", bool(u.IsIconic(h)))
    if w <= 0 or ht <= 0:
        continue
    hdc = u.GetWindowDC(h)
    mdc = g.CreateCompatibleDC(hdc)
    bmp = g.CreateCompatibleBitmap(hdc, w, ht)
    g.SelectObject(mdc, bmp)
    u.PrintWindow(h, mdc, 2)
    buf = ctypes.create_string_buffer(w * ht * 4)

    class BIH(ctypes.Structure):
        _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG),
                    ("biHeight", wt.LONG), ("biPlanes", wt.WORD),
                    ("biBitCount", wt.WORD), ("biCompression", wt.DWORD),
                    ("biSizeImage", wt.DWORD), ("biXPelsPerMeter", wt.LONG),
                    ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD),
                    ("biClrImportant", wt.DWORD)]

    bi = BIH()
    bi.biSize = ctypes.sizeof(BIH)
    bi.biWidth = w
    bi.biHeight = -ht
    bi.biPlanes = 1
    bi.biBitCount = 32
    g.GetDIBits(mdc, bmp, 0, ht, buf, ctypes.byref(bi), 0)
    img = Image.frombuffer("RGBA", (w, ht), buf, "raw", "BGRA", 0, 1)
    img.convert("RGB").save(sys.argv[2])
    print("saved", sys.argv[2])
