import io
import os
import struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ALLOWED_BASE = Path(r"C:\Users\chu.mai\Desktop\Remote").resolve()

def _image_to_dib(im: Image.Image) -> bytes:
    """Converts a PIL RGBA image to standard Windows ICO BMP DIB bytes (XOR + AND mask)."""
    im = im.convert("RGBA")
    w, h = im.size
    header = struct.pack("<IIIHHIIIIII", 40, w, h * 2, 1, 32, 0, w * h * 4, 0, 0, 0, 0)
    
    xor_data = bytearray()
    for y in reversed(range(h)):
        for x in range(w):
            r, g, b, a = im.getpixel((x, y))
            xor_data.extend([b, g, r, a])
            
    and_row_bytes = (w + 31) // 32 * 4
    and_data = bytearray()
    for y in reversed(range(h)):
        row_bits = 0
        for x in range(w):
            _, _, _, a = im.getpixel((x, y))
            if a == 0:
                row_bits |= (1 << (7 - (x % 8)))
            if (x % 8 == 7) or (x == w - 1):
                and_data.append(row_bits)
                row_bits = 0
        written_bytes = (w + 7) // 8
        padding = and_row_bytes - written_bytes
        if padding > 0:
            and_data.extend([0] * padding)
            
    return header + bytes(xor_data) + bytes(and_data)

def write_windows_ico(images_dict: dict, output_path: str):
    if ".." in output_path:
        raise ValueError("Invalid relative path traversal")
    target_file = Path(output_path).resolve()
    if not target_file.is_relative_to(ALLOWED_BASE):
        raise ValueError("Target outside allowed base")

    sorted_sizes = sorted(images_dict.keys())
    count = len(sorted_sizes)
    
    encoded_images = []
    for sz in sorted_sizes:
        im = images_dict[sz]
        if sz >= 256:
            buf = io.BytesIO()
            im.save(buf, format="PNG")
            encoded_images.append(buf.getvalue())
        else:
            encoded_images.append(_image_to_dib(im))
            
    header = struct.pack("<HHH", 0, 1, count)
    current_offset = 6 + 16 * count
    
    entries = []
    for i, sz in enumerate(sorted_sizes):
        data = encoded_images[i]
        size_bytes = len(data)
        w = 0 if sz >= 256 else sz
        h = 0 if sz >= 256 else sz
        entry = struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, size_bytes, current_offset)
        entries.append(entry)
        current_offset += size_bytes
        
    target_file.parent.mkdir(parents=True, exist_ok=True)
    with target_file.open("wb") as f:
        f.write(header)
        for e in entries:
            f.write(e)
        for p in encoded_images:
            f.write(p)

def create_app_icon_master(size=1024):
    """
    Windows 11 Fluent App Icon:
    Dark Mica/Acrylic Squircle + Glowing Cyan Monitor + Golden Spark + Online Pip
    """
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # 1. Soft Ambient Shadow
    s_margin = 48
    s_radius = 210
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_box = [s_margin, s_margin + 24, size - s_margin, size - s_margin + 24]
    s_draw.rounded_rectangle(s_box, radius=s_radius, fill=(0, 0, 0, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=32))
    im.paste(shadow, (0, 0), shadow)
    
    # 2. Windows 11 Dark Acrylic Squircle Base
    m = 56
    r = 200
    box = [m, m, size - m, size - m]
    # Smooth gradient simulation or rich dark mica fill
    draw.rounded_rectangle(box, radius=r, fill=(28, 33, 43, 255), outline=(96, 205, 255, 60), width=4)
    
    # Inner subtle glow
    inner_box = [m + 4, m + 4, size - m - 4, size - m - 4]
    draw.rounded_rectangle(inner_box, radius=r - 4, fill=None, outline=(255, 255, 255, 20), width=2)
    
    # 3. Remote Monitor Display
    # Screen body
    mon_x = 220
    mon_y = 240
    mon_w = 584
    mon_h = 390
    mon_r = 56
    stroke_w = 44
    
    # Monitor Screen Bezel (Fluent Cyan #60CDFF)
    draw.rounded_rectangle(
        [mon_x, mon_y, mon_x + mon_w, mon_y + mon_h],
        radius=mon_r,
        fill=(18, 22, 30, 255),
        outline=(96, 205, 255, 255),
        width=stroke_w
    )
    
    # Monitor Stand Stem
    stem_w = 48
    stem_x = (size - stem_w) // 2
    stem_y1 = mon_y + mon_h - 10
    stem_y2 = 710
    draw.rectangle([stem_x, stem_y1, stem_x + stem_w, stem_y2], fill=(96, 205, 255, 255))
    
    # Monitor Base Bar
    base_w = 260
    base_h = 38
    base_x = (size - base_w) // 2
    draw.rounded_rectangle(
        [base_x, stem_y2 - 10, base_x + base_w, stem_y2 - 10 + base_h],
        radius=19,
        fill=(96, 205, 255, 255)
    )
    
    # 4. Perfectly Centered Electric Spark / Lightning Bolt (#FBBF24 Amber Gold)
    # Monitor screen inner center is at (512, 435) - Centro-symmetric aligned
    cx = 512
    cy = 435
    bolt_pts = [
        (cx + 32, cy - 145),
        (cx - 96, cy + 8),
        (cx - 8, cy + 8),
        (cx - 32, cy + 145),
        (cx + 96, cy - 8),
        (cx + 8, cy - 8),
    ]
    draw.polygon(bolt_pts, fill=(251, 191, 36, 255))
    
    # 5. Online Status Pip at Bottom-Right of Screen (#10B981)
    pip_cx = mon_x + mon_w - 20
    pip_cy = mon_y + mon_h - 20
    pip_r = 44
    # Dark ring border
    draw.ellipse(
        [pip_cx - pip_r - 10, pip_cy - pip_r - 10, pip_cx + pip_r + 10, pip_cy + pip_r + 10],
        fill=(28, 33, 43, 255)
    )
    # Emerald green dot
    draw.ellipse(
        [pip_cx - pip_r, pip_cy - pip_r, pip_cx + pip_r, pip_cy + pip_r],
        fill=(16, 185, 129, 255)
    )
    
    return im

def create_tray_icon_master(size=1024):
    """
    Windows 11 Transparent System Tray Icon:
    Full-bleed silhouette monitor + lightning bolt + status pip (NO background squircle).
    Crisp outline optimized for dark taskbar.
    """
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Monitor dimensions - large and clear
    mon_x = 96
    mon_y = 120
    mon_w = 832
    mon_h = 560
    mon_r = 80
    stroke_w = 64
    
    # Monitor bezel
    draw.rounded_rectangle(
        [mon_x, mon_y, mon_x + mon_w, mon_y + mon_h],
        radius=mon_r,
        fill=(0, 0, 0, 0),
        outline=(96, 205, 255, 255),
        width=stroke_w
    )
    
    # Monitor Stand Stem
    stem_w = 68
    stem_x = (size - stem_w) // 2
    stem_y1 = mon_y + mon_h - 10
    stem_y2 = 790
    draw.rectangle([stem_x, stem_y1, stem_x + stem_w, stem_y2], fill=(96, 205, 255, 255))
    
    # Monitor Base Bar
    base_w = 380
    base_h = 56
    base_x = (size - base_w) // 2
    draw.rounded_rectangle(
        [base_x, stem_y2 - 10, base_x + base_w, stem_y2 - 10 + base_h],
        radius=28,
        fill=(96, 205, 255, 255)
    )
    
    # Centered Lightning Bolt (#FBBF24) - Centro-symmetric aligned
    cx = 512
    cy = mon_y + (mon_h // 2) - 10
    bolt_pts = [
        (cx + 40, cy - 180),
        (cx - 120, cy + 10),
        (cx - 10, cy + 10),
        (cx - 40, cy + 180),
        (cx + 120, cy - 10),
        (cx + 10, cy - 10),
    ]
    draw.polygon(bolt_pts, fill=(251, 191, 36, 255))
    
    # Online Pip at Bottom-Right (#10B981)
    pip_cx = mon_x + mon_w - 30
    pip_cy = mon_y + mon_h - 30
    pip_r = 72
    draw.ellipse(
        [pip_cx - pip_r - 14, pip_cy - pip_r - 14, pip_cx + pip_r + 14, pip_cy + pip_r + 14],
        fill=(0, 0, 0, 255)
    )
    draw.ellipse(
        [pip_cx - pip_r, pip_cy - pip_r, pip_cx + pip_r, pip_cy + pip_r],
        fill=(16, 185, 129, 255)
    )
    
    return im

def main():
    root = Path(r"C:\Users\chu.mai\Desktop\Remote\DeskAgent").resolve()
    print("Generating master icons...")
    app_master = create_app_icon_master(1024)
    tray_master = create_tray_icon_master(1024)
    
    sizes = [16, 24, 32, 48, 64, 128, 256]
    app_dict = {s: app_master.resize((s, s), Image.Resampling.LANCZOS) for s in sizes}
    tray_dict = {s: tray_master.resize((s, s), Image.Resampling.LANCZOS) for s in sizes}
    
    # 1. App ICO targets
    app_ico_targets = [
        str(root / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico"),
        str(root / "flutter" / "assets" / "icon.ico"),
        str(root / "res" / "icon.ico"),
    ]
    for target in app_ico_targets:
        write_windows_ico(app_dict, target)
        print(f"Generated App ICO: {target}")
        
    # 2. Tray ICO targets (transparent background!)
    tray_ico_target = str(root / "res" / "tray-icon.ico")
    write_windows_ico(tray_dict, tray_ico_target)
    print(f"Generated Tray ICO (transparent): {tray_ico_target}")
    
    # 3. PNG targets
    png_targets = [
        (str(root / "res" / "icon.png"), 512),
        (str(root / "res" / "128x128@2x.png"), 256),
        (str(root / "res" / "128x128.png"), 128),
        (str(root / "res" / "64x64.png"), 64),
        (str(root / "res" / "32x32.png"), 32),
        (str(root / "flutter" / "assets" / "icon.png"), 256),
    ]
    for target, sz in png_targets:
        if ".." in target:
            continue
        p = Path(target).resolve()
        p.parent.mkdir(parents=True, exist_ok=True)
        im = app_master.resize((sz, sz), Image.Resampling.LANCZOS)
        im.save(str(p), format="PNG")
        print(f"Generated PNG {sz}x{sz}: {target}")

    # 4. Generate clean SVG logo (symmetrical centered lightning bolt)
    svg_content = '''<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3.5" y="4.5" width="25" height="16.5" rx="3.5" stroke="#60CDFF" stroke-width="2.0" fill="#1C212B"/>
  <path d="M11.5 26.5H20.5M16 21V26.5" stroke="#60CDFF" stroke-width="2.0" stroke-linecap="round"/>
  <path d="M17 7.95L13 13.05H15.8L15 17.55L19 12.45H16.2L17 7.95Z" fill="#FBBF24"/>
  <circle cx="26" cy="18.5" r="3.6" fill="#1C212B"/>
  <circle cx="26" cy="18.5" r="2.4" fill="#10B981"/>
</svg>'''
    
    svg_targets = [
        root / "res" / "logo.svg",
        root / "flutter" / "assets" / "icon.svg",
    ]
    for svg_path in svg_targets:
        svg_path.write_text(svg_content, encoding="utf-8")
        print(f"Generated SVG: {svg_path}")
        
    print("All icons successfully generated!")

if __name__ == "__main__":
    main()
