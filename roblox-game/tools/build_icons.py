#!/usr/bin/env python3
"""Genere les icones du jeu.

1. Decoupe assets/icon-sheet.webp (grille 5x4) en 20 PNG dans assets/icons/.
2. Dessine les petites icones (piece, stats, cadenas, gemme, fermer...) dans le meme style.
3. Encode toutes les icones dans src/ReplicatedStorage/Shared/IconData.lua
   (palette 256 couleurs + RLE + base64) pour les afficher sans upload via EditableImage.

Usage : python3 tools/build_icons.py   (necessite Pillow et numpy)
"""
import base64, os
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "icons")
SHEET = os.path.join(ROOT, "assets", "icon-sheet.webp")
OUT_LUA = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "IconData.lua")
os.makedirs(ICONS, exist_ok=True)

# ---------------------------------------------------------------- 1. planche
NAMES = [["index", "eggs", "pets", "shop", "rewards"], ["worlds", "race", "leaderboard", "trading", "quests"],
         ["settings", "inventory", "teleport", "daily", "codes"], ["ranks", "achievements", "freegift", "events", "exit"]]
YCUTS = {0: [0, 235, 450, 645, 844], 1: [0, 232, 448, 648, 844], 2: [0, 231, 444, 650, 844], 3: [0, 233, 449, 652, 844], 4: [0, 231, 450, 653, 844]}
XCUTS = [[0, 302, 607, 877, 1148, 1500], [0, 312, 598, 892, 1165, 1500], [0, 300, 595, 889, 1156, 1500], [0, 285, 595, 879, 1166, 1500]]


def largest_component(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    best, cur = (0, 0), 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                cur += 1
                q = deque([(y, x)])
                lab[y, x] = cur
                n = 0
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            q.append((ny, nx))
                if n > best[1]:
                    best = (cur, n)
    return lab == best[0]


def dilate(mask, it):
    img = Image.fromarray((mask * 255).astype(np.uint8))
    for _ in range(it):
        img = img.filter(ImageFilter.MaxFilter(3))
    return np.array(img) > 0


def square(img, pad=8, size=256):
    w, h = img.size
    s = max(w, h) + pad
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(img, ((s - w) // 2, (s - h) // 2))
    return sq.resize((size, size), Image.LANCZOS)


def cut_sheet():
    if not os.path.exists(SHEET):
        print("planche absente, decoupe ignoree")
        return
    A = np.array(Image.open(SHEET).convert("RGBA"))
    for r, row in enumerate(NAMES):
        for c, name in enumerate(row):
            x0, x1 = XCUTS[r][c], XCUTS[r][c + 1]
            y0, y1 = YCUTS[c][r], YCUTS[c][r + 1]
            cell = A[y0:y1, x0:x1].copy()
            small = (cell[..., 3] > 150)[::2, ::2]
            keep = largest_component(dilate(small, 2))
            keep = np.kron(keep, np.ones((2, 2), dtype=bool))[: cell.shape[0], : cell.shape[1]]
            keep = dilate(keep, 8)
            cell[~keep, 3] = 0
            ys, xs = np.where(cell[..., 3] > 20)
            cell = cell[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
            square(Image.fromarray(cell)).save(os.path.join(ICONS, name + ".png"))


# ---------------------------------------------------------------- 2. icones dessinees
S = 4  # supersampling
BASE = 128
OUT = (25, 18, 40, 255)


def canvas():
    img = Image.new("RGBA", (BASE * S, BASE * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def P(v):
    return v * S


def finish(img):
    return img.resize((BASE, BASE), Image.LANCZOS)


def vgrad(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", size)
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    for y in range(h):
        t = y / max(1, h - 1)
        arr[y, :, :] = [int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)] + [255]
    g = Image.fromarray(arr)
    return g


def fill_shape(img, mask_draw_fn, top, bottom, outline_w=7):
    """Dessine une forme avec contour sombre epais + degrade vertical."""
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    mask_draw_fn(ImageDraw.Draw(mask), 255)
    # contour : masque dilate
    outline = mask.filter(ImageFilter.MaxFilter(outline_w * 2 + 1)) if outline_w else mask
    dark = Image.new("RGBA", (w, h), OUT)
    img.paste(dark, (0, 0), outline)
    img.paste(vgrad((w, h), top, bottom), (0, 0), mask)
    return mask


def gloss(img, box):
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([P(v) for v in box], fill=150)
    m = m.filter(ImageFilter.GaussianBlur(P(1.5)))
    img.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), m)


def glow(img, color, radius=10):
    w, h = img.size
    alpha = img.split()[3].filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(P(radius) / 2))
    halo = Image.new("RGBA", (w, h), color + (0,))
    halo.putalpha(alpha.point(lambda a: int(a * 0.75)))
    halo.alpha_composite(img)
    return halo


def star_points(cx, cy, r1, r2, n=5, rot=-90):
    import math
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180 / n)
        r = r1 if i % 2 == 0 else r2
        pts.append((P(cx + math.cos(a) * r), P(cy + math.sin(a) * r)))
    return pts


def draw_coin():
    img, _ = canvas()
    fill_shape(img, lambda d, f: d.ellipse([P(10), P(10), P(118), P(118)], fill=f), (255, 236, 120), (240, 150, 20))
    fill_shape(img, lambda d, f: d.ellipse([P(28), P(28), P(100), P(100)], fill=f), (250, 185, 40), (255, 225, 110), outline_w=3)
    fill_shape(img, lambda d, f: d.polygon(star_points(64, 66, 26, 11), fill=f), (255, 250, 210), (255, 200, 50), outline_w=4)
    gloss(img, (24, 18, 60, 40))
    return glow(finish_big(img), (255, 200, 40), 4)


def finish_big(img):
    return img  # glow est applique avant la reduction


def draw_bolt():
    img, _ = canvas()
    pts = [(72, 6), (24, 70), (58, 70), (46, 122), (104, 50), (68, 50), (86, 6)]
    fill_shape(img, lambda d, f: d.polygon([(P(x), P(y)) for x, y in pts], fill=f), (255, 245, 140), (255, 170, 0))
    gloss(img, (60, 14, 74, 34))
    return glow(img, (255, 210, 40), 4)


def draw_power():
    img, _ = canvas()
    # flamme
    def flame(d, f):
        d.ellipse([P(26), P(50), P(102), P(122)], fill=f)
        d.polygon([(P(28), P(84)), (P(40), P(30)), (P(54), P(56)), (P(64), P(6)), (P(80), P(52)), (P(92), P(34)), (P(100), P(84))], fill=f)
    fill_shape(img, flame, (255, 220, 80), (240, 60, 30))
    fill_shape(img, lambda d, f: d.ellipse([P(46), P(78), P(82), P(116)], fill=f), (255, 250, 200), (255, 190, 60), outline_w=0)
    gloss(img, (40, 60, 54, 82))
    return glow(img, (255, 110, 40), 4)


def draw_shield():
    img, _ = canvas()
    def sh(d, f):
        d.polygon([(P(64), P(6)), (P(116), P(24)), (P(110), P(74)), (P(64), P(122)), (P(18), P(74)), (P(12), P(24))], fill=f)
    fill_shape(img, sh, (140, 210, 255), (30, 110, 230))
    def inner(d, f):
        d.polygon([(P(64), P(24)), (P(96), P(36)), (P(92), P(70)), (P(64), P(102)), (P(36), P(70)), (P(32), P(36))], fill=f)
    fill_shape(img, inner, (200, 235, 255), (90, 170, 255), outline_w=3)
    gloss(img, (28, 24, 50, 56))
    return glow(img, (60, 160, 255), 4)


def draw_clover():
    img, _ = canvas()
    def cl(d, f):
        for cx, cy in ((64, 34), (36, 60), (92, 60), (64, 86)):
            d.ellipse([P(cx - 26), P(cy - 26), P(cx + 26), P(cy + 26)], fill=f)
        d.line([P(70), P(96), P(86), P(124)], fill=f, width=P(9))
    fill_shape(img, cl, (150, 240, 120), (40, 160, 60))
    gloss(img, (46, 14, 70, 30))
    return glow(img, (80, 220, 90), 4)


def draw_lock():
    img, _ = canvas()
    fill_shape(img, lambda d, f: d.arc([P(32), P(8), P(96), P(80)], 180, 360, fill=f, width=P(14)), (230, 230, 245), (150, 150, 175))
    fill_shape(img, lambda d, f: d.rounded_rectangle([P(18), P(52), P(110), P(122)], radius=P(16), fill=f), (255, 225, 100), (230, 140, 20))
    fill_shape(img, lambda d, f: (d.ellipse([P(54), P(70), P(74), P(90)], fill=f), d.rectangle([P(60), P(84), P(68), P(104)], fill=f)), (40, 30, 50), (40, 30, 50), outline_w=0)
    gloss(img, (26, 58, 44, 80))
    return glow(img, (255, 200, 40), 3)


def draw_gem():
    img, _ = canvas()
    pts = [(64, 8), (112, 46), (64, 122), (16, 46)]
    fill_shape(img, lambda d, f: d.polygon([(P(x), P(y)) for x, y in pts], fill=f), (255, 255, 255), (170, 170, 185))
    fill_shape(img, lambda d, f: d.polygon([(P(64), P(22)), (P(92), P(46)), (P(64), P(94)), (P(36), P(46))], fill=f), (255, 255, 255), (215, 215, 225), outline_w=0)
    gloss(img, (40, 26, 58, 40))
    return img


def draw_star():
    img, _ = canvas()
    fill_shape(img, lambda d, f: d.polygon(star_points(64, 68, 60, 26), fill=f), (255, 245, 150), (255, 160, 0))
    gloss(img, (44, 34, 62, 50))
    return glow(img, (255, 210, 40), 4)


def draw_close():
    img, _ = canvas()
    fill_shape(img, lambda d, f: d.ellipse([P(8), P(8), P(120), P(120)], fill=f), (255, 120, 120), (210, 30, 50))
    def x(d, f):
        d.line([P(40), P(40), P(88), P(88)], fill=f, width=P(16))
        d.line([P(88), P(40), P(40), P(88)], fill=f, width=P(16))
    fill_shape(img, x, (255, 255, 255), (235, 235, 245), outline_w=4)
    gloss(img, (26, 18, 62, 40))
    return img


def draw_paw_small():
    img, _ = canvas()
    def paw(d, f):
        d.ellipse([P(30), P(58), P(98), P(118)], fill=f)
        for cx, cy, r in ((22, 48, 15), (46, 24, 15), (82, 24, 15), (106, 48, 15)):
            d.ellipse([P(cx - r), P(cy - r), P(cx + r), P(cy + r)], fill=f)
    fill_shape(img, paw, (255, 225, 100), (240, 150, 20))
    gloss(img, (42, 64, 62, 78))
    return glow(img, (255, 200, 40), 4)


def draw_egg_small():
    img, _ = canvas()
    fill_shape(img, lambda d, f: d.ellipse([P(22), P(6), P(106), P(122)], fill=f), (255, 255, 255), (200, 200, 220))
    for cx, cy, r in ((50, 46, 11), (80, 74, 13), (52, 94, 8)):
        fill_shape(img, lambda d, f, cx=cx, cy=cy, r=r: d.ellipse([P(cx - r), P(cy - r), P(cx + r), P(cy + r)], fill=f), (200, 170, 255), (150, 110, 240), outline_w=0)
    gloss(img, (38, 18, 54, 44))
    return img


DRAWN = {
    "coin": draw_coin, "speed": draw_bolt, "power": draw_power, "stamina": draw_shield, "luck": draw_clover,
    "lock": draw_lock, "gem": draw_gem, "star": draw_star, "close": draw_close, "paw": draw_paw_small, "egg": draw_egg_small,
}


def build_drawn():
    for name, fn in DRAWN.items():
        img = fn()
        img = img.resize((BASE, BASE), Image.LANCZOS) if img.size[0] != BASE else img
        img.save(os.path.join(ICONS, name + ".png"))


# ---------------------------------------------------------------- 3. encodage Luau
def encode(path, size):
    img = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    arr = np.array(img)
    arr[arr[..., 3] < 8] = 0  # nettoie les pixels presque transparents
    q = Image.fromarray(arr).quantize(colors=255, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    pal = q.getpalette(rawmode="RGBA")[: 256 * 4]
    idx = np.array(q).flatten()
    rle = bytearray()
    i = 0
    n = len(idx)
    while i < n:
        v = idx[i]
        run = 1
        while i + run < n and idx[i + run] == v and run < 255:
            run += 1
        rle += bytes((run, int(v)))
        i += run
    return base64.b64encode(bytes(pal)).decode(), base64.b64encode(bytes(rle)).decode()


def write_lua():
    entries = []
    total = 0
    for file in sorted(os.listdir(ICONS)):
        if not file.endswith(".png"):
            continue
        name = file[:-4]
        size = 128 if name in DRAWN else 192
        pal, rle = encode(os.path.join(ICONS, file), size)
        total += len(rle)
        entries.append(f'\t{name} = {{ size = {size}, palette = "{pal}", data = "{rle}" }},')
    with open(OUT_LUA, "w") as f:
        f.write("-- GENERE AUTOMATIQUEMENT par tools/build_icons.py : ne pas modifier a la main.\n")
        f.write("-- Icones encodees (palette RGBA + RLE, base64), decodees par Icons.lua.\n\n")
        f.write("return {\n" + "\n".join(entries) + "\n}\n")
    print(f"{len(entries)} icones -> IconData.lua ({total // 1024} Ko de donnees)")


if __name__ == "__main__":
    cut_sheet()
    build_drawn()
    write_lua()
