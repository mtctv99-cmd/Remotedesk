import os
from PIL import Image, ImageDraw, ImageFilter

def create_deskagent_icon(size=256):
    scale = 4
    canvas_size = 256 * scale # 1024
    im = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    # 1. Background Squircle (Windows 11 Fluent App Icon style)
    m = 16 * scale # 64
    r = 54 * scale # 216
    box = [m, m, canvas_size - m, canvas_size - m]

    # Drop shadow
    shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_box = [m, m + 6 * scale, canvas_size - m, canvas_size - m + 6 * scale]
    s_draw.rounded_rectangle(s_box, radius=r, fill=(0, 0, 0, 46))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=8 * scale))
    im.paste(shadow, (0, 0), shadow)

    # White Squircle base with subtle crisp border
    draw.rounded_rectangle(box, radius=r, fill=(255, 255, 255, 255), outline=(226, 232, 240, 255), width=2 * scale)

    # 2. Monitor Screen (Blue #0284c7)
    mon_x = 240
    mon_y = 240
    mon_w = 544
    mon_h = 360
    mon_r = 80
    stroke_w = 52

    # Screen fill
    draw.rounded_rectangle(
        [mon_x, mon_y, mon_x + mon_w, mon_y + mon_h],
        radius=mon_r,
        fill=(240, 249, 255, 255),
        outline=(2, 132, 199, 255),
        width=stroke_w
    )

    # Monitor Stem & Base
    stem_w = 48
    stem_x = (canvas_size - stem_w) // 2
    stem_y1 = mon_y + mon_h - 10
    stem_y2 = 688
    draw.rectangle([stem_x, stem_y1, stem_x + stem_w, stem_y2], fill=(2, 132, 199, 255))

    # Monitor Base Bar
    base_w = 210
    base_h = 44
    base_x = (canvas_size - base_w) // 2
    draw.rounded_rectangle(
        [base_x, stem_y2 - 10, base_x + base_w, stem_y2 - 10 + base_h],
        radius=22,
        fill=(2, 132, 199, 255)
    )

    # 3. Bold Lightning Bolt (Vibrant Orange #ea580c)
    bolt_pts = [
        (566, 286),
        (406, 436),
        (512, 436),
        (458, 568),
        (618, 410),
        (512, 410),
    ]
    draw.polygon(bolt_pts, fill=(234, 88, 12, 255))

    # 4. Status Pip: Online Green (#22c55e)
    pip_cx = 726
    pip_cy = 680
    pip_r = 46
    # White border ring
    draw.ellipse(
        [pip_cx - pip_r - 12, pip_cy - pip_r - 12, pip_cx + pip_r + 12, pip_cy + pip_r + 12],
        fill=(255, 255, 255, 255)
    )
    # Green pip
    draw.ellipse(
        [pip_cx - pip_r, pip_cy - pip_r, pip_cx + pip_r, pip_cy + pip_r],
        fill=(34, 197, 94, 255)
    )

    final_img = im.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

def main():
    root = os.path.dirname(os.path.abspath(__file__))
    img256 = create_deskagent_icon(256)
    img512 = create_deskagent_icon(512)

    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

    # Targets for .ico
    ico_targets = [
        os.path.join(root, "flutter", "windows", "runner", "resources", "app_icon.ico"),
        os.path.join(root, "flutter", "assets", "icon.ico"),
        os.path.join(root, "res", "icon.ico"),
        os.path.join(root, "res", "tray-icon.ico"),
        os.path.join(root, "flutter", "build", "windows", "x64", "runner", "Release", "data", "flutter_assets", "assets", "icon.ico"),
    ]

    for target in ico_targets:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        img256.save(target, format="ICO", sizes=ico_sizes)
        print(f"Generated ICO: {target} ({os.path.getsize(target)} bytes)")

    # Targets for .png
    png_targets = [
        (os.path.join(root, "res", "icon.png"), 512),
        (os.path.join(root, "res", "128x128@2x.png"), 256),
        (os.path.join(root, "res", "128x128.png"), 128),
        (os.path.join(root, "res", "64x64.png"), 64),
        (os.path.join(root, "res", "32x32.png"), 32),
        (os.path.join(root, "flutter", "assets", "icon.png"), 256),
    ]

    for target, sz in png_targets:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        im = img512.resize((sz, sz), Image.Resampling.LANCZOS)
        im.save(target, format="PNG")
        print(f"Generated PNG: {target} ({sz}x{sz}, {os.path.getsize(target)} bytes)")

    print("All DeskAgent icon assets updated successfully!")

if __name__ == "__main__":
    main()
