"""Placeholder art generator for the Sokoban project.

Everything is drawn procedurally so the project stays self contained.  Swap the
PNGs in assets/art for real art later; the game only relies on the file names.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets" / "art"
ART.mkdir(parents=True, exist_ok=True)

S = 128
SS = 3


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def new(size, ss=SS):
    return Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0)), ss


def finish(img, ss, size=None):
    out = img.resize((size or img.width // ss, size or img.height // ss), Image.LANCZOS)
    return out


def rgba(r, g, b, a=255):
    return (r, g, b, a)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded(d, box, radius, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def noise(img, rng, amount=10, alpha=26, scale=3):
    d = ImageDraw.Draw(img)
    w, h = img.size
    for _ in range(w * h // (scale * 26)):
        x = rng.randrange(w)
        y = rng.randrange(h)
        v = rng.randint(-amount, amount)
        d.point((x, y), fill=(128 + v, 128 + v, 128 + v, alpha))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGBA", (size, size), top)
    d = ImageDraw.Draw(img)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / max(1, size - 1)))
    return img


def shadowed_box(img, ss, box, radius, fill, outline_dark, outline_light):
    """Draw a rounded block with a simple bevel."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = [v * ss for v in box]
    rounded(d, (x0, y0 + 6 * ss, x1, y1 + 6 * ss), radius * ss, fill=(8, 11, 18, 90))
    rounded(d, (x0, y0, x1, y1), radius * ss, fill=fill)
    rounded(d, (x0 + 2 * ss, y0 + 2 * ss, x1 - 2 * ss, y0 + 2 * ss + 5 * ss),
            radius * ss, fill=outline_light)
    rounded(d, (x0 + 2 * ss, y0 + 2 * ss, x1 - 2 * ss, y1 - 2 * ss),
            radius * ss, outline=outline_dark, width=2 * ss)


# --------------------------------------------------------------------------- #
# tiles
# --------------------------------------------------------------------------- #
def make_floor(variant: int):
    size = S * SS
    rng = random.Random(100 + variant)
    img = vertical_gradient(size, (43, 53, 74, 255), (34, 42, 60, 255))
    d = ImageDraw.Draw(img)
    # tile seams
    d.line([(0, 0), (size, 0)], fill=(24, 30, 44, 255), width=2 * SS)
    d.line([(0, 0), (0, size)], fill=(24, 30, 44, 255), width=2 * SS)
    d.line([(1, 1), (size, 1)], fill=(68, 82, 110, 70), width=SS)
    d.line([(1, 1), (1, size)], fill=(68, 82, 110, 70), width=SS)
    # inset plate
    rounded(d, (10 * SS, 10 * SS, size - 10 * SS, size - 10 * SS), 10 * SS,
            outline=(76, 92, 124, 40), width=SS)
    noise(img, rng, amount=9, alpha=22, scale=3)
    if variant == 1:
        # rivets
        for x, y in ((24, 24), (size - 24, 24), (24, size - 24), (size - 24, size - 24)):
            d.ellipse((x - 4 * SS, y - 4 * SS, x + 4 * SS, y + 4 * SS), fill=(95, 112, 145, 120))
            d.ellipse((x - 2 * SS, y - 2 * SS, x + 1 * SS, y + 1 * SS), fill=(140, 160, 194, 90))
    elif variant == 2:
        # hairline crack
        pts = [(28, 96), (46, 78), (40, 58), (62, 38), (58, 20)]
        d.line([(p[0] * SS, p[1] * SS) for p in pts], fill=(20, 25, 37, 120), width=2 * SS,
               joint="curve")
    return finish(img, SS, S)


def make_goal():
    size = S * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((16 * SS, 16 * SS, size - 16 * SS, size - 16 * SS), fill=(70, 214, 196, 55))
    glow = glow.filter(ImageFilter.GaussianBlur(12 * SS))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    # dashed ring
    cx = cy = size / 2
    radius = 34 * SS
    segments = 12
    for i in range(segments):
        if i % 2:
            continue
        a0 = i * 360 / segments + 4
        a1 = a0 + 360 / segments - 8
        d.arc((cx - radius, cy - radius, cx + radius, cy + radius), a0, a1,
              fill=(98, 232, 210, 235), width=5 * SS)
    # diamond
    pts = [(cx, cy - 16 * SS), (cx + 16 * SS, cy), (cx, cy + 16 * SS), (cx - 16 * SS, cy)]
    d.polygon(pts, fill=(88, 224, 204, 235), outline=(196, 255, 244, 255))
    d.line([pts[0], pts[2]], fill=(180, 255, 244, 190), width=2 * SS)
    d.line([pts[1], pts[3]], fill=(180, 255, 244, 190), width=2 * SS)
    return finish(img, SS, S)


def make_wall():
    size = S * SS
    rng = random.Random(5)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # base drop shadow
    rounded(d, (5 * SS, 9 * SS, size - 5 * SS, size - 1 * SS), 12 * SS,
            fill=(6, 9, 15, 120))
    # block face
    rounded(d, (4 * SS, 4 * SS, size - 4 * SS, size - 8 * SS), 12 * SS,
            fill=(60, 74, 100, 255))
    # top light edge
    rounded(d, (8 * SS, 7 * SS, size - 8 * SS, 22 * SS), 7 * SS, fill=(86, 104, 136, 255))
    # brick seams
    for row in range(3):
        y = (34 + row * 27) * SS
        d.line([(12 * SS, y), (size - 12 * SS, y)], fill=(44, 55, 76, 180), width=2 * SS)
        offset = (24 if row % 2 == 0 else 52) * SS
        for bx in range(int(offset), size - 12 * SS, 56 * SS):
            d.line([(bx, y), (bx, y + 27 * SS)], fill=(44, 55, 76, 150), width=2 * SS)
    noise(img, rng, amount=12, alpha=26, scale=4)
    # bevel highlight / shadow
    d.arc((4 * SS, 4 * SS, size - 4 * SS, size - 8 * SS), 200, 340,
          fill=(122, 145, 184, 160), width=3 * SS)
    d.arc((4 * SS, 4 * SS, size - 4 * SS, size - 8 * SS), 20, 160,
          fill=(30, 38, 56, 190), width=3 * SS)
    return finish(img, SS, S)


# --------------------------------------------------------------------------- #
# entities
# --------------------------------------------------------------------------- #
def crate_body(d, ss, box, on_goal=False):
    x0, y0, x1, y1 = [v * ss for v in box]
    r = 8 * ss
    rounded(d, (x0, y0 + 5 * ss, x1, y1 + 5 * ss), r, fill=(7, 10, 17, 110))
    wood_dark = (122, 76, 43, 255)
    wood = (166, 108, 62, 255)
    wood_light = (196, 137, 84, 255)
    rounded(d, (x0, y0, x1, y1), r, fill=wood_dark)
    inset = 5 * ss
    rounded(d, (x0 + inset, y0 + inset, x1 - inset, y1 - inset), r - 3, fill=wood)
    # planks
    for i in range(1, 4):
        x = x0 + inset + (x1 - x0 - 2 * inset) * i / 4
        d.line([(x, y0 + inset), (x, y1 - inset)], fill=(128, 82, 47, 150), width=2 * ss)
    d.line([(x0 + inset, y0 + (y1 - y0) * 0.5), (x1 - inset, y0 + (y1 - y0) * 0.5)],
           fill=(128, 82, 47, 90), width=2 * ss)
    # diagonal braces
    d.line([(x0 + 12 * ss, y0 + 12 * ss), (x1 - 12 * ss, y1 - 12 * ss)],
           fill=(112, 70, 39, 120), width=4 * ss)
    # grain
    rng = random.Random(12)
    for _ in range(18):
        gx = rng.uniform(x0 + 10 * ss, x1 - 10 * ss)
        gy = rng.uniform(y0 + 10 * ss, y1 - 10 * ss)
        d.line([(gx, gy), (gx + rng.uniform(-10, 10) * ss, gy + 2 * ss)],
               fill=(206, 150, 95, 70), width=ss)
    # metal brackets
    metal = (106, 122, 148, 255)
    metal_light = (166, 184, 208, 255)
    arm = 22 * ss
    for cx, cy, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.rectangle((min(cx, cx + sx * arm), min(cy, cy + sy * 10 * ss),
                     max(cx, cx + sx * arm), max(cy, cy + sy * 10 * ss)), fill=metal)
        d.rectangle((min(cx, cx + sx * 10 * ss), min(cy, cy + sy * arm),
                     max(cx, cx + sx * 10 * ss), max(cy, cy + sy * arm)), fill=metal)
        d.rectangle((min(cx, cx + sx * arm), min(cy, cy + sy * 4 * ss),
                     max(cx, cx + sx * arm), max(cy, cy + sy * 4 * ss)), fill=metal_light)
        d.ellipse((min(cx, cx + sx * 7 * ss) - 2 * ss, min(cy, cy + sy * 7 * ss) - 2 * ss,
                   max(cx, cx + sx * 7 * ss) + 2 * ss, max(cy, cy + sy * 7 * ss) + 2 * ss),
                  fill=(214, 222, 236, 230))
    if on_goal:
        # glowing rune
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        for i in range(6):
            a0 = i * 60
            d.arc((cx - 22 * ss, cy - 22 * ss, cx + 22 * ss, cy + 22 * ss), a0, a0 + 34,
                  fill=(176, 255, 240, 210), width=4 * ss)
        d.ellipse((cx - 6 * ss, cy - 6 * ss, cx + 6 * ss, cy + 6 * ss),
                  fill=(220, 255, 248, 235))


def make_box(on_goal=False):
    size = S * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if on_goal:
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.rounded_rectangle((24 * SS, 24 * SS, size - 24 * SS, size - 24 * SS),
                             radius=14 * SS, fill=(64, 226, 202, 150))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(14 * SS)))
    d = ImageDraw.Draw(img)
    crate_body(d, SS, (10, 10, 118, 118), on_goal)
    return finish(img, SS, S)


def make_player(direction: str, frame: int):
    size = S * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = size // 2
    bob = (-2 if frame else 0) * SS
    lean = (1 if frame else -1) * SS

    # shadow
    d.ellipse((cx - 34 * SS, 104 * SS, cx + 34 * SS, 120 * SS), fill=(5, 8, 14, 90))

    body_col = (238, 234, 222, 255)
    body_shade = (198, 194, 182, 255)
    accent = (244, 196, 92, 255)
    visor = (58, 210, 196, 255)
    visor_dark = (30, 140, 134, 255)
    dark = (52, 60, 76, 255)

    feet_y = 104 * SS + bob
    for side in (-1, 1):
        fx = cx + side * 16 * SS + (lean if side < 0 else -lean)
        rounded(d, (fx - 10 * SS, feet_y - 10 * SS, fx + 10 * SS, feet_y + 8 * SS), 6 * SS,
                fill=(70, 82, 104, 255))
        rounded(d, (fx - 8 * SS, feet_y - 8 * SS, fx + 8 * SS, feet_y + 2 * SS), 4 * SS,
                fill=(104, 118, 144, 255))

    # body
    rounded(d, (cx - 30 * SS, 58 * SS + bob, cx + 30 * SS, 104 * SS + bob), 14 * SS,
            fill=body_col)
    rounded(d, (cx - 30 * SS, 88 * SS + bob, cx + 30 * SS, 104 * SS + bob), 10 * SS,
            fill=body_shade)
    rounded(d, (cx - 24 * SS, 66 * SS + bob, cx + 24 * SS, 74 * SS + bob), 4 * SS,
            fill=accent)
    d.ellipse((cx - 8 * SS, 82 * SS + bob, cx + 8 * SS, 94 * SS + bob), fill=(64, 74, 94, 255))
    d.ellipse((cx - 4 * SS, 85 * SS + bob, cx + 4 * SS, 91 * SS + bob), fill=(96, 212, 198, 255))

    # arms
    for side in (-1, 1):
        ax = cx + side * 38 * SS
        ay = 76 * SS + bob + (3 * SS if (frame and side > 0) else 0)
        rounded(d, (ax - 7 * SS, ay - 12 * SS, ax + 7 * SS, ay + 12 * SS), 6 * SS,
                fill=body_shade)
        d.ellipse((ax - 7 * SS, ay + 6 * SS, ax + 7 * SS, ay + 20 * SS), fill=accent)

    # head
    head_top = 18 * SS + bob
    rounded(d, (cx - 30 * SS, head_top, cx + 30 * SS, head_top + 48 * SS), 18 * SS,
            fill=body_col)
    rounded(d, (cx - 30 * SS, head_top + 34 * SS, cx + 30 * SS, head_top + 48 * SS), 14 * SS,
            fill=body_shade)
    # antenna
    d.line([(cx, head_top - 8 * SS), (cx, head_top - 1 * SS)], fill=dark, width=4 * SS)
    d.ellipse((cx - 6 * SS, head_top - 16 * SS, cx + 6 * SS, head_top - 4 * SS), fill=accent)

    if direction == "down":
        rounded(d, (cx - 22 * SS, head_top + 10 * SS, cx + 22 * SS, head_top + 32 * SS),
                9 * SS, fill=(38, 46, 62, 255))
        rounded(d, (cx - 18 * SS, head_top + 13 * SS, cx + 18 * SS, head_top + 29 * SS),
                7 * SS, fill=visor)
        rounded(d, (cx - 14 * SS, head_top + 16 * SS, cx - 2 * SS, head_top + 22 * SS),
                3 * SS, fill=(200, 255, 246, 220))
        d.ellipse((cx - 7 * SS, head_top - 4 * SS, cx - 1 * SS, head_top + 2 * SS),
                  fill=(224, 228, 236, 255))
    elif direction == "up":
        rounded(d, (cx - 22 * SS, head_top + 8 * SS, cx + 22 * SS, head_top + 36 * SS),
                10 * SS, fill=body_shade)
        for sx in (-16, 0, 16):
            d.ellipse((cx + sx * SS - 4 * SS, head_top + 16 * SS,
                       cx + sx * SS + 4 * SS, head_top + 24 * SS), fill=(168, 166, 158, 255))
        d.line([(cx - 20 * SS, head_top + 32 * SS), (cx + 20 * SS, head_top + 32 * SS)],
               fill=(176, 174, 166, 255), width=2 * SS)
        d.ellipse((cx - 3 * SS, head_top - 6 * SS, cx + 3 * SS, head_top), fill=(202, 206, 214, 255))
    else:
        sign = 1 if direction == "right" else -1
        def norm(x0, x1):
            return (min(x0, x1), max(x0, x1))
        a, b = norm(cx + sign * 6 * SS, cx + sign * 30 * SS)
        rounded(d, (a, head_top + 10 * SS, b, head_top + 34 * SS), 10 * SS,
                fill=(38, 46, 62, 255))
        a, b = norm(cx + sign * 9 * SS, cx + sign * 27 * SS)
        rounded(d, (a, head_top + 13 * SS, b, head_top + 31 * SS), 7 * SS, fill=visor)
        e = cx + sign * 28 * SS
        d.ellipse((e - 5 * SS, head_top + 16 * SS, e + 5 * SS, head_top + 26 * SS),
                  fill=(198, 255, 246, 200))
        # side ear
        e = cx - sign * 34 * SS
        d.ellipse((e - 6 * SS, head_top + 18 * SS, e + 6 * SS, head_top + 34 * SS),
                  fill=accent)
        e = cx - sign * 12 * SS
        d.ellipse((e - 2 * SS, head_top - 4 * SS, e + 2 * SS, head_top),
                  fill=(202, 206, 214, 255))
    return finish(img, SS, S)


def make_shadow():
    size = 128 * 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((28, 48, size - 28, size - 30), fill=(0, 0, 0, 110))
    img = img.filter(ImageFilter.GaussianBlur(10))
    return img.resize((128, 128), Image.LANCZOS)


def make_particle(kind="spark"):
    size = 64 * 4
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    if kind == "spark":
        d.ellipse((cx - 9 * 4, cy - 9 * 4, cx + 9 * 4, cy + 9 * 4), fill=(255, 255, 255, 235))
        for i in range(4):
            a = math.radians(i * 90 + 45)
            x = cx + math.cos(a) * 26 * 4
            y = cy + math.sin(a) * 26 * 4
            d.ellipse((x - 4 * 4, y - 4 * 4, x + 4 * 4, y + 4 * 4), fill=(255, 255, 255, 160))
    else:
        d.ellipse((cx - 14 * 4, cy - 14 * 4, cx + 14 * 4, cy + 14 * 4), fill=(255, 255, 255, 80))
    return img.resize((64, 64), Image.LANCZOS)


# --------------------------------------------------------------------------- #
# icons
# --------------------------------------------------------------------------- #
def icon(name: str, size=64, color=(255, 255, 255, 255)):
    ss = 6
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size * ss / 64.0  # scaled unit

    def L(pts, w=5, c=color, closed=False):
        p = [(x * u, y * u) for x, y in pts]
        if closed:
            p = p + [p[0]]
        d.line(p, fill=c, width=int(w * u), joint="curve")
        r = w * u / 2
        for x, y in p:
            d.ellipse((x - r, y - r, x + r, y + r), fill=c)

    def C(cx, cy, r, w=5):
        d.ellipse(((cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u),
                  outline=color, width=int(w * u))

    def F(pts, c=color):
        d.polygon([(x * u, y * u) for x, y in pts], fill=c)

    if name in ("undo", "redo", "restart"):
        if name == "restart":
            d.arc((12 * u, 12 * u, 52 * u, 52 * u), 40, 330, fill=color, width=int(5 * u))
            F([(46, 8), (56, 20), (42, 22)])
        else:
            flip = name == "undo"
            box = (14 * u, 18 * u, 50 * u, 50 * u)
            if flip:
                d.arc(box, 150, 380, fill=color, width=int(5 * u))
                F([(12, 28), (28, 18), (28, 36)])
            else:
                d.arc(box, 160, 390, fill=color, width=int(5 * u))
                F([(52, 28), (36, 18), (36, 36)])
    elif name == "home":
        L([(12, 30), (32, 12), (52, 30)], 5)
        L([(18, 29), (18, 50), (46, 50), (46, 29)], 5)
        L([(27, 50), (27, 38), (37, 38), (37, 50)], 4)
    elif name == "pause":
        d.rounded_rectangle((16 * u, 12 * u, 27 * u, 52 * u), radius=3 * u, fill=color)
        d.rounded_rectangle((37 * u, 12 * u, 48 * u, 52 * u), radius=3 * u, fill=color)
    elif name == "play":
        F([(20, 12), (52, 32), (20, 52)])
    elif name == "star":
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            r = 26 if i % 2 == 0 else 11
            pts.append((32 + math.cos(a) * r, 33 + math.sin(a) * r))
        F(pts)
    elif name == "lock":
        d.rounded_rectangle((16 * u, 28 * u, 48 * u, 54 * u), radius=6 * u, fill=color)
        d.arc((21 * u, 10 * u, 43 * u, 38 * u), 180, 360, fill=color, width=int(5 * u))
        d.ellipse((29 * u, 36 * u, 35 * u, 42 * u), fill=(30, 38, 54, 255))
    elif name == "pencil":
        L([(44, 10), (54, 20), (26, 48), (12, 52), (16, 38)], 5)
        L([(38, 16), (48, 26)], 4)
    elif name == "grid":
        for i in (24, 40):
            L([(i, 12), (i, 52)], 3)
            L([(12, i), (52, i)], 3)
        L([(12, 12), (12, 52), (52, 52), (52, 12), (12, 12)], 4)
    elif name == "brush":
        L([(20, 44), (42, 20)], 7)
        F([(14, 38), (26, 50), (18, 54), (10, 46)])
        d.rounded_rectangle((38 * u, 8 * u, 56 * u, 22 * u), radius=5 * u, fill=color)
    elif name == "eraser":
        d.rounded_rectangle((16 * u, 24 * u, 46 * u, 44 * u), radius=5 * u, fill=color)
        L([(24, 52), (50, 52)], 5)
        L([(28, 30), (38, 38)], 3, (30, 38, 54, 255))
    elif name == "bulb":
        C(32, 27, 14, 5)
        L([(27, 41), (37, 41)], 4)
        L([(28, 47), (36, 47)], 4)
        L([(32, 50), (32, 55)], 4)
        for a in range(0, 360, 60):
            rad = math.radians(a)
            L([(32 + math.cos(rad) * 20, 27 + math.sin(rad) * 20)],
              4) if False else None
        for a in (-140, -100, -60, -20, 20):
            rad = math.radians(a)
            x0 = 32 + math.cos(rad) * 20
            y0 = 27 + math.sin(rad) * 20
            x1 = 32 + math.cos(rad) * 25
            y1 = 27 + math.sin(rad) * 25
            L([(x0, y0), (x1, y1)], 3)
    elif name == "settings":
        for i in range(8):
            a = i * math.pi / 4
            x = 32 + math.cos(a) * 20
            y = 32 + math.sin(a) * 20
            d.ellipse(((x - 6) * u, (y - 6) * u, (x + 6) * u, (y + 6) * u), fill=color)
        d.ellipse((14 * u, 14 * u, 50 * u, 50 * u), outline=color, width=int(7 * u))
        d.ellipse((25 * u, 25 * u, 39 * u, 39 * u), fill=(0, 0, 0, 0))
        d.ellipse((25 * u, 25 * u, 39 * u, 39 * u), outline=color, width=int(4 * u))
    elif name == "sound":
        F([(12, 25), (22, 25), (34, 14), (34, 50), (22, 39), (12, 39)])
        d.arc((30 * u, 20 * u, 48 * u, 44 * u), -60, 60, fill=color, width=int(4 * u))
        d.arc((34 * u, 14 * u, 56 * u, 50 * u), -55, 55, fill=color, width=int(3 * u))
    elif name == "close":
        L([(17, 17), (47, 47)], 6)
        L([(47, 17), (17, 47)], 6)
    elif name == "check":
        L([(14, 34), (27, 47), (50, 18)], 6)
    elif name in ("arrow_left", "arrow_right"):
        s = -1 if name == "arrow_left" else 1
        L([(32 - 10 * s, 14), (32 + 12 * s, 32), (32 - 10 * s, 50)], 6)
    elif name in ("plus", "minus"):
        L([(14, 32), (50, 32)], 6)
        if name == "plus":
            L([(32, 14), (32, 50)], 6)
    elif name == "save":
        d.rounded_rectangle((12 * u, 12 * u, 52 * u, 52 * u), radius=5 * u, fill=color)
        d.rectangle((22 * u, 12 * u, 42 * u, 28 * u), fill=(30, 38, 54, 255))
        d.rectangle((19 * u, 36 * u, 45 * u, 52 * u), fill=(30, 38, 54, 255))
        d.rectangle((24 * u, 17 * u, 34 * u, 25 * u), fill=(230, 234, 242, 255))
    elif name == "folder":
        F([(10, 18), (26, 18), (31, 25), (54, 25), (54, 50), (10, 50)])
        L([(10, 30), (54, 30)], 3, (30, 38, 54, 255))
    elif name == "trash":
        L([(14, 20), (50, 20)], 5)
        L([(24, 20), (24, 13), (40, 13), (40, 20)], 4)
        L([(18, 20), (21, 53), (43, 53), (46, 20)], 5)
        L([(28, 27), (29, 46)], 3)
        L([(36, 27), (35, 46)], 3)
    elif name == "test":
        d.ellipse((8 * u, 8 * u, 56 * u, 56 * u), outline=color, width=int(4 * u))
        F([(27, 21), (46, 32), (27, 43)])
    elif name == "resize":
        L([(14, 50), (50, 14)], 5)
        L([(36, 14), (50, 14), (50, 28)], 5)
        L([(28, 50), (14, 50), (14, 36)], 5)
    elif name == "fill":
        L([(18, 34), (32, 12), (48, 30), (34, 50), (18, 34)], 4)
        L([(24, 24), (40, 42)], 3)
        d.ellipse((46 * u, 38 * u, 54 * u, 46 * u), fill=color)
        F([(50, 46), (47, 53), (53, 53)])
    elif name == "rect":
        d.rectangle((14 * u, 18 * u, 50 * u, 46 * u), outline=color, width=int(5 * u))
    elif name == "select":
        F([(18, 12), (50, 32), (34, 35), (42, 50), (34, 54), (27, 39), (18, 48)])
    elif name == "move":
        L([(32, 12), (32, 52)], 4)
        L([(12, 32), (52, 32)], 4)
        F([(32, 8), (27, 17), (37, 17)])
        F([(32, 56), (27, 47), (37, 47)])
        F([(8, 32), (17, 27), (17, 37)])
        F([(56, 32), (47, 27), (47, 37)])
    elif name == "music":
        L([(40, 14), (40, 44)], 5)
        L([(40, 14), (52, 18)], 4)
        d.ellipse((29 * u, 42 * u, 42 * u, 52 * u), fill=color)
    elif name == "fullscreen":
        L([(12, 26), (12, 12), (26, 12)], 5)
        L([(38, 12), (52, 12), (52, 26)], 5)
        L([(52, 38), (52, 52), (38, 52)], 5)
        L([(26, 52), (12, 52), (12, 38)], 5)
    elif name == "info":
        d.ellipse((10 * u, 10 * u, 54 * u, 54 * u), outline=color, width=int(4 * u))
        d.ellipse((29 * u, 17 * u, 35 * u, 23 * u), fill=color)
        d.rounded_rectangle((29 * u, 28 * u, 35 * u, 47 * u), radius=3 * u, fill=color)
    elif name == "import":
        L([(32, 10), (32, 36)], 5)
        F([(32, 44), (21, 31), (43, 31)])
        L([(14, 40), (14, 52), (50, 52), (50, 40)], 4)
    elif name == "export":
        L([(32, 40), (32, 14)], 5)
        F([(32, 6), (21, 19), (43, 19)])
        L([(14, 40), (14, 52), (50, 52), (50, 40)], 4)
    elif name == "push":
        d.rounded_rectangle((8 * u, 24 * u, 24 * u, 36 * u), radius=3 * u, fill=color)
        d.rounded_rectangle((26 * u, 24 * u, 42 * u, 36 * u), radius=3 * u, fill=color)
        F([(56, 30), (44, 22), (44, 38)])
        L([(8, 48), (46, 48)], 4)
        L([(46, 48), (40, 42)], 3)
    elif name == "pass":
        d.rounded_rectangle((16 * u, 18 * u, 48 * u, 46 * u), radius=4 * u,
                            outline=color, width=int(4 * u))
        L([(6, 32), (58, 32)], 4)
        F([(58, 26), (48, 22), (48, 42)])
        L([(24, 26), (24, 38)], 3)
        L([(32, 26), (32, 38)], 3)
        L([(40, 26), (40, 38)], 3)
    elif name == "hook":
        L([(32, 8), (32, 28)], 5)
        d.arc((14 * u, 24 * u, 50 * u, 52 * u), 200, 340, fill=color, width=int(5 * u))
        L([(20, 38), (15, 52)], 4)
        L([(44, 38), (49, 52)], 4)
    elif name == "jump":
        d.arc((8 * u, 14 * u, 56 * u, 60 * u), 200, 340, fill=color, width=int(4 * u))
        F([(54, 30), (44, 22), (44, 38)])
        d.rounded_rectangle((22 * u, 36 * u, 42 * u, 54 * u), radius=3 * u, fill=color)
    elif name == "phase":
        for i in range(3):
            yy = 12 + i * 18
            L([(20, yy), (20, yy + 10)], 4)
            L([(34, yy), (34, yy + 10)], 4)
        L([(8, 32), (48, 32)], 4)
        F([(58, 32), (48, 26), (48, 38)])
    elif name == "warp":
        C(32, 32, 20, 4)
        C(32, 32, 8, 3)
        L([(32, 6), (32, 16)], 4)
        L([(32, 48), (32, 58)], 4)
        L([(6, 32), (16, 32)], 4)
        L([(48, 32), (58, 32)], 4)
    elif name == "core":
        pts = []
        for i in range(6):
            a = math.pi / 6 + i * math.pi / 3
            pts.append((32 + math.cos(a) * 24, 32 + math.sin(a) * 24))
        F(pts)
        d.ellipse((24 * u, 24 * u, 40 * u, 40 * u), fill=(22, 30, 44, 255))
        d.ellipse((28 * u, 28 * u, 36 * u, 36 * u), fill=color)
    elif name == "coin":
        C(32, 32, 21, 5)
        C(32, 32, 15, 3)
        L([(32, 22), (32, 42)], 4)
        L([(25, 28), (39, 28)], 3)
        L([(25, 34), (39, 34)], 3)
    elif name == "c4":
        d.rounded_rectangle((22 * u, 24 * u, 42 * u, 56 * u), radius=5 * u, fill=color)
        L([(32, 24), (38, 14), (46, 12)], 3)
        F([(44, 6), (52, 10), (46, 16), (40, 12)])
        L([(26, 32), (26, 48)], 3, (22, 30, 44, 255))
        L([(38, 32), (38, 48)], 3, (22, 30, 44, 255))
    elif name == "crane":
        L([(14, 14), (48, 14), (48, 34)], 5)
        L([(14, 14), (14, 44)], 5)
        d.arc((38 * u, 34 * u, 58 * u, 54 * u), 200, 20, fill=color, width=int(5 * u))
        L([(14, 44), (8, 52)], 4)
    elif name == "contract":
        L([(16, 12), (40, 12), (48, 20), (48, 52), (16, 52), (16, 12)], 4)
        L([(40, 12), (40, 20), (48, 20)], 3)
        L([(22, 28), (42, 28)], 3)
        L([(22, 35), (42, 35)], 3)
        C(38, 45, 7, 3)
        F([(34, 45), (42, 45), (38, 52)])
    elif name == "rope":
        d.arc((14 * u, 12 * u, 50 * u, 44 * u), 200, 340, fill=color, width=int(5 * u))
        d.arc((22 * u, 24 * u, 46 * u, 48 * u), 20, 160, fill=color, width=int(5 * u))
        L([(46, 42), (52, 50)], 4)
        L([(18, 30), (12, 22)], 4)
    elif name == "rewind":
        d.arc((12 * u, 12 * u, 52 * u, 52 * u), 120, 420, fill=color, width=int(4 * u))
        F([(12, 16), (26, 20), (14, 30)])
        L([(32, 22), (32, 34), (42, 38)], 4)
    elif name == "guide":
        L([(10, 20), (26, 16), (32, 20), (38, 16), (54, 20), (54, 48), (38, 44),
           (32, 48), (26, 44), (10, 48), (10, 20)], 4)
        L([(32, 20), (32, 48)], 3)
        L([(17, 28), (26, 26)], 3)
        L([(38, 26), (47, 28)], 3)
    elif name == "shop":
        for i in range(4):
            x = 12 + i * 10
            F([(x, 14), (x + 10, 14), (x + 8, 22), (x + 2, 22)])
        L([(12, 22), (12, 52), (52, 52), (52, 22)], 4)
        L([(26, 52), (26, 34), (38, 34), (38, 52)], 4)
    elif name == "ad":
        F([(10, 26), (26, 22), (44, 10), (44, 54), (26, 42), (10, 38)])
        L([(14, 38), (14, 52)], 4)
        d.arc((46 * u, 18 * u, 60 * u, 46 * u), -60, 60, fill=color, width=int(3 * u))
    elif name == "trophy":
        d.rounded_rectangle((20 * u, 10 * u, 44 * u, 34 * u), radius=6 * u, fill=color)
        d.arc((8 * u, 12 * u, 26 * u, 32 * u), 90, 270, fill=color, width=int(4 * u))
        d.arc((38 * u, 12 * u, 56 * u, 32 * u), -90, 90, fill=color, width=int(4 * u))
        d.rectangle((29 * u, 34 * u, 35 * u, 44 * u), fill=color)
        d.rounded_rectangle((21 * u, 44 * u, 43 * u, 52 * u), radius=3 * u, fill=color)
    else:
        C(32, 32, 18, 4)
    return img.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------- #
# hazards: rubble, thug, thief
# --------------------------------------------------------------------------- #
def make_rubble():
    size = 128
    ss = 4
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = ss

    def rock(box, top, side, dark):
        d.polygon([(box[0] * u, box[3] * u), (box[1] * u, box[3] * u),
                   ((box[0] + 8) * u, box[1] * u), ((box[2] - 6) * u, box[0] * u),
                   (box[2] * u, box[3] * u)], fill=side)
        d.polygon([(box[0] * u, box[3] * u), ((box[0] + 8) * u, box[1] * u),
                   ((box[2] - 6) * u, box[0] * u), ((box[2] - 10) * u, box[3] * u)],
                  fill=top)
        d.line([(box[0] * u, box[3] * u), (box[1] * u, box[3] * u)], fill=dark,
               width=int(3 * u))

    d.ellipse((12 * u, 96 * u, 116 * u, 120 * u), fill=(0, 0, 0, 80))
    rock((10, 78, 56, 118), (120, 124, 132, 255), (86, 92, 104, 255), (58, 64, 76, 255))
    rock((48, 62, 96, 116), (134, 138, 146, 255), (96, 102, 114, 255), (64, 70, 84, 255))
    rock((78, 82, 122, 118), (110, 114, 126, 255), (78, 84, 96, 255), (52, 58, 70, 255))
    for cx, cy in ((36, 88), (70, 74), (104, 92)):
        d.ellipse(((cx - 4) * u, (cy - 4) * u, (cx + 4) * u, (cy + 4) * u),
                  fill=(70, 76, 90, 255))
    return img.resize((size, size), Image.LANCZOS)


def _humanoid(body, trim, eye, hood=False, sack=False, spikes=False):
    size = 128
    ss = 4
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = ss
    d.ellipse((22 * u, 104 * u, 106 * u, 122 * u), fill=(0, 0, 0, 90))
    # legs
    d.rounded_rectangle((44 * u, 84 * u, 60 * u, 110 * u), radius=6 * u, fill=body)
    d.rounded_rectangle((68 * u, 84 * u, 84 * u, 110 * u), radius=6 * u, fill=body)
    # torso
    d.rounded_rectangle((38 * u, 46 * u, 90 * u, 90 * u), radius=12 * u, fill=body)
    d.rounded_rectangle((46 * u, 56 * u, 82 * u, 84 * u), radius=9 * u, fill=trim)
    # arms
    d.rounded_rectangle((26 * u, 48 * u, 42 * u, 86 * u), radius=8 * u, fill=body)
    d.rounded_rectangle((86 * u, 48 * u, 102 * u, 86 * u), radius=8 * u, fill=body)
    # head
    d.rounded_rectangle((44 * u, 16 * u, 84 * u, 50 * u), radius=12 * u, fill=body)
    if hood:
        d.polygon([(38 * u, 52 * u), (90 * u, 52 * u), (78 * u, 12 * u), (50 * u, 12 * u)],
                  fill=trim)
        d.rounded_rectangle((50 * u, 26 * u, 78 * u, 42 * u), radius=7 * u,
                            fill=(12, 14, 22, 255))
    else:
        d.rounded_rectangle((50 * u, 28 * u, 78 * u, 42 * u), radius=7 * u,
                            fill=(12, 14, 22, 255))
    d.ellipse((54 * u, 31 * u, 62 * u, 39 * u), fill=eye)
    d.ellipse((68 * u, 31 * u, 76 * u, 39 * u), fill=eye)
    if spikes:
        for x in (30, 94):
            d.polygon([(x * u, 48 * u), ((x + 8) * u, 34 * u), ((x + 16) * u, 48 * u)],
                      fill=trim)
        d.rounded_rectangle((94 * u, 60 * u, 118 * u, 72 * u), radius=4 * u, fill=trim)
    if sack:
        d.ellipse((16 * u, 70 * u, 44 * u, 100 * u), fill=trim)
        d.ellipse((24 * u, 74 * u, 36 * u, 86 * u), fill=(0, 0, 0, 60))
    return img.resize((size, size), Image.LANCZOS)


def make_thug():
    return _humanoid((122, 66, 60, 255), (168, 96, 72, 255), (255, 214, 120, 255),
                     spikes=True)


def make_thief():
    return _humanoid((58, 52, 96, 255), (40, 36, 70, 255), (140, 220, 255, 255),
                     hood=True, sack=True)


# --------------------------------------------------------------------------- #
# shop robot: full body sheet used by the upgrade screen
# --------------------------------------------------------------------------- #
ROBOT_W, ROBOT_H = 440, 860


def make_robot():
    """Front facing worker-bot. Part centres match RobotUpgrades.HOTSPOTS."""
    ss = 3
    W, H = ROBOT_W * 1, ROBOT_H
    img = Image.new("RGBA", (W * 1, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    metal = (58, 72, 96, 255)
    metal_dark = (34, 44, 62, 255)
    metal_light = (86, 104, 134, 255)
    trim = (242, 193, 78, 255)
    energy = (79, 209, 197, 255)

    def plate(box, radius=10, fill=metal, outline=metal_dark, width=3):
        rounded(d, box, radius, fill=fill, outline=outline, width=width)

    def shading(box, radius=10):
        x0, y0, x1, y1 = box
        rounded(d, (x0 + 4, y0 + 4, x1 - 4, y0 + (y1 - y0) * 0.35), radius,
                fill=metal_light)

    # backpack (mounted high behind the left shoulder)
    plate((38, 104, 128, 268), 16)
    d.rounded_rectangle((58, 124, 110, 176), radius=8, fill=metal_dark)
    d.rounded_rectangle((58, 186, 110, 238), radius=8, fill=(30, 40, 56, 255))
    d.line([(128, 200), (152, 216)], fill=metal_light, width=6)
    d.ellipse((142, 208, 162, 228), fill=energy)

    # legs
    for lx in (150, 236):
        plate((lx, 470, lx + 56, 610), 14)
        d.rounded_rectangle((lx + 10, 520, lx + 46, 596), radius=6, fill=metal_dark)
        plate((lx + 4, 604, lx + 52, 726), 10, (46, 58, 80, 255))
        d.line([(lx + 28, 620), (lx + 28, 706)], fill=trim, width=5)
        plate((lx - 10, 724, lx + 66, 774), 12, metal_dark, (24, 32, 46, 255), 3)
        d.rounded_rectangle((lx - 2, 736, lx + 58, 762), radius=6, fill=metal)

    # pelvis
    plate((146, 424, 294, 486), 14)
    d.rectangle((150, 452, 290, 466), fill=metal_dark)

    # torso
    plate((126, 158, 314, 432), 22)
    shading((126, 158, 314, 432), 22)
    # chest core
    d.ellipse((172, 214, 268, 310), fill=(22, 30, 44, 255), outline=metal_dark, width=4)
    d.ellipse((184, 226, 256, 298), fill=(18, 60, 62, 255), outline=energy, width=4)
    d.ellipse((202, 244, 238, 280), fill=energy)
    d.ellipse((208, 250, 226, 266), fill=(235, 255, 252, 255))
    # torso vents
    for i in range(3):
        y = 332 + i * 24
        d.rounded_rectangle((166, y, 274, y + 10), radius=5, fill=metal_dark)
    # shoulder pads
    for sx in (96, 300):
        plate((sx, 150, sx + 44, 210), 14, metal_light, metal_dark, 3)

    # arms
    # left arm: magnetic hook claw
    plate((78, 196, 132, 302), 12)
    d.line([(105, 214), (105, 288)], fill=metal_dark, width=5)
    plate((70, 298, 128, 392), 10, (46, 58, 80, 255))
    d.rounded_rectangle((78, 320, 120, 344), radius=6, fill=trim)
    d.line([(100, 392), (100, 424)], fill=metal_light, width=9)
    d.arc((72, 410, 128, 460), 200, 340, fill=energy, width=9)
    d.line([(80, 420), (68, 434)], fill=energy, width=7)
    d.line([(120, 420), (132, 434)], fill=energy, width=7)
    # right arm: hydraulic piston pusher
    plate((308, 196, 362, 302), 12)
    d.line([(335, 214), (335, 288)], fill=metal_dark, width=5)
    plate((312, 298, 370, 396), 10, (46, 58, 80, 255))
    for i in range(2):
        x = 324 + i * 22
        d.rounded_rectangle((x, 316, x + 16, 378), radius=6, fill=trim)
    plate((300, 400, 382, 446), 8, metal_dark, (24, 32, 46, 255), 3)
    d.rounded_rectangle((308, 410, 374, 436), radius=5, fill=metal_light)

    # head
    plate((156, 44, 284, 142), 20)
    shading((156, 44, 284, 142), 20)
    d.rounded_rectangle((170, 62, 270, 118), radius=12, fill=(16, 22, 34, 255))
    d.rounded_rectangle((178, 74, 262, 100), radius=10, fill=(22, 84, 88, 255))
    d.rounded_rectangle((186, 80, 254, 94), radius=7, fill=energy)
    d.rounded_rectangle((196, 84, 244, 90), radius=3, fill=(235, 255, 252, 255))
    d.rounded_rectangle((192, 124, 248, 136), radius=5, fill=metal_dark)
    # antenna
    d.line([(220, 44), (220, 22)], fill=metal_light, width=5)
    d.ellipse((213, 12, 227, 26), fill=trim)
    # neck
    d.rounded_rectangle((196, 140, 244, 164), radius=8, fill=metal_dark)

    return img.resize((ROBOT_W, ROBOT_H), Image.LANCZOS)


# --------------------------------------------------------------------------- #
# ad banner (placeholder creative for the rewarded-ad modal)
# --------------------------------------------------------------------------- #
def make_ad_banner():
    W, H = 640, 300
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        shade = rgba(int(28 + (16 - 28) * t), int(40 + (24 - 40) * t),
                     int(62 + (36 - 62) * t))
        d.line([(0, y), (W, y)], fill=shade)
    for x in range(-H, W, 46):
        d.polygon([(x, H), (x + 18, H), (x + 18 + H, 0), (x + H, 0)],
                  fill=(255, 255, 255, 8))
    d.rectangle((0, 0, W - 1, H - 1), outline=(77, 96, 130, 255), width=3)
    for i in range(3):
        cx, cy = W - 120, 96 + i * 62
        d.rounded_rectangle((cx - 96, cy - 22, cx + 96, cy + 22), radius=10,
                            fill=(242, 193, 78, 26 + i * 8),
                            outline=(242, 193, 78, 90 + i * 30), width=2)
    icon_img = icon("ad", 128, (242, 193, 78, 255))
    img.alpha_composite(icon_img, (48, 86))
    return img


# --------------------------------------------------------------------------- #
# logo
# --------------------------------------------------------------------------- #
def make_logo():
    W, H = 1200, 460
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font_cn = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 190, index=0)
    font_en = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 62)
    # crate emblem
    crate = make_box(False).resize((190, 190), Image.LANCZOS)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((70, 90, 330, 350), fill=(64, 214, 196, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(30)))
    img.alpha_composite(crate, (110, 120))
    # chinese title with warm gradient
    text = "推箱子"
    bbox = d.textbbox((0, 0), text, font=font_cn)
    tw = bbox[2] - bbox[0]
    x = 380
    y = 110
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.text((x, y), text, font=font_cn, fill=255)
    grad = vertical_gradient(H, (255, 236, 196, 255), (244, 183, 76, 255)).resize((W, H))
    img.paste(grad, (0, 0), mask)
    d.text((x + 4, y + 6), text, font=font_cn, fill=(10, 14, 22, 90))
    # english subtitle
    sub = "S O K O B A N   ·   W A R E H O U S E"
    d.text((390, 330), sub, font=font_en, fill=(150, 171, 204, 255))
    d.line([(392, 400), (1050, 400)], fill=(240, 190, 92, 190), width=3)
    d.text((392, 410), "PUSH · PLAN · PREVAIL", font=ImageFont.truetype(
        "C:/Windows/Fonts/segoeuib.ttf", 26), fill=(110, 133, 168, 255))
    return img


# --------------------------------------------------------------------------- #
def main():
    for i in range(3):
        make_floor(i).save(ART / f"floor_{i}.png")
    make_goal().save(ART / "goal.png")
    make_wall().save(ART / "wall.png")
    make_box(False).save(ART / "box.png")
    make_box(True).save(ART / "box_goal.png")
    for direction in ("down", "up", "left", "right"):
        for frame in (0, 1):
            make_player(direction, frame).save(ART / f"player_{direction}_{frame}.png")
    make_shadow().save(ART / "shadow.png")
    make_particle("spark").save(ART / "spark.png")
    make_particle("dust").save(ART / "dust.png")
    make_rubble().save(ART / "rubble.png")
    make_thug().save(ART / "thug.png")
    make_thief().save(ART / "thief.png")
    make_logo().save(ART / "logo.png")
    make_robot().save(ART / "robot_body.png")
    make_ad_banner().save(ART / "ad_banner.png")
    for name in ("undo", "redo", "restart", "home", "pause", "play", "star", "lock", "pencil",
                 "grid", "brush", "eraser", "bulb", "settings", "sound", "close", "check",
                 "arrow_left", "arrow_right", "plus", "minus", "save", "folder", "trash",
                 "test", "resize", "fill", "rect", "select", "move", "music", "fullscreen",
                 "info", "import", "export", "trophy", "coin", "c4", "crane", "contract",
                 "rope", "rewind", "guide", "shop", "ad", "push", "hook", "jump", "phase",
                 "warp", "core", "pass"):
        icon(name).save(ART / f"icon_{name}.png")
    print("art written to", ART)


if __name__ == "__main__":
    main()
