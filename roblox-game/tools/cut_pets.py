#!/usr/bin/env python3
"""Decoupe assets/pet-sheet.webp (fond en damier dessine) en un PNG transparent par pet.

1. Le damier (gris clair / gris moyen, neutre a legerement bleute) est retire par remplissage
   depuis les bords. Les pelages blancs sont chauds (rouge > bleu), ce qui les protege.
2. Les 19 pets sont reperes (grosses zones), puis chaque morceau detache (aile, flamme,
   bout de queue) est rattache au pet le plus proche par propagation.
3. Les morsures du contour sont rebouchees : un creux est rempli s'il ne contient pas de cases
   gris moyen du damier (un vrai trou de fond contient toujours les deux couleurs du damier).
Usage : python3 tools/cut_pets.py
"""
import os
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "assets", "pet-sheet.webp")
OUT = os.path.join(ROOT, "assets", "pets_from_sheet")  # assets/pets contient les images fournies
PET_ORDER = [
    ["Chaton", "Chiot", "Lapin", "Renard", "Hibou", "Licorne"],
    ["Cerf", "Loup", "Ours", "Panda", "Phenix", "Dragon"],
    ["Scorpion", "Chameau", "Cobra", "Lezard", "Sphinx", "Genie", "Pharaon"],
]
RELAXED = {"Phenix"}  # halo de flammes transparent par-dessus le damier

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def mask_img(m):
    return Image.fromarray((m * 255).astype(np.uint8))


def dilate(m, size):
    return np.array(mask_img(m).filter(ImageFilter.MaxFilter(size))) > 0


def erode(m, size):
    return np.array(mask_img(m).filter(ImageFilter.MinFilter(size))) > 0


def closing(m, radius):
    # plusieurs petits filtres = plus rapide qu'un gros
    out = m
    for _ in range(radius):
        out = dilate(out, 3)
    for _ in range(radius):
        out = erode(out, 3)
    return out


def flood(mask, seeds):
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for y, x in seeds:
        if mask[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for dy, dx in N4:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def border_seeds(h, w):
    return [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]


def label(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    comps = []
    cur = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                cur += 1
                q = deque([(y, x)])
                lab[y, x] = cur
                n, sy, sx = 0, 0, 0
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    sy += cy
                    sx += cx
                    for dy, dx in N4:
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            q.append((ny, nx))
                comps.append({"id": cur, "n": n, "cy": sy / n, "cx": sx / n})
    return lab, comps


def main():
    os.makedirs(OUT, exist_ok=True)
    rgb = np.array(Image.open(SHEET).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    grey = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    cool = (rgb[..., 2] - rgb[..., 0]) >= -1
    light_sq = (sat <= 10) & cool & (grey >= 244)
    dark_sq = (sat <= 10) & cool & (grey >= 208) & (grey <= 232)
    checker = light_sq | (dark_sq | ((sat <= 10) & cool & (grey > 232) & (grey < 244)))

    bg = flood(checker, border_seeds(h, w))
    fg = ~bg
    fg = erode(fg, 3)  # retire le lisere d'anticrenelage du damier

    # --- reperage des pets (demi-resolution pour aller vite)
    small = fg[::2, ::2]
    lab, comps = label(small)
    big = sorted([c for c in comps if c["n"] > 1500], key=lambda c: c["cy"])
    expected = sum(len(r) for r in PET_ORDER)
    assert len(big) == expected, f"{len(big)} pets trouves, {expected} attendus"
    names = {}
    i = 0
    for row in PET_ORDER:
        for name, c in zip(row, sorted(big[i: i + len(row)], key=lambda c: c["cx"])):
            names[c["id"]] = name
        i += len(row)

    # propagation : chaque pixel de premier plan prend l'etiquette du pet le plus proche
    sh, sw = small.shape
    owner = np.zeros((sh, sw), dtype=np.int32)
    q = deque()
    for c in big:
        ys, xs = np.where(lab == c["id"])
        owner[ys, xs] = c["id"]
        q.extend(zip(ys.tolist(), xs.tolist()))
    reach = dilate(small, 13)
    while q:
        cy, cx = q.popleft()
        v = owner[cy, cx]
        for dy, dx in N4:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < sh and 0 <= nx < sw and reach[ny, nx] and owner[ny, nx] == 0:
                owner[ny, nx] = v
                q.append((ny, nx))
    # morceaux isoles restants : centre le plus proche
    for c in comps:
        if c["n"] >= 10 and owner[int(c["cy"]), int(c["cx"])] == 0:
            best = min(big, key=lambda b: (b["cy"] - c["cy"]) ** 2 + (b["cx"] - c["cx"]) ** 2)
            owner[lab == c["id"]] = best["id"]
    owner_full = np.kron(owner, np.ones((2, 2), dtype=np.int32))[:h, :w]

    for pid, name in names.items():
        mask = fg & (owner_full == pid)
        ys, xs = np.where(mask)
        pad = 24
        y0, y1 = max(0, ys.min() - pad), min(h, ys.max() + pad)
        x0, x1 = max(0, xs.min() - pad), min(w, xs.max() + pad)
        m = mask[y0:y1, x0:x1]
        sub = rgb[y0:y1, x0:x1]
        dsq = dark_sq[y0:y1, x0:x1]
        chk = checker[y0:y1, x0:x1]
        # damier assombri par l'ombre au sol : gris neutre a legerement bleute
        neutral = (sat[y0:y1, x0:x1] <= 14) & ((rgb[y0:y1, x0:x1, 2] - rgb[y0:y1, x0:x1, 0]) >= -4) & (grey[y0:y1, x0:x1] >= 140)
        others = (owner_full[y0:y1, x0:x1] != pid) & (owner_full[y0:y1, x0:x1] != 0) & fg[y0:y1, x0:x1]

        # rebouche les morsures et les trous qui ne sont pas du vrai fond
        for radius in (6, 14):
            closed = closing(m, radius)
            added = closed & ~m & ~others
            lab3, comps3 = label(added)
            for c3 in comps3:
                region = lab3 == c3["id"]
                dark_frac = dsq[region].mean()
                checker_frac = chk[region].mean()
                shadow_frac = neutral[region].mean()
                if (dark_frac < 0.06 or checker_frac < 0.35) and shadow_frac < 0.5:
                    m |= region
        outside = flood(~m, border_seeds(*m.shape))
        holes = ~outside & ~m
        lab4, comps4 = label(holes)
        for c4 in comps4:
            region = lab4 == c4["id"]
            if dsq[region].mean() < 0.06 and neutral[region].mean() < 0.5:
                m |= region

        if name in RELAXED:
            sg = sub.mean(axis=2)
            ss = sub.max(axis=2) - sub.min(axis=2)
            loose = (ss <= 110) & (sg >= 185) & m
            lab2, comps2 = label(loose)
            for c2 in comps2:
                if c2["n"] > 150:
                    m &= lab2 != c2["id"]

        # lisere : retire les pixels de bord clairs et neutres (melange pet + damier)
        sg = sub.mean(axis=2)
        ss = sub.max(axis=2) - sub.min(axis=2)
        pale = (sg >= 196) & (ss <= 24) & ((sub[..., 2] - sub[..., 0]) >= -6)
        for _ in range(4):
            edge = m & ~erode(m, 3)
            m &= ~(edge & (chk | pale))
        # supprime les grains isoles
        lab5, comps5 = label(m)
        if comps5:
            main_n = max(c["n"] for c in comps5)
            for c5 in comps5:
                if c5["n"] < max(40, main_n * 0.002):
                    m &= lab5 != c5["id"]

        alpha = np.array(mask_img(m).filter(ImageFilter.GaussianBlur(0.8)))
        crop = np.dstack([sub.astype(np.uint8), alpha.astype(np.uint8)])
        img = Image.fromarray(crop)
        ys, xs = np.where(alpha > 20)
        img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        cw, ch = img.size
        s = max(cw, ch) + 12
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sq.paste(img, ((s - cw) // 2, (s - ch) // 2))
        sq.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print(f"{len(names)} pets decoupes dans assets/pets/")


if __name__ == "__main__":
    main()
