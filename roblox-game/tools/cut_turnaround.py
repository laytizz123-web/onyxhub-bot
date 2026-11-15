#!/usr/bin/env python3
"""Decoupe la planche de vues (assets/pet-turnaround.webp) : 19 pets x 4 vues
(trois-quarts, face, profil, dos) -> assets/turnaround/<Nom>_<vue>.png (fond transparent)."""
import os
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "assets", "pet-turnaround.webp")
OUT = os.path.join(ROOT, "assets", "turnaround")
# Ordre des panneaux sur la planche (ligne par ligne). Sur la planche, "Pharaon" est le lion a coiffe
# et "Sphinx" le chat couronne : on les remet selon la liste du jeu (Sphinx = lion, Pharaon = chat couronne).
PANELS = [["Cerf", "Chameau", "Chaton"], ["Chiot", "Cobra", "Dragon"], ["Genie", "Hibou", "Lapin"],
          ["Lezard", "Licorne", "Loup"], ["Ours", "Panda", "Sphinx"], ["Phenix", "Renard", "Scorpion"], ["Pharaon"]]
VIEWS = ["hero", "front", "side", "back"]
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
                              "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys)})
    return lab, comps


def main():
    os.makedirs(OUT, exist_ok=True)
    rgb = np.array(Image.open(SHEET).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # fond : bleu ciel clair (page, panneaux, bordures)
    bg = (b >= 228) & (g >= 160) & (r >= 90) & (b - r >= 55) & (b - g >= 25)
    fg = ~bg
    fg[:95, :] = False  # titre
    fg = np.array(Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 0
    lab, comps = label(fg)
    # etiquettes des panneaux : rectangles bleu fonce, larges et bas
    def is_tab(c):
        hh, ww = c["y1"] - c["y0"], c["x1"] - c["x0"]
        return hh < 42 and ww > hh * 1.6
    big = [c for c in comps if c["n"] > 600 and not is_tab(c)]
    small = [c for c in comps if 20 <= c["n"] <= 600 and not is_tab(c)]
    for c in big:
        c["members"] = [c["id"]]
    for s in small:
        best = min(big, key=lambda c: max(0, c["x0"] - s["cx"], s["cx"] - c["x1"]) + max(0, c["y0"] - s["cy"], s["cy"] - c["y1"]))
        d = max(0, best["x0"] - s["cx"], s["cx"] - best["x1"]) + max(0, best["y0"] - s["cy"], s["cy"] - best["y1"])
        if d < 12:
            best["members"].append(s["id"])
            best["x0"], best["x1"] = min(best["x0"], s["x0"]), max(best["x1"], s["x1"])
            best["y0"], best["y1"] = min(best["y0"], s["y0"]), max(best["y1"], s["y1"])
    # fusionne les morceaux empiles dans la meme vue (ex. chignon du genie separe du corps)
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
                if overlap > 0.5 * (c["x1"] - c["x0"]) and gap < 20:
                    a["members"] += c["members"]
                    a["x0"], a["x1"] = min(a["x0"], c["x0"]), max(a["x1"], c["x1"])
                    a["y0"], a["y1"] = min(a["y0"], c["y0"]), max(a["y1"], c["y1"])
                    a["cy"] = (a["y0"] + a["y1"]) / 2
                    big.remove(c)
                    merged = True
                    break
            if merged:
                break
    expected = sum(len(r) * 4 for r in PANELS)
    print(f"{len(big)} vues trouvees (attendu {expected})")
    big.sort(key=lambda c: c["cy"])
    rows, cur = [], []
    for c in big:
        if cur and c["cy"] - cur[-1]["cy"] > 90:
            rows.append(cur); cur = []
        cur.append(c)
    rows.append(cur)
    for names, row in zip(PANELS, rows):
        row.sort(key=lambda c: c["cx"])
        if len(row) != len(names) * 4:
            print("ligne inattendue", names, len(row), [(int(c["cx"]), int(c["cy"]), c["n"]) for c in row])
            continue
        for k, name in enumerate(names):
            for v, view in enumerate(VIEWS):
                c = row[k * 4 + v]
                pad = 3
                x0, x1, y0, y1 = max(0, c["x0"] - pad), min(w, c["x1"] + pad), max(0, c["y0"] - pad), min(h, c["y1"] + pad)
                m = np.isin(lab[y0:y1, x0:x1], c["members"])
                m = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
                m &= fg[y0:y1, x0:x1] | ~bg[y0:y1, x0:x1]
                alpha = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)))
                img = np.dstack([rgb[y0:y1, x0:x1].astype(np.uint8), alpha.astype(np.uint8)])
                Image.fromarray(img).save(os.path.join(OUT, f"{name}_{view}.png"))
    print("ok")


if __name__ == "__main__":
    main()
