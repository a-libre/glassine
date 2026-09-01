#!/usr/bin/env python3
"""Generates AppIcon.iconset (PNGs) for Glassine. Run once; build.sh turns it into .icns."""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(OUT, exist_ok=True)

S = 1024
ICON = 824              # macOS icon grid: 824px squircle centered in 1024
R = int(ICON * 0.2237)  # corner radius per Apple's template
OFF = (S - ICON) // 2


def squircle_mask(size, radius, ss=4):
    m = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=radius * ss, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    g = Image.new("RGBA", (size, size))
    px = g.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
        for x in range(size):
            px[x, y] = c
    return g


def build(size=S):
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Body: dark graphite glass
    body = vertical_gradient(ICON, (44, 44, 50), (16, 16, 19))
    mask = squircle_mask(ICON, R)

    # Soft top highlight (glass sheen)
    sheen = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-ICON * 0.2, -ICON * 0.55, ICON * 1.2, ICON * 0.45], fill=(255, 255, 255, 26))
    sheen = sheen.filter(ImageFilter.GaussianBlur(60))
    body = Image.alpha_composite(body, sheen)

    # Warm glow behind the caret
    glow = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = ICON / 2, ICON / 2
    gd.ellipse([cx - 150, cy - 260, cx + 150, cy + 260], fill=(208, 120, 74, 110))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    body = Image.alpha_composite(body, glow)

    # Faint text lines to the left/right of the caret (a page)
    lines = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    line_color = (255, 255, 255, 22)
    lw = 14
    y0 = cy - 170
    for i, w in enumerate([300, 250, 280, 200]):
        y = y0 + i * 92
        ld.rounded_rectangle([cx - 320, y, cx - 320 + w, y + lw], radius=lw // 2, fill=line_color)
    body = Image.alpha_composite(body, lines)

    # The caret
    caret = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    cd = ImageDraw.Draw(caret)
    cw, ch = 26, 380
    cd.rounded_rectangle([cx + 12 - cw / 2, cy - ch / 2, cx + 12 + cw / 2, cy + ch / 2], radius=cw / 2, fill=(224, 137, 95, 255))
    caret_glow = caret.filter(ImageFilter.GaussianBlur(18))
    body = Image.alpha_composite(body, caret_glow)
    body = Image.alpha_composite(body, caret)

    # Subtle inner border
    border = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border)
    bd.rounded_rectangle([1, 1, ICON - 2, ICON - 2], radius=R, outline=(255, 255, 255, 28), width=3)
    body = Image.alpha_composite(body, border)

    body.putalpha(mask)

    # Drop shadow
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    sh.putalpha(mask.point(lambda a: int(a * 0.55)))
    shadow.paste(sh, (OFF, OFF + 18))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(body, (OFF, OFF), body)
    return canvas


master = build()
master.save(os.path.join(HERE, "AppIcon-1024.png"))
for px in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        n = px * scale
        img = master.resize((n, n), Image.LANCZOS)
        name = f"icon_{px}x{px}.png" if scale == 1 else f"icon_{px}x{px}@2x.png"
        img.save(os.path.join(OUT, name))
print("wrote", OUT)
