import io
import os
import struct
from pathlib import Path
from PIL import Image

ALLOWED_BASE = Path(r"C:\Users\chu.mai\Desktop\Remote").resolve()

def _image_to_dib(im: Image.Image) -> bytes:
    """Converts a PIL RGBA image to standard Windows ICO BMP DIB bytes (XOR + AND mask)."""
    im = im.convert("RGBA")
    w, h = im.size
    
    # 1. BITMAPINFOHEADER (40 bytes)
    # Height is doubled in ICO format to account for both XOR and AND masks
    header = struct.pack("<IIIHHIIIIII", 40, w, h * 2, 1, 32, 0, w * h * 4, 0, 0, 0, 0)
    
    # 2. XOR mask: 32-bit BGRA, bottom-up order
    xor_data = bytearray()
    for y in reversed(range(h)):
        for x in range(w):
            r, g, b, a = im.getpixel((x, y))
            xor_data.extend([b, g, r, a])
            
    # 3. AND mask: 1 bit per pixel, bottom-up order, row padded to 32-bit (4-byte) boundary
    and_row_bytes = (w + 31) // 32 * 4
    and_data = bytearray()
    for y in reversed(range(h)):
        row_bits = 0
        for x in range(w):
            _, _, _, a = im.getpixel((x, y))
            # 1 = transparent, 0 = opaque
            if a == 0:
                row_bits |= (1 << (7 - (x % 8)))
            if (x % 8 == 7) or (x == w - 1):
                and_data.append(row_bits)
                row_bits = 0
        # Pad row to 4-byte boundary
        written_bytes = (w + 7) // 8
        padding = and_row_bytes - written_bytes
        if padding > 0:
            and_data.extend([0] * padding)
            
    return header + bytes(xor_data) + bytes(and_data)

def write_windows_ico(images_dict: dict, output_path: str):
    """
    images_dict: dict mapping size (int) -> PIL Image (RGBA)
    output_path: path to save .ico file
    Uses DIB for sizes <= 128 and PNG for 256, strictly adhering to Windows Win32 / GDI specifications.
    """
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
