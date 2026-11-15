#!/usr/bin/env python3
"""Decoupe la planche a 5 vues (assets/pet-turnaround5.webp, fond bleu nuit) :
19 pets x (face, 3/4, profil, dos, 3/4 dos) -> assets/turnaround5/<Nom>_<vue>.png"""
import os
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "assets", "pet-turnaround5.webp")
OUT = os.path.join(ROOT, "assets", "turnaround5")
# colonne de gauche : 1 a 10, colonne de droite : 11 a 19 (noms du jeu)
LEFT = ["Cerf", "Chaton", "Cobra", "Genie", "Lapin", "Licorne", "Ours", "Sphinx", "Chameau", "Chiot"]
RIGHT = ["Hibou", "Dragon", "Lezard", "Loup", "Panda", "Phenix", "Scorpion", "Renard", "Pharaon"]
VIEWS = ["front", "q", "side", "back", "qb"]
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def label(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    comps, cur = [], 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not lab[y, x]:
                cur += 1
                q = deque([(y, x)]); lab[y, x] = cur
                ys, xs = [], []
                while q:
                    cy, cx = q.popleft(); ys.append(cy); xs.append(cx)
                    for dy, dx in N4:
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur; q.append((ny, nx))
                comps.append({"id": cur, "n": len(ys), "x0": min(xs), "x1": max(xs) + 1, "y0": min(ys), "y1": max(ys) + 1,
                              "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys), "members": [cur]})
    return lab, comps


def main():
    os.makedirs(OUT, exist_ok=True)
    rgb = np.array(Image.open(SHEET).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb.mean(axis=2)
    # fond : bleu nuit (sombre et bleute) ; les noirs des pets sont neutres
    # fond = zone sombre (bleu nuit ou halo sombre) reliee au bord de l'image ;
    # les yeux, noirs mais enfermes dans le pet, restent au premier plan
    cand = (b - r >= 4) & (lum < 58)
    bg = np.zeros_like(cand)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if cand[y, x]:
                bg[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if cand[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for dy, dx in N4:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True; q.append((ny, nx))
    fg = ~bg
    # retire les bordures fines des panneaux
    fg = np.array(Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 0
    fg[1080:, 610:] = False  # cartouche "19 Pets"
    lab, comps = label(fg)

    def is_label(c):
        hh, ww = c["y1"] - c["y0"], c["x1"] - c["x0"]
        return hh < 30 and ww > hh * 2
    big = [c for c in comps if c["n"] > 500 and not is_label(c)]
    small = [c for c in comps if 15 <= c["n"] <= 500 and not is_label(c)]
    for s in small:
        best = min(big, key=lambda c: max(0, c["x0"] - s["cx"], s["cx"] - c["x1"]) + max(0, c["y0"] - s["cy"], s["cy"] - c["y1"]))
        d = max(0, best["x0"] - s["cx"], s["cx"] - best["x1"]) + max(0, best["y0"] - s["cy"], s["cy"] - best["y1"])
        if d < 8:
            best["members"].append(s["id"])
            best["x0"], best["x1"] = min(best["x0"], s["x0"]), max(best["x1"], s["x1"])
            best["y0"], best["y1"] = min(best["y0"], s["y0"]), max(best["y1"], s["y1"])
    # morceaux empiles dans une meme vue
    merged = True
    while merged:
        merged = False
        big.sort(key=lambda c: -c["n"])
        for a in big:
            for c in big:
                if c is a or c["n"] > a["n"]:
                    continue
                overlap = min(a["x1"], c["x1"]) - max(a["x0"], c["x0"])
                gap = max(a["y0"] - c["y1"], c["y0"] - a["y1"], 0)
                if overlap > 0.5 * (c["x1"] - c["x0"]) and gap < 12:
                    a["members"] += c["members"]
                    a["x0"], a["x1"] = min(a["x0"], c["x0"]), max(a["x1"], c["x1"])
                    a["y0"], a["y1"] = min(a["y0"], c["y0"]), max(a["y1"], c["y1"])
                    a["cy"] = (a["y0"] + a["y1"]) / 2
                    big.remove(c); merged = True
                    break
            if merged:
                break
    labels = [c for c in comps if is_label(c) and c["n"] > 150]
    for names, (cx0, cx1) in ((LEFT, (0, w // 2)), (RIGHT, (w // 2, w))):
        labs = sorted([c for c in labels if cx0 <= c["cx"] < cx1 and c["x0"] - cx0 < 60], key=lambda c: c["y0"])
        if len(labs) < len(names) and len(labs) >= 2:
            # etiquette manquante (collee a un pet) : on la deduit de l'espacement regulier des lignes
            pitch = np.median(np.diff([c["y0"] for c in labs]))
            fixed = [labs[0]]
            for c in labs[1:]:
                while c["y0"] - fixed[-1]["y0"] > pitch * 1.5:
                    prev = fixed[-1]
                    fixed.append(dict(prev, y0=int(prev["y0"] + pitch), y1=int(prev["y1"] + pitch), id=-1))
                fixed.append(c)
            while len(fixed) < len(names):
                prev = fixed[-1]
                fixed.append(dict(prev, y0=int(prev["y0"] + pitch), y1=int(prev["y1"] + pitch), id=-1))
            labs = fixed
        if len(labs) != len(names):
            print("etiquettes trouvees", len(labs), "attendu", len(names))
        # centres des 5 cases, d'apres les lignes bien separees
        col = sorted([c for c in big if cx0 <= c["cx"] < cx1], key=lambda c: c["cy"])
        rows, cur = [], []
        for c in col:
            if cur and c["cy"] - np.mean([x["cy"] for x in cur]) > 60:
                rows.append(cur); cur = []
            cur.append(c)
        rows.append(cur)
        good = [sorted(r, key=lambda c: c["cx"]) for r in rows if len(r) == 5]
        centers = np.mean([[c["cx"] for c in r] for r in good], axis=0)
        for i, name in enumerate(names):
            lab_c = labs[i]
            y0 = max(0, lab_c["y0"] - 6)
            y1 = labs[i + 1]["y0"] - 6 if i + 1 < len(labs) else (1080 if names is RIGHT else h)
            bounds = [lab_c["x1"] + 2] + [(centers[k] + centers[k + 1]) / 2 for k in range(4)] + [cx1]
            band = fg[y0:y1].copy()
            band[np.isin(lab[y0:y1], [c["id"] for c in labels])] = False
            for k, view in enumerate(VIEWS):
                bx0, bx1 = int(bounds[k]), int(bounds[k + 1])
                m = np.zeros_like(band)
                m[:, bx0:bx1] = band[:, bx0:bx1]
                sl, sc = label(m)
                if not sc:
                    print("vue vide", name, view); continue
                biggest = max(c["n"] for c in sc)
                keep = [c["id"] for c in sc if c["n"] >= max(25, biggest * 0.01)]
                m = np.isin(sl, keep)
                ys, xs = np.where(m)
                pad = 2
                x0, x1 = max(0, xs.min() - pad), min(w, xs.max() + 1 + pad)
                yy0, yy1 = max(0, ys.min() - pad), min(y1 - y0, ys.max() + 1 + pad)
                mm = m[yy0:yy1, x0:x1]
                sub = rgb[y0 + yy0:y0 + yy1, x0:x1]
                slum = sub.mean(axis=2)
                ssat = sub.max(axis=2) - sub.min(axis=2)
                shadow = (slum < 62) & (ssat < 35)
                for _ in range(3):  # retire l'ombre grise collee au contour
                    inner = np.array(Image.fromarray((mm * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
                    mm = mm & ~(mm & ~inner & shadow)
                alpha = np.array(Image.fromarray((mm * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5)))
                crop = rgb[y0 + yy0:y0 + yy1, x0:x1].astype(np.uint8)
                Image.fromarray(np.dstack([crop, alpha.astype(np.uint8)])).save(os.path.join(OUT, f"{name}_{view}.png"))
    print("ok")


if __name__ == "__main__":
    main()
