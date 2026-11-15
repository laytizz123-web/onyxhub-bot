#!/usr/bin/env python3
"""Decoupe assets/pet-sheet.webp (fond en damier dessine) en un PNG transparent par pet.

Le damier est retire par remplissage depuis les bords sur les pixels gris clair / gris moyen
peu satures. Les pets sont ensuite separes par composantes connexes et nommes dans l'ordre
de lecture (ligne par ligne, de gauche a droite) selon PET_ORDER.
Usage : python3 tools/cut_pets.py
"""
import os
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "assets", "pet-sheet.webp")
OUT = os.path.join(ROOT, "assets", "pets")
PET_ORDER = [
    ["Chaton", "Chiot", "Lapin", "Renard", "Hibou", "Licorne"],
    ["Cerf", "Loup", "Ours", "Panda", "Phenix", "Dragon"],
    ["Scorpion", "Chameau", "Cobra", "Lezard", "Sphinx", "Genie", "Pharaon"],
]


RELAXED = {"Phenix"}
STRICT = {"Lapin", "Panda", "Licorne"}
SEAL = 9


def flood_from_border(mask):
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


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
                pts = []
                while q:
                    cy, cx = q.popleft()
                    pts.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            q.append((ny, nx))
                ys = [p[0] for p in pts]
                xs = [p[1] for p in pts]
                comps.append({"id": cur, "n": len(pts), "box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1)})
    return lab, comps


def main():
    os.makedirs(OUT, exist_ok=True)
    rgb = np.array(Image.open(SHEET).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    grey = rgb.mean(axis=2)
    sat = mx - mn

    # le damier est neutre a legerement bleute ; les pelages blancs sont chauds (rouge > bleu)
    cool = (rgb[..., 2] - rgb[..., 0]) >= -1
    checker = (sat <= 10) & cool & ((grey >= 244) | ((grey >= 208) & (grey <= 240)))
    # remplissage depuis les bords
    bg = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if checker[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if checker[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and checker[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    fg = ~bg
    # nettoyage : supprime le liseré clair (erosion 1 px) puis adoucit le bord
    fg_img = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    alpha = np.array(fg_img.filter(ImageFilter.GaussianBlur(0.7)))
    fg = alpha > 128
    small = fg[::2, ::2]
    lab, comps = label(small)
    big = [c for c in comps if c["n"] > 1500]
    tiny = [c for c in comps if c["n"] <= 1500]
    # rattache les petits morceaux (flammes, queues) au pet le plus proche
    for c in big:
        c["members"] = [c["id"]]
    for t in tiny:
        if t["n"] < 15:
            continue
        tx = (t["box"][0] + t["box"][2]) / 2
        ty = (t["box"][1] + t["box"][3]) / 2
        best = min(big, key=lambda b: max(0, b["box"][0] - tx, tx - b["box"][2]) + max(0, b["box"][1] - ty, ty - b["box"][3]))
        best["members"].append(t["id"])
        bx0, by0, bx1, by1 = best["box"]
        x0, y0, x1, y1 = t["box"]
        best["box"] = (min(bx0, x0), min(by0, y0), max(bx1, x1), max(by1, y1))
    # ordre de lecture : lignes par centre vertical
    for c in big:
        c["cx"] = (c["box"][0] + c["box"][2]) / 2
        c["cy"] = (c["box"][1] + c["box"][3]) / 2
    big.sort(key=lambda c: c["cy"])
    rows, idx = [], 0
    for names in PET_ORDER:
        row = sorted(big[idx: idx + len(names)], key=lambda c: c["cx"])
        rows.append(row)
        idx += len(names)
    assert idx == len(big), f"{len(big)} pets trouves, {idx} attendus"
    rgba = np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)])
    for names, row in zip(PET_ORDER, rows):
        for name, c in zip(names, row):
            member = np.isin(lab, c["members"])
            member = np.kron(member, np.ones((2, 2), dtype=bool))[:h, :w]
            member = np.array(Image.fromarray((member * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
            x0, y0, x1, y1 = [v * 2 for v in c["box"]]
            x0, y0 = max(0, x0 - 4), max(0, y0 - 4)
            x1, y1 = min(w, x1 + 4), min(h, y1 + 4)
            crop = rgba[y0:y1, x0:x1].copy()
            alpha_c = np.where(member[y0:y1, x0:x1], crop[..., 3], 0)
            sub_rgb = rgb[y0:y1, x0:x1]
            if name in STRICT:
                # pets tres blancs : fond = seulement le gris parfaitement neutre-bleute
                sg = sub_rgb.mean(axis=2)
                ss = sub_rgb.max(axis=2) - sub_rgb.min(axis=2)
                strict = (ss <= 6) & ((sub_rgb[..., 2] - sub_rgb[..., 0]) >= 1) & ((sg >= 248) | ((sg >= 210) & (sg <= 236)))
                bg_strict = flood_from_border(strict)
                soft = np.array(Image.fromarray(((~bg_strict) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)))
                alpha_c = np.where(member[y0:y1, x0:x1] | (soft >= 128), np.maximum(alpha_c, soft), 0)
                alpha_c = np.where(bg_strict, np.minimum(alpha_c, soft), alpha_c)
                # ne garde que ce qui est relie au corps du pet (supprime les points isoles)
                lab4, comps4 = label(alpha_c >= 128)
                core = member[y0:y1, x0:x1]
                keep = np.zeros_like(core)
                for c4 in comps4:
                    region = lab4 == c4["id"]
                    if c4["n"] > 400 and (region & core).sum() > 0.5 * c4["n"]:
                        keep |= region
                keep = np.array(Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
                alpha_c = np.where(keep, alpha_c, 0)
            if name in RELAXED:
                # halo de flammes : retire aussi le damier legerement teinte relie au fond
                sg = sub_rgb.mean(axis=2)
                ss = sub_rgb.max(axis=2) - sub_rgb.min(axis=2)
                loose = (ss <= 110) & (sg >= 185)
                lab2, comps2 = label(loose)
                kill = np.zeros_like(loose)
                for c2 in comps2:
                    if c2["n"] > 150:
                        kill |= lab2 == c2["id"]
                kill |= flood_from_border(loose | (alpha_c < 128)) & loose
                alpha_c = np.where(kill, 0, alpha_c)
            # rebouche les trous interieurs (fuites du remplissage dans les zones blanches)
            solid = alpha_c >= 128
            sealed = np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(SEAL)).filter(ImageFilter.MinFilter(SEAL))) > 0
            outside = flood_from_border(~sealed)
            holes = ~outside & ~solid
            sub_checker = checker[y0:y1, x0:x1]
            lab3, comps3 = label(holes)
            for c3 in comps3:
                region = lab3 == c3["id"]
                # un trou rempli de damier est du vrai fond enferme (entre une queue et un corps...)
                if sub_checker[region].mean() < 0.5:
                    alpha_c = np.where(region, 255, alpha_c)
            # retire le liseré de damier sur le bord (2 passes)
            for _ in range(6):
                solid = alpha_c >= 128
                edge = solid & ~(np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0)
                fringe = edge & (sub_rgb.max(axis=2) - sub_rgb.min(axis=2) <= 14) & (sub_rgb.mean(axis=2) >= 200) & ((sub_rgb[..., 2] - sub_rgb[..., 0]) >= -3)
                alpha_c = np.where(fringe, 0, alpha_c)
            crop[..., 3] = alpha_c
            img = Image.fromarray(crop)
            cw, ch = img.size
            s = max(cw, ch) + 12
            sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            sq.paste(img, ((s - cw) // 2, (s - ch) // 2))
            sq.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print(f"{len(big)} pets decoupes dans assets/pets/")


if __name__ == "__main__":
    main()
