"""Window captures taken by hand — CleanShot, or ⇧⌘4 then space: the window
with its shadow on transparency — turned into App Store pictures at 2880 × 1800:

  python3 docs/appstore/from-captures.py <folder of captures> <output folder> [names…]

Each capture is found by the opaque rectangle inside the shadow, which must be
2880 × 1800: a 1440 × 900 window on a Retina display (Help → Window at 1440 × 900
in the demonstration copy). Two sets come out, both opaque RGB, as the store
requires — App Store Connect takes 1280 × 800, 1440 × 900, 2560 × 1600 or
2880 × 1800, and nothing with an alpha channel:

  App Store 2880x1800/             the window itself, edge to edge, 1:1 pixels; its
                                   rounded corners squared off from the pixels beside them
  App Store 2880x1800 (floating)/  the window with its shadow on a quiet background, at 90%

Mind image optimisers that watch folders (Clop, say): one turned every PNG
written into the capture folder into 256 colours, the captures included.
Pause it, or capture into a folder it does not watch. Needs Pillow and numpy.
"""
import glob, os, sys
import numpy as np
from PIL import Image, ImageFilter


SRC = sys.argv[1]
OUT = sys.argv[2]
NAMES = sys.argv[3:]  # one per file, in sorted order; falls back to numbers
W, H = 2880, 1800

def window_rect(alpha):
    cols = np.where((alpha == 255).sum(axis=0) > 1000)[0]
    rows = np.where((alpha == 255).sum(axis=1) > 1000)[0]
    return cols.min(), rows.min(), cols.max() + 1, rows.max() + 1

def flatten(rgba):
    """The window's rounded corners made square, as if the window went on:
    the corner filled with the sidebar's or page's own colour from just
    inside, and the window's edge highlight drawn straight through it.
    Nothing partly transparent is left."""
    a = np.array(rgba).astype(np.int32)
    h, w = a.shape[:2]
    alpha = a[:, :, 3]
    # The corner radius: how far along the top edge the first opaque pixel is.
    r = int(np.argmax(alpha[0, :] == 255)) + 2
    n = r + 6
    edge = 2  # the highlight along the window's edge, in pixels
    def fix(ys, xs, sample_y, sample_x, top_src, left_src):
        # ys, xs: index arrays addressing the corner square; sample: interior strip for the fill
        block = a[np.ix_(ys, xs)]
        fill = np.median(a[np.ix_(sample_y, sample_x)][:, :, :3].reshape(-1, 3), axis=0)
        cy, cx = (r - 1) if ys[0] == 0 else (n - r), (r - 1) if xs[0] == 0 else (n - r)
        yy, xx = np.mgrid[0:n, 0:n]
        outside = (block[:, :, 3] < 255) | (np.hypot(yy - cy, xx - cx) > r - 3)
        block[outside, :3] = fill.round().astype(np.int32)
        block[:, :, 3] = 255
        a[np.ix_(ys, xs)] = block
        # the edge highlight, copied from a straight stretch of the same edge
        a[np.ix_(top_src[0], xs)] = a[np.ix_(top_src[0], top_src[1])]
        a[np.ix_(ys, left_src[1])] = a[np.ix_(left_src[0], left_src[1])]
    rows_t, rows_b = np.arange(0, n), np.arange(h - n, h)
    cols_l, cols_r = np.arange(0, n), np.arange(w - n, w)
    inner = np.arange(n + 2, n + 8)
    # top-left
    fix(rows_t, cols_l, np.arange(edge + 2, edge + 8), inner,
        (np.arange(0, edge), np.arange(n + 4, 2 * n + 4)), (np.arange(n + 4, 2 * n + 4), np.arange(0, edge)))
    # top-right
    fix(rows_t, cols_r, np.arange(edge + 2, edge + 8), np.arange(w - n - 8, w - n - 2),
        (np.arange(0, edge), np.arange(w - 2 * n - 4, w - n - 4)), (np.arange(n + 4, 2 * n + 4), np.arange(w - edge, w)))
    # bottom-left
    fix(rows_b, cols_l, np.arange(h - edge - 8, h - edge - 2), inner,
        (np.arange(h - edge, h), np.arange(n + 4, 2 * n + 4)), (np.arange(h - 2 * n - 4, h - n - 4), np.arange(0, edge)))
    # bottom-right
    fix(rows_b, cols_r, np.arange(h - edge - 8, h - edge - 2), np.arange(w - n - 8, w - n - 2),
        (np.arange(h - edge, h), np.arange(w - 2 * n - 4, w - n - 4)), (np.arange(h - 2 * n - 4, h - n - 4), np.arange(w - edge, w)))
    # A tool that saves 8-bit PNGs leaves a few edge pixels part-transparent
    # by rounding; their colour is the edge's, so they are simply opaque now.
    a[:, :, 3] = 255
    return Image.fromarray(a[:, :, :3].astype(np.uint8), "RGB")

def full(rgba, rect):
    x0, y0, x1, y1 = rect
    win = rgba.crop((x0, y0, x1, y1))
    assert win.size == (W, H), win.size
    return flatten(win)

def floating(rgba, rect, scale=0.9, top=70):
    """The whole capture, shadow and all, at `scale`, the window's top at `top`
    on a background drawn from the window's own tones."""
    x0, y0, x1, y1 = rect
    win = np.array(rgba.crop((x0, y0, x1, y1)).convert("RGB")).astype(np.float32)
    mean = win.reshape(-1, 3).mean(axis=0)
    lum = mean @ np.array([0.299, 0.587, 0.114])
    if lum < 128:
        c_top = np.clip(mean * 0.55 + 6, 0, 255)
        c_bot = np.clip(mean * 0.30, 0, 255)
    else:
        c_top = np.clip(mean * 0.35 + 170, 0, 255)
        c_bot = np.clip(mean * 0.25 + 150, 0, 255)
    t = np.linspace(0, 1, H)[:, None, None]
    bg = (c_top[None, None, :] * (1 - t) + c_bot[None, None, :] * t)
    bg = Image.fromarray(bg.repeat(W, axis=1).round().astype(np.uint8), "RGB").convert("RGBA")
    sw, sh = round(rgba.width * scale), round(rgba.height * scale)
    small = rgba.resize((sw, sh), Image.LANCZOS)
    # place so the window lands centred horizontally with its top at `top`
    wx = round(x0 * scale); wy = round(y0 * scale); ww = round((x1 - x0) * scale)
    px = (W - ww) // 2 - wx
    py = top - wy
    canvas = bg.copy()
    canvas.alpha_composite(small, (px, py))
    return canvas.convert("RGB")

files = sorted(glob.glob(os.path.join(SRC, "*.png")))
FULL, FLOAT = "App Store 2880x1800", "App Store 2880x1800 (floating)"
os.makedirs(os.path.join(OUT, FULL), exist_ok=True)
os.makedirs(os.path.join(OUT, FLOAT), exist_ok=True)
for i, f in enumerate(files):
    rgba = Image.open(f).convert("RGBA")
    rect = window_rect(np.array(rgba)[:, :, 3])
    name = NAMES[i] if i < len(NAMES) else f"{i + 1:02d}"
    a = full(rgba, rect); a.save(os.path.join(OUT, FULL, f"{name}.png"))
    b = floating(rgba, rect); b.save(os.path.join(OUT, FLOAT, f"{name}.png"))
    print(name, rect, a.size, b.size, flush=True)
