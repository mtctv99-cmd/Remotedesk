import ctypes
import ctypes.wintypes as wt
import sys

sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image

h = int(sys.argv[1], 0)
u = ctypes.windll.user32
g = ctypes.windll.gdi32
u.ShowWindow(h, 9)
ctypes.windll.kernel32.Sleep(800)
r = wt.RECT()
u.GetWindowRect(h, ctypes.byref(r))
w, ht = r.right - r.left, r.bottom - r.top
print("rect", r.left, r.top, w, ht)
hdc = u.GetWindowDC(h)
mdc = g.CreateCompatibleDC(hdc)
bmp = g.CreateCompatibleBitmap(hdc, w, ht)
g.SelectObject(mdc, bmp)
u.PrintWindow(h, mdc, 2)
buf = ctypes.create_string_buffer(w * ht * 4)


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG),
                ("biHeight", wt.LONG), ("biPlanes", wt.WORD),
                ("biBitCount", wt.WORD), ("biCompression", wt.DWORD),
                ("biSizeImage", wt.DWORD), ("biXPelsPerMeter", wt.LONG),
                ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD),
                ("biClrImportant", wt.DWORD)]


bi = BITMAPINFOHEADER()
bi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
bi.biWidth = w
bi.biHeight = -ht
bi.biPlanes = 1
bi.biBitCount = 32
g.GetDIBits(mdc, bmp, 0, ht, buf, ctypes.byref(bi), 0)
img = Image.frombuffer("RGBA", (w, ht), buf, "raw", "BGRA", 0, 1)
img.convert("RGB").save(sys.argv[2])
print("saved", sys.argv[2])
