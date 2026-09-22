#!/usr/bin/env python3
"""The same sheet of paper as make_icon.py, full-bleed for iOS: no squircle,
no shadow, no hairline — the phone cuts the corners itself. Writes both
appearances into ios/Assets.xcassets/AppIcon.appiconset.
   python3 Resources/make_ios_icon.py
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ios", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)


def render(variant):
    sys.argv = [sys.argv[0]] + (["--dark"] if variant == "dark" else [])
    for m in [k for k in sys.modules if k == "make_icon"]:
        del sys.modules[m]
    sys.path.insert(0, HERE)
    import make_icon as M
    P = M.P
    ss = 2
    n = 1024 * ss                                      # the art itself is the whole icon
    k = n / M.ICON                                     # icon points → art pixels
    art = M.vertical_gradient(n, M.PAPER_TOP, M.PAPER_BOTTOM)
    sheen = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse([-n * 0.2, -n * 0.6, n * 1.2, n * 0.4], fill=P["sheen"])
    art = Image.alpha_composite(art, sheen.filter(ImageFilter.GaussianBlur(n * 0.08)))

    gx = (M.G_RIGHT - M.OFF) * k - M.G_W * (M.G_HEIGHT * k / M.G_H)
    gy = (M.G_TOP - M.OFF) * k
    gh = M.G_HEIGHT * k
    gk = gh / M.G_H

    rows = [gy + (0.06 + 0.66 * i / 6) * gh for i in range(7)]
    thickness = 7.0 * k
    rules = Image.new("L", (n, n), 0)
    rd = ImageDraw.Draw(rules)
    x_end = gx + 262 * gk
    for row, start in zip(rows, M.RULE_STARTS):
        x0 = start * n
        length = x_end - x0
        steps = 96
        for i in range(steps):
            t = i / steps
            a = int(255 * 0.34 * (t ** 1.4))
            rd.rectangle([x0 + length * t, row - thickness / 2, x0 + length * (i + 1) / steps + 1, row + thickness / 2], fill=a)
    outline = M.draw_g(n, gx, gy, gh, 255, silhouette=True)
    rules.paste(0, (0, 0), outline.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.5 * ss)))
    ink = Image.new("RGBA", (n, n), M.RULE + (255,))
    ink.putalpha(rules)
    art = Image.alpha_composite(art, ink)

    letter = M.draw_g(n, gx, gy, gh, 255)
    ink = M.vertical_gradient(n, M.INK_TOP, M.INK_BOTTOM)
    ink.putalpha(letter)
    art = Image.alpha_composite(art, ink)
    return art.convert("RGB").resize((1024, 1024), Image.LANCZOS)


render("light").save(os.path.join(OUT, "AppIcon-Light.png"))
render("dark").save(os.path.join(OUT, "AppIcon-Dark.png"))
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    f.write('''{
  "images" : [
    { "filename" : "AppIcon-Light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''')
with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
    f.write('{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
print("wrote", OUT)
