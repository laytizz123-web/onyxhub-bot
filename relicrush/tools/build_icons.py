#!/usr/bin/env python3
"""Icones de RELIC RUSH.
1. Decoupe assets/icon-sheet.webp (grille 4 x 3, fond blanc) en 12 icones avec leur titre.
2. Dessine les petites icones du HUD (piece, puissance, relique, cadenas, fermer, valider...) dans le meme style.
3. Encode tout dans src/ReplicatedStorage/Shared/IconData.lua (palette + RLE + base64), affiche en jeu via EditableImage.
Usage : python3 tools/build_icons.py
"""
import base64, math, os
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "icons")
SHEET = os.path.join(ROOT, "assets", "icon-sheet.webp")
OUT_LUA = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "IconData.lua")
os.makedirs(ICONS, exist_ok=True)
NAMES = [["index", "inventory", "shop", "worlds"], ["upgrades", "rebirth", "quests", "trading"], ["boss", "daily", "leaderboard", "settings"]]


def background_mask(A, tol=28):
    """Fond blanc connecte aux bords (flood fill)."""
    rgb = A[..., :3].astype(int)
    white = (np.abs(rgb - 255).max(axis=2) <= tol) | (A[..., 3] < 20)
    h, w = white.shape
    bg = np.zeros_like(white)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if white[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if white[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and white[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True; q.append((ny, nx))
    return bg


def square(img, size=256, pad=6):
    w, h = img.size
    s = max(w, h) + pad
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(img, ((s - w) // 2, (s - h) // 2))
    return sq.resize((size, size), Image.LANCZOS)


def cut_sheet():
    A = np.array(Image.open(SHEET).convert("RGBA"))
    H, W = A.shape[:2]
    bg = background_mask(A)
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    # adoucit le bord (anti-crenelage) : alpha partiel pour les pixels presque blancs du contour
    edge = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.8))
    A[..., 3] = np.minimum(np.array(edge), A[..., 3])
    rows, cols = len(NAMES), len(NAMES[0])
    for r in range(rows):
        for c in range(cols):
            y0, y1 = int(H * r / rows), int(H * (r + 1) / rows)
            x0, x1 = int(W * c / cols), int(W * (c + 1) / cols)
            cell = A[y0:y1, x0:x1].copy()
            ys, xs = np.where(cell[..., 3] > 30)
            cell = cell[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
            square(Image.fromarray(cell)).save(os.path.join(ICONS, NAMES[r][c] + ".png"))


# --------------------------------------------------------------- icones dessinees
S = 4
B = 128
OUT = (30, 18, 45, 255)


def P(v):
    return int(v * S)


def grad(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    arr = (np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t)
    arr = np.repeat(arr, w, axis=1)
    return Image.fromarray(np.concatenate([arr, np.full((h, w, 1), 255)], 2).astype(np.uint8))


def shape(img, draw_fn, top, bottom, ow=6):
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    draw_fn(ImageDraw.Draw(m), 255)
    if ow:
        img.paste(Image.new("RGBA", (w, h), OUT), (0, 0), m.filter(ImageFilter.MaxFilter(ow * 2 + 1)))
    img.paste(grad((w, h), top, bottom), (0, 0), m)
    return m


def gloss(img, box, a=140):
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([P(v) for v in box], fill=a)
    img.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), m.filter(ImageFilter.GaussianBlur(P(1.6))))


def new():
    return Image.new("RGBA", (B * S, B * S), (0, 0, 0, 0))


def done(img, name):
    img.resize((B, B), Image.LANCZOS).save(os.path.join(ICONS, name + ".png"))


def spiral(d, cx, cy, r, fill, width):
    pts = []
    for i in range(60):
        t = i / 59 * 2.6 * math.pi
        rr = r * (0.15 + 0.85 * i / 59)
        pts.append((cx + math.cos(t) * rr, cy + math.sin(t) * rr))
    d.line(pts, fill=fill, width=width, joint="curve")


def draw_coin():
    img = new()
    shape(img, lambda d, f: d.ellipse([P(10), P(10), P(118), P(118)], fill=f), (255, 225, 90), (225, 140, 20))
    shape(img, lambda d, f: d.ellipse([P(26), P(26), P(102), P(102)], fill=f), (255, 205, 60), (240, 170, 30), ow=0)
    d = ImageDraw.Draw(img)
    spiral(d, P(64), P(64), P(26), (170, 95, 15, 255), P(7))
    gloss(img, (24, 16, 70, 46))
    done(img, "coin")


def draw_power():
    img = new()
    pts = [(70, 6), (26, 72), (58, 72), (48, 122), (102, 50), (68, 50), (84, 6)]
    shape(img, lambda d, f: d.polygon([(P(x), P(y)) for x, y in pts], fill=f), (215, 140, 255), (120, 40, 200))
    gloss(img, (52, 12, 76, 40))
    done(img, "power")


def draw_relic():
    img = new()
    pts = [(64, 6), (110, 46), (64, 122), (18, 46)]
    shape(img, lambda d, f: d.polygon([(P(x), P(y)) for x, y in pts], fill=f), (140, 230, 255), (40, 110, 220))
    d = ImageDraw.Draw(img)
    d.line([(P(18), P(46)), (P(110), P(46))], fill=(255, 255, 255, 160), width=P(3))
    d.line([(P(64), P(6)), (P(44), P(46)), (P(64), P(122)), (P(84), P(46)), (P(64), P(6))], fill=(255, 255, 255, 110), width=P(2))
    gloss(img, (34, 18, 62, 40))
    done(img, "relic")


def draw_lock():
    img = new()
    shape(img, lambda d, f: d.arc([P(34), P(10), P(94), P(76)], 180, 360, fill=f, width=P(14)), (200, 205, 215), (130, 135, 150))
    shape(img, lambda d, f: d.rounded_rectangle([P(20), P(52), P(108), P(120)], radius=P(14), fill=f), (255, 215, 80), (220, 140, 20))
    shape(img, lambda d, f: d.ellipse([P(55), P(72), P(73), P(90)], fill=f), (60, 40, 30), (40, 25, 20), ow=0)
    done(img, "lock")


def draw_close():
    img = new()
    shape(img, lambda d, f: d.ellipse([P(8), P(8), P(120), P(120)], fill=f), (255, 110, 110), (200, 40, 50))
    d = ImageDraw.Draw(img)
    for a, b in (((40, 40), (88, 88)), ((88, 40), (40, 88))):
        d.line([(P(a[0]), P(a[1])), (P(b[0]), P(b[1]))], fill=(255, 255, 255, 255), width=P(14))
    gloss(img, (28, 16, 70, 40))
    done(img, "close")


def draw_check():
    img = new()
    shape(img, lambda d, f: d.ellipse([P(8), P(8), P(120), P(120)], fill=f), (130, 235, 110), (40, 160, 60))
    d = ImageDraw.Draw(img)
    d.line([(P(34), P(66)), (P(56), P(88)), (P(96), P(42))], fill=(255, 255, 255, 255), width=P(15), joint="curve")
    gloss(img, (28, 16, 70, 40))
    done(img, "check")


def draw_slot():
    img = new()
    shape(img, lambda d, f: d.ellipse([P(10), P(10), P(118), P(118)], fill=f), (110, 80, 200), (50, 30, 110))
    shape(img, lambda d, f: d.ellipse([P(36), P(36), P(92), P(92)], fill=f), (160, 230, 255), (60, 140, 230), ow=4)
    gloss(img, (40, 38, 66, 54))
    done(img, "slot")


def draw_crate():
    img = new()
    shape(img, lambda d, f: d.rounded_rectangle([P(12), P(40), P(116), P(118)], radius=P(10), fill=f), (190, 120, 60), (120, 70, 35))
    shape(img, lambda d, f: d.rounded_rectangle([P(8), P(24), P(120), P(52)], radius=P(10), fill=f), (220, 150, 75), (150, 90, 45))
    shape(img, lambda d, f: d.rectangle([P(54), P(24), P(74), P(118)], fill=f), (255, 220, 90), (220, 150, 30), ow=3)
    shape(img, lambda d, f: d.polygon([(P(64), P(42)), (P(76), P(56)), (P(64), P(70)), (P(52), P(56))], fill=f), (150, 230, 255), (50, 130, 230), ow=3)
    done(img, "crate")


def draw_rebirthToken():
    img = new()
    shape(img, lambda d, f: d.regular_polygon((P(64), P(64), P(56)), 6, rotation=30, fill=f), (220, 150, 255), (110, 40, 190))
    d = ImageDraw.Draw(img)
    d.arc([P(36), P(36), P(92), P(92)], 200, 500, fill=(255, 255, 255, 255), width=P(9))
    d.polygon([(P(92), P(50)), (P(100), P(70)), (P(80), P(64))], fill=(255, 255, 255, 255))
    gloss(img, (34, 16, 74, 38))
    done(img, "token")


# --------------------------------------------------------------- encodage
def encode(path, size):
    img = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    a = np.array(img)
    a[a[..., 3] < 12] = 0
    img = Image.fromarray(a)
    q = img.quantize(colors=255, method=Image.FASTOCTREE)
    pal = q.getpalette(rawmode="RGBA")[: 256 * 4]
    pal += [0] * (1024 - len(pal))
    idx = np.array(q).ravel()
    rle = bytearray()
    i = 0
    while i < len(idx):
        v = idx[i]
        run = 1
        while i + run < len(idx) and idx[i + run] == v and run < 255:
            run += 1
        rle += bytes((run, int(v)))
        i += run
    return base64.b64encode(bytes(pal)).decode(), base64.b64encode(bytes(rle)).decode()


def write_lua():
    entries, total = [], 0
    for file in sorted(os.listdir(ICONS)):
        name = file[:-4]
        size = 200 if name in sum(NAMES, []) else 96
        pal, rle = encode(os.path.join(ICONS, file), size)
        total += len(rle)
        entries.append(f'\t{name} = {{ size = {size}, palette = "{pal}", data = "{rle}" }},')
    with open(OUT_LUA, "w") as f:
        f.write("-- GENERE par tools/build_icons.py : icones RELIC RUSH (palette RGBA + RLE, base64).\n-- Decodees par Icons.lua et affichees via EditableImage.\n\nreturn {\n")
        f.write("\n".join(entries) + "\n}\n")
    print(f"{len(entries)} icones, {total / 1024:.0f} Ko")


if __name__ == "__main__":
    cut_sheet()
    for fn in (draw_coin, draw_power, draw_relic, draw_lock, draw_close, draw_check, draw_slot, draw_crate, draw_rebirthToken):
        fn()
    write_lua()
    # planche de controle
    files = sorted(os.listdir(ICONS))
    sheet = Image.new("RGBA", (6 * 140, ((len(files) + 5) // 6) * 140), (20, 24, 50, 255))
    for i, f in enumerate(files):
        im = Image.open(os.path.join(ICONS, f)).convert("RGBA").resize((128, 128))
        sheet.alpha_composite(im, ((i % 6) * 140 + 6, (i // 6) * 140 + 6))
    sheet.save(os.path.join(ROOT, "assets", "icons_preview.png"))
