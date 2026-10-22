#!/usr/bin/env python3
"""Generate the DeskAgent app icon (multi-size .ico) programmatically.

Logo spec from flutter/assets/icons/deskagent_logo.svg (32x32 viewBox):
monitor with blue gradient stroke + orange lightning bolt, on a white
squircle so it reads on both light and dark taskbars.
"""
from PIL import Image, ImageDraw
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent  # DeskAgent/
OUT_ICO = REPO / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico"
OUT_ICO_RES = REPO / "res" / "icon.ico"
OUT_ICO_TRAY = REPO / "res" / "tray-icon.ico"
SIZES = [16, 24, 32, 48, 64, 128, 256]

BLUE = (2, 132, 199)       # #0284c7 stroke base
BLUE_LIGHT = (56, 189, 248)  # #38bdf8 stroke top
ORANGE = (234, 88, 12)     # #ea580c bolt
ORANGE_LIGHT = (251, 146, 60)  # #fb923c
WHITE = (255, 255, 255)


def draw_logo(size: int) -> Image.Image:
    # Supersample x8 for smooth edges, then downscale.
    s = size * 8
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = s / 32.0  # 1 unit = 1 viewBox px

    def ur(v):
        return v * u

    # White rounded-square plate (squircle feel: radius ~22% of canvas).
    plate_r = s * 0.22
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=plate_r, fill=(*WHITE, 255))

    # Monitor: rounded rect 4..28 x 6..22, rx 3.5u(32) scaled, stroke 2.2.
    mon = [ur(4), ur(6), ur(28), ur(22)]
    mon_r = ur(3.5)
    stroke = max(1, round(2.2 * u))
    # Two-tone blue: top half lighter, bottom darker (gradient feel).
    mid_y = (mon[1] + mon[3]) / 2
    d.rounded_rectangle(mon, radius=mon_r, outline=BLUE_LIGHT, width=stroke)
    d.rounded_rectangle([mon[0], mid_y, mon[2], mon[3]], radius=mon_r,
                        outline=BLUE, width=stroke)

    # Stand: (12,26)-(20,26) and (16,22)-(16,26), stroke 2, round caps.
    st = max(1, round(2 * u))
    d.line([ur(12), ur(26), ur(20), ur(26)], fill=BLUE, width=st)
    d.line([ur(16), ur(22), ur(16), ur(26)], fill=BLUE, width=st)

    # Lightning bolt: M18 8.5 L12 14.5 H16 L14 20 L20 13.5 H16 Z (orange).
    bolt = [(ur(18), ur(8.5)), (ur(12), ur(14.5)), (ur(16), ur(14.5)),
            (ur(14), ur(20)), (ur(20), ur(13.5)), (ur(16), ur(13.5))]
    d.polygon(bolt, fill=(*ORANGE, 255))

    # Clip everything back to the rounded plate so nothing spills outside.
    mask = Image.new("L", (s, s), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, s - 1, s - 1], radius=plate_r, fill=255)
    img.putalpha(Image.composite(img.split()[3], Image.new("L", (s, s), 0), mask))

    return img.resize((size, size), Image.LANCZOS)


def main():
    frames = [draw_logo(sz) for sz in SIZES]
    frames[-1].save(OUT_ICO, format="ICO", sizes=[(sz, sz) for sz in SIZES])
    frames[-1].save(OUT_ICO_RES, format="ICO", sizes=[(sz, sz) for sz in SIZES])
    frames[-1].save(OUT_ICO_TRAY, format="ICO", sizes=[(sz, sz) for sz in SIZES])
    prev = Path(REPO / "flutter" / "build" / "windows" / "x64" / "runner" / "Release")
    print(f"ico written: {OUT_ICO} ({OUT_ICO.stat().st_size} bytes)")
    print(f"exe rebuilt with new runner resource will carry the new icon")


if __name__ == "__main__":
    main()
