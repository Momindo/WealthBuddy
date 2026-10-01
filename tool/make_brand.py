"""Renders the WealthBuddy mark (steps rising to a gold coin) to the PNGs the icon and splash tools need.
Geometry matches lib/ui/logo.dart: a 100x100 box, path 22,74 → 40,74 → 40,58 → 58,58 → 58,42 → 72,42, coin at 72,27 r=9."""
from PIL import Image, ImageDraw

TEAL, GOLD, WHITE = (15, 92, 77, 255), (216, 173, 94, 255), (255, 255, 255, 255)
PATH = [(22, 74), (40, 74), (40, 58), (58, 58), (58, 42), (72, 42)]

def mark(draw, ox, oy, scale, stroke=8, coin=9):
    pts = [(ox + x * scale, oy + y * scale) for x, y in PATH]
    w = stroke * scale
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill=WHITE, width=int(round(w)))
    for x, y in pts:  # round caps and joins
        r = w / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)
    cx, cy, r = ox + 72 * scale, oy + 27 * scale, coin * scale
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD)

def mono(size, name):
    """White-only mark for the Android notification icon (Android tints it; colour is ignored)."""
    ss = 4
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = S * 0.9
    off = (S - box) / 2
    k = box / 100
    pts = [(off + x * k, off + y * k) for x, y in PATH]
    w = 9 * k
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=WHITE, width=int(round(w)))
    for x, y in pts:
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=WHITE)
    cx, cy, r = off + 72 * k, off + 27 * k, 10 * k
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)
    img.resize((size, size), Image.LANCZOS).save(name)
    print("wrote", name)

def render(size, bg, mark_frac, rounded=False, name=""):
    ss = 4  # supersample for smooth edges
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0) if bg is None else bg)
    d = ImageDraw.Draw(img)
    if rounded:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.24), fill=TEAL)
    box = S * mark_frac
    off = (S - box) / 2
    mark(d, off, off, box / 100)
    img = img.resize((size, size), Image.LANCZOS)
    img.save(name)
    print("wrote", name, img.size)

render(1024, TEAL, 0.78, name="assets/brand/icon.png")                 # iOS + legacy Android: full-bleed teal, OS rounds it
render(1024, None, 0.62, name="assets/brand/icon_foreground.png")    # Android adaptive foreground, inside the safe zone
render(768, None, 0.9, name="assets/brand/splash.png")               # native splash image on teal
render(960, None, 0.6, name="assets/brand/splash_android12.png")     # Android 12+ splash: must fit the 640px circle
render(512, None, 0.86, rounded=True, name="assets/brand/logo.png")   # rounded tile, for README and stores
mono(96, "assets/brand/ic_stat_wb.png")                              # Android notification small icon
