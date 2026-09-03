#!/usr/bin/env python3
"""Generates AppIcon.iconset (PNGs) for Glassine. Run once; build.sh turns it into .icns.

The mark is the wordmark's lowercase g on a sheet of paper, with ruled lines
running in from the left and fading out — lines of text arriving at the letter.
The g is drawn from its geometry (a ring, a stem, a hook) rather than a font, so
the icon is reproducible anywhere and the letter matches the wordmark exactly.

Every size is rendered on its own rather than shrunk from the 1024 master, so
the ruled lines can stay a whole pixel wide where the master's would vanish.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(OUT, exist_ok=True)

# Apple's macOS icon grid: an 824-point squircle centred in 1024, and the
# corner radius from the template. Everything below is in these 1024-point
# units and scaled at render time.
S = 1024
ICON = 824
R = ICON * 0.2237
OFF = (S - ICON) / 2

PAPER_TOP, PAPER_BOTTOM = (249, 248, 245), (238, 237, 233)
INK_TOP, INK_BOTTOM = (38, 38, 41), (62, 62, 66)
RULE = (40, 40, 44)

# --- The letter -------------------------------------------------------------------------------
# Measured from the wordmark's g, in a 279×428 box: a near-monoline bowl, a
# stem on the right, and a hook that is the lower half of a second ring.
G_W, G_H = 279, 428
G_HEIGHT = 446                      # points, in the 1024 icon
G_RIGHT = OFF + ICON * 0.80         # where the stem's right edge sits
G_TOP = OFF + (ICON - G_HEIGHT) / 2 - 6


def draw_g(canvas_size, x, y, height, fill, silhouette=False):
    """The g as an L mask on a canvas_size square, top-left at (x, y), this tall.
    With silhouette=True the counters are filled: the letter's outline, used to
    stop the ruled lines at its edge rather than letting them cross the bowl."""
    k = height / G_H
    m = Image.new("L", (canvas_size, canvas_size), 0)
    d = ImageDraw.Draw(m)

    def E(box, v):
        d.ellipse([x + box[0] * k, y + box[1] * k, x + box[2] * k, y + box[3] * k], fill=v)

    def Rc(box, v):
        d.rectangle([x + box[0] * k, y + box[1] * k, x + box[2] * k, y + box[3] * k], fill=v)

    E([0, 0, 264, 304], fill)                        # bowl, outer
    if not silhouette:
        E([26, 28, 246, 276], 0)                     # bowl, counter
    Rc([246, 0, 278, 340], fill)                     # stem
    hook = Image.new("L", m.size, 0)
    hd = ImageDraw.Draw(hook)
    hd.ellipse([x + 16 * k, y + 252 * k, x + 278 * k, y + 428 * k], fill=255)
    if not silhouette:
        hd.ellipse([x + 46 * k, y + 280 * k, x + 246 * k, y + 400 * k], fill=0)
    hd.rectangle([0, 0, m.width, y + 338 * k], fill=0)   # lower half only; the cut is the terminal
    m.paste(fill, (0, 0), hook)
    return m


def vertical_gradient(size, top, bottom):
    strip = Image.new("RGBA", (1, size))
    for yy in range(size):
        t = yy / max(1, size - 1)
        strip.putpixel((0, yy), tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,))
    return strip.resize((size, size))


def squircle(size, ss):
    m = Image.new("L", (size * ss, size * ss), 0)
    # `size` here is the art's width in pixels, so the radius scales by the art's width in points.
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=R * size / ICON * ss, fill=255)
    return m.resize((size, size), Image.LANCZOS)


# Where each ruled line starts, as a fraction of the way across the art, and
# the rows they sit on: evenly over the bowl and stem, never the hook, like the
# wordmark study they come from.
RULE_STARTS = [0.09, 0.17, 0.12, 0.07, 0.20, 0.10, 0.15]


def build(size):
    ss = 4 if size <= 128 else 2                       # supersample; small sizes need it most
    k = size / S                                       # points → pixels
    W = size * ss                                      # working canvas, in supersampled pixels
    icon_px = ICON * k * ss
    off_px = OFF * k * ss

    art = vertical_gradient(int(round(icon_px)), PAPER_TOP, PAPER_BOTTOM)
    n = art.width
    # A breath of light across the top, so the paper reads as a surface.
    sheen = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse([-n * 0.2, -n * 0.6, n * 1.2, n * 0.4], fill=(255, 255, 255, 60))
    art = Image.alpha_composite(art, sheen.filter(ImageFilter.GaussianBlur(n * 0.08)))

    # Letter geometry in art pixels
    gx = (G_RIGHT - OFF) * k * ss - G_W * (G_HEIGHT * k * ss / G_H)
    gy = (G_TOP - OFF) * k * ss
    gh = G_HEIGHT * k * ss
    gk = gh / G_H

    # Ruled lines: fade in from the left, stop at the letter's edge.
    rules_on = size >= 32
    if rules_on:
        count = 7 if size >= 64 else 3
        rows = [gy + (0.06 + 0.66 * i / 6) * gh for i in range(7)]
        if count == 3:
            rows = [rows[0], rows[3], rows[6]]
            starts = [RULE_STARTS[0], RULE_STARTS[3], RULE_STARTS[6]]
        else:
            starts = RULE_STARTS
        thickness = max(1.0 * ss, 7.0 * k * ss)                      # never thinner than a pixel
        alpha_max = 0.34 if size >= 64 else 0.5
        rules = Image.new("L", (n, n), 0)
        rd = ImageDraw.Draw(rules)
        x_end = gx + 262 * gk                                        # to the stem's middle, never past it
        for row, start in zip(rows, starts):
            x0 = start * n
            length = x_end - x0
            steps = 96
            for i in range(steps):
                t = i / steps
                a = int(255 * alpha_max * (t ** 1.4))
                xa = x0 + length * t
                xb = x0 + length * (i + 1) / steps
                rd.rectangle([xa, row - thickness / 2, xb + 1, row + thickness / 2], fill=a)
        letter_outline = draw_g(n, gx, gy, gh, 255, silhouette=True)
        rules.paste(0, (0, 0), letter_outline.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.5 * ss)))
        ink = Image.new("RGBA", (n, n), RULE + (255,))
        ink.putalpha(rules)
        art = Image.alpha_composite(art, ink)

    # The letter itself, in ink that darkens toward the top like the wordmark study.
    letter = draw_g(n, gx, gy, gh, 255)
    ink = vertical_gradient(n, INK_TOP, INK_BOTTOM)
    ink.putalpha(letter)
    art = Image.alpha_composite(art, ink)

    # A hairline edge so the sheet has a boundary on a white desktop too.
    edge = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([0.5, 0.5, n - 1.5, n - 1.5], radius=R * k * ss, outline=(0, 0, 0, 22), width=max(1, int(3 * k * ss)))
    art = Image.alpha_composite(art, edge)

    art.putalpha(squircle(n, 1) if ss == 1 else squircle(n, 2))

    # Shadow, then the sheet on top.
    canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sh = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh.putalpha(art.split()[3].point(lambda a: int(a * 0.45)))
    shadow.paste(sh, (int(off_px), int(off_px + 18 * k * ss)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * k * ss))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(art, (int(off_px), int(off_px)), art)
    return canvas.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    build(1024).save(os.path.join(HERE, "AppIcon-1024.png"))
    for px in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            n = px * scale
            name = f"icon_{px}x{px}.png" if scale == 1 else f"icon_{px}x{px}@2x.png"
            build(n).save(os.path.join(OUT, name))
    print("wrote", OUT)
