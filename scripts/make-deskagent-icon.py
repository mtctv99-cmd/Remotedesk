"""Trim a generated logo into DeskAgent app icons.

Usage:
    python scripts/make-deskagent-icon.py path/to/logo.png

The source is cropped to the non-background artwork, squared with transparent
padding, given a Windows-11-style rounded mask, then written to:
    flutter/assets/icon.png                       (runtime logo)
    flutter/assets/icons/deskagent_logo.png       (widget brand mark)
    flutter/windows/runner/resources/app_icon.ico (exe icon)
    res/icon.ico                                  (packaging icon)
    res/tray-icon.ico                             (tray icon)
    reports/logo-preview.png                      (review preview)
"""

from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def background_color(im: Image.Image) -> tuple[int, int, int, int]:
    w, h = im.size
    points = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    samples = [im.getpixel(p) for p in points]
    return tuple(sum(c[i] for c in samples) // len(samples) for i in range(4))


def trim(im: Image.Image) -> Image.Image:
    bg = background_color(im)
    solid = Image.new("RGBA", im.size, bg)
    diff = ImageChops.difference(im, solid).convert("L")
    bbox = diff.point(lambda v: 255 if v > 24 else 0).getbbox()
    if bbox is None:
        return im
    pad = max(2, int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.01))
    box = (
        max(0, bbox[0] - pad),
        max(0, bbox[1] - pad),
        min(im.width, bbox[2] + pad),
        min(im.height, bbox[3] + pad),
    )
    return im.crop(box)


def square(im: Image.Image, size: int = 1024) -> Image.Image:
    side = max(im.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2), im)
    return canvas.resize((size, size), Image.LANCZOS)


def rounded(im: Image.Image, radius_ratio: float = 0.22) -> Image.Image:
    size = im.size[0]
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    out = im.copy()
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    if not src.is_file():
        print(f"missing source: {src}")
        return 2

    im = rounded(square(trim(Image.open(src).convert("RGBA"))))

    outputs = {
        ROOT / "flutter/assets/icon.png": 512,
        ROOT / "flutter/assets/icons/deskagent_logo.png": 512,
        ROOT / "res/icon.png": 1024,
        ROOT / "reports/logo-preview.png": 512,
    }
    for path, size in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        im.resize((size, size), Image.LANCZOS).save(path)
        print(f"wrote {path} ({size}x{size})")

    for ico in [
        ROOT / "flutter/windows/runner/resources/app_icon.ico",
        ROOT / "res/icon.ico",
        ROOT / "res/tray-icon.ico",
    ]:
        ico.parent.mkdir(parents=True, exist_ok=True)
        im.save(ico, sizes=SIZES)
        print(f"wrote {ico} ({', '.join(f'{w}x{h}' for w, h in SIZES)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
