#!/usr/bin/env python3
"""Reconstruit chaque pet en 3D a partir de ses vues de face, profil et dos (assets/turnaround/).

Forme : pour chaque hauteur, la silhouette de face donne la largeur, celle de profil la profondeur ;
chaque paire (troncon de face, troncon de profil) est remplie par une section ovale (corps ronds,
pattes, oreilles et queue a la bonne profondeur). Surface extraite par "surface nets", lissee.
Peinture : chaque triangle prend la vue qui lui fait face (face, dos, profil droit ou gauche).
Sortie : assets/pets_glb/<Nom>.glb, TousLesPets.glb et <Nom>_apercu.png.
Usage : python3 tools/turnaround_3d.py [Nom ...]
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inflate_pets import write_glb, write_combined_glb, render, bleed  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "turnaround")
OUT = os.path.join(ROOT, "assets", "pets_glb")
NAMES = ["Chaton", "Chiot", "Lapin", "Renard", "Hibou", "Licorne", "Cerf", "Loup", "Ours", "Panda",
         "Phenix", "Dragon", "Scorpion", "Chameau", "Cobra", "Lezard", "Sphinx", "Genie", "Pharaon"]
BASE_GRID = 54     # nombre de voxels sur la hauteur
GRID = BASE_GRID
MAX_TRIS = 19000   # Roblox refuse plus de 20 000 triangles par piece
HEIGHT = 4.2       # hauteur du pet en studs
TILE = 256         # resolution de chaque vue dans la texture
VIEW_H = 200       # hauteur de travail des vues (pixels)


def load_view(name, view):
    img = Image.open(os.path.join(SRC, f"{name}_{view}.png")).convert("RGBA")
    a = np.array(img)
    rgb = a[..., :3].astype(int)
    mask = a[..., 3] > 128
    h = mask.shape[0]
    rows = np.arange(h)[:, None]
    # ombre bleue au sol sous le pet
    if name != "Genie":
        blue = (rgb[..., 2] - rgb[..., 0] > 50) & (rgb[..., 2] > 140) & (rgb[..., 2] - rgb[..., 1] > 25)
        mask &= ~(blue & (rows > h * 0.72))
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    a = a[y0:y1, x0:x1].copy()
    a[..., 3] = np.where(mask[y0:y1, x0:x1], 255, 0)
    img = Image.fromarray(a)
    w = max(1, round(img.width * VIEW_H / img.height))
    return img.resize((w, VIEW_H), Image.LANCZOS)


def facing_right(side):
    """Le profil regarde-t-il vers la droite ? (les yeux, tres sombres, sont du cote du museau)"""
    a = np.array(side).astype(int)
    m = a[..., 3] > 128
    grey = a[..., :3].mean(axis=2)
    h, w = m.shape
    dark = m & (grey < 55)
    dark[h // 2:] = False
    if dark.sum() < 5:
        return True
    xs = np.where(dark)[1]
    cx = np.where(m)[1].mean()
    return xs.mean() >= cx


def runs(mask_row):
    """Centre et demi-largeur du troncon auquel appartient chaque pixel de la ligne."""
    n = len(mask_row)
    c = np.zeros(n); hw = np.ones(n)
    i = 0
    while i < n:
        if mask_row[i]:
            j = i
            while j < n and mask_row[j]:
                j += 1
            c[i:j] = (i + j - 1) / 2
            hw[i:j] = max((j - i) / 2, 0.75)
            i = j
        else:
            i += 1
    return c, hw


def resize_mask(img, w, h):
    a = np.array(img.split()[3].resize((w, h), Image.BILINEAR)) > 127
    return a


def surface_nets(f, iso=0.5):
    """Extraction de surface (dual) sur un champ 3D f[y, x, z]."""
    ny, nx, nz = f.shape
    inside = f > iso
    # sommets : un par cellule active
    corners = [(dy, dx, dz) for dy in (0, 1) for dx in (0, 1) for dz in (0, 1)]
    cell_in = np.stack([inside[dy:ny - 1 + dy, dx:nx - 1 + dx, dz:nz - 1 + dz] for dy, dx, dz in corners])
    active = cell_in.any(0) & ~cell_in.all(0)
    edges = [((0, 0, 0), (1, 0, 0)), ((0, 1, 0), (1, 1, 0)), ((0, 0, 1), (1, 0, 1)), ((0, 1, 1), (1, 1, 1)),
             ((0, 0, 0), (0, 1, 0)), ((1, 0, 0), (1, 1, 0)), ((0, 0, 1), (0, 1, 1)), ((1, 0, 1), (1, 1, 1)),
             ((0, 0, 0), (0, 0, 1)), ((1, 0, 0), (1, 0, 1)), ((0, 1, 0), (0, 1, 1)), ((1, 1, 0), (1, 1, 1))]
    acc = np.zeros(active.shape + (3,)); cnt = np.zeros(active.shape)
    for a, b in edges:
        fa = f[a[0]:ny - 1 + a[0], a[1]:nx - 1 + a[1], a[2]:nz - 1 + a[2]]
        fb = f[b[0]:ny - 1 + b[0], b[1]:nx - 1 + b[1], b[2]:nz - 1 + b[2]]
        cross = (fa > iso) != (fb > iso)
        t = np.clip((iso - fa) / np.where(np.abs(fb - fa) < 1e-9, 1e-9, fb - fa), 0, 1)
        for k in range(3):
            acc[..., k] += np.where(cross, a[k] + t * (b[k] - a[k]), 0)
        cnt += cross
    idx = -np.ones(active.shape, int)
    cy, cx, cz = np.where(active)
    idx[cy, cx, cz] = np.arange(len(cy))
    verts = np.stack([cy, cx, cz], 1) + acc[cy, cx, cz] / cnt[cy, cx, cz][:, None]
    quads = []
    outs = []
    # faces : une par arete de la grille qui traverse la surface
    for axis in range(3):
        o1, o2 = [ax for ax in range(3) if ax != axis]
        sl_a = [slice(1, -1)] * 3
        sl_b = [slice(1, -1)] * 3
        sl_a[axis] = slice(0, -1)
        sl_b[axis] = slice(1, None)
        fa = inside[tuple(sl_a)]
        fb = inside[tuple(sl_b)]
        cross = fa != fb
        pts = np.stack(np.where(cross), 1)
        for p, flip in zip(pts, fa[cross]):
            q = p.copy()
            q[o1] += 1; q[o2] += 1  # coordonnees de point de grille (decalage du slice 1:-1)
            base = q.copy(); base[axis] -= 1 if False else 0
            # les 4 cellules autour de l'arete
            c = []
            for d1, d2 in ((-1, -1), (0, -1), (0, 0), (-1, 0)):
                cc = q.copy(); cc[o1] += d1; cc[o2] += d2
                cc[axis] = p[axis]
                c.append(idx[tuple(cc)])
            if min(c) < 0:
                continue
            quads.append(c)
            # direction exterieure : de l'interieur vers l'exterieur le long de l'axe
            out = np.zeros(3)
            out[axis] = 1.0 if flip else -1.0
            outs.append(out)
    return verts, np.array(quads), np.array(outs)


def build(name, grid=None):
    global GRID
    GRID = grid or BASE_GRID
    front = load_view(name, "front")
    side = load_view(name, "side")
    back = load_view(name, "back")
    if not facing_right(side):
        side = side.transpose(Image.FLIP_LEFT_RIGHT)
    # dimensions de la grille (y vers le bas dans les images)
    s = GRID / VIEW_H
    nx = max(4, round(front.width * s))
    nz = max(4, round(side.width * s))
    ny = GRID
    Mf = resize_mask(front, nx, ny)
    Ms = resize_mask(side, nz, ny)[:, ::-1]  # colonne 0 = museau (avant, -Z)
    xc = np.zeros((ny, nx)); hx = np.ones((ny, nx)); zc = np.zeros((ny, nz)); hz = np.ones((ny, nz))
    for y in range(ny):
        xc[y], hx[y] = runs(Mf[y])
        zc[y], hz[y] = runs(Ms[y])
    X = np.arange(nx)[None, :, None]; Z = np.arange(nz)[None, None, :]
    ell = ((X - xc[:, :, None]) / (hx[:, :, None] + 0.35)) ** 2 + ((Z - zc[:, None, :]) / (hz[:, None, :] + 0.35)) ** 2
    occ = Mf[:, :, None] & Ms[:, None, :] & (ell <= 1.0)
    f = occ.astype(float)
    f = np.pad(f, 2)
    for _ in range(3):  # lissage du champ
        g = f.copy()
        for ax in range(3):
            g = (np.roll(g, 1, ax) + g * 2 + np.roll(g, -1, ax)) / 4
        f = g
    verts, quads, outs = surface_nets(f)
    # lissage des sommets (Laplacien)
    nb = [[] for _ in range(len(verts))]
    for q in quads:
        for k in range(4):
            nb[q[k]].append(q[(k + 1) % 4]); nb[q[k]].append(q[(k + 3) % 4])
    for _ in range(6):
        new = verts.copy()
        for i, n in enumerate(nb):
            if n:
                new[i] = 0.5 * verts[i] + 0.5 * verts[n].mean(0)
        verts = new
    # repere monde : grille (y bas, x, z) -> studs ; avant = -Z ; droite de l'image de face = -X
    unit = HEIGHT / GRID
    gy, gx, gz = verts[:, 0] - 2, verts[:, 1] - 2, verts[:, 2] - 2
    pos = np.stack([-(gx - (nx - 1) / 2) * unit, (ny - 1 - gy) * unit, (gz - (nz - 1) / 2) * unit], 1).astype(np.float32)
    pos[:, 1] -= pos[:, 1].min()
    tris = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]])
    out_dir = np.concatenate([outs, outs])
    # grille (y, x, z) -> monde : y et x sont inverses
    out_world = np.stack([-out_dir[:, 1], -out_dir[:, 0], out_dir[:, 2]], 1)
    p0, p1, p2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    wrong = np.einsum("ij,ij->i", fn, out_world) < 0
    tris[wrong] = tris[wrong][:, ::-1]
    fn[wrong] = -fn[wrong]
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    # vue : 0 face (-Z), 1 dos (+Z), 2 profil droit (+X), 3 profil gauche (-X)
    w = np.stack([np.maximum(0, -fn[:, 2]), np.maximum(0, fn[:, 2]) * 1.05, np.maximum(0, fn[:, 0]) * 1.1, np.maximum(0, -fn[:, 0]) * 1.1], 1)
    view = np.argmax(w, 1)
    # UV par vue (coordonnees normalisees dans chaque tuile de la texture)
    xs = gx / max(nx - 1, 1); ys = gy / max(ny - 1, 1); zs = gz / max(nz - 1, 1)
    out_pos, out_uv, out_tris, remap = [], [], [], {}
    for t, v in zip(tris, view):
        tri = []
        for vi in t:
            key = (int(vi), int(v))
            if key not in remap:
                if v == 0:
                    u = xs[vi]
                elif v == 1:
                    u = 1 - xs[vi]
                elif v == 2:
                    u = 1 - zs[vi]  # profil vu depuis +X : le museau a droite
                else:
                    u = zs[vi]
                u = np.clip(u, 0.002, 0.998)
                remap[key] = len(out_pos)
                out_pos.append(pos[vi])
                out_uv.append(((v + u) / 4, np.clip(ys[vi], 0.002, 0.998)))
            tri.append(remap[key])
        out_tris.append(tri)
    pos2 = np.array(out_pos, np.float32)
    uv2 = np.array(out_uv, np.float32)
    tris2 = np.array(out_tris, np.uint32)
    # normales lissees par vue
    nrm = np.zeros_like(pos2)
    a, b, c = pos2[tris2[:, 0]], pos2[tris2[:, 1]], pos2[tris2[:, 2]]
    n = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(nrm, tris2[:, k], n)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    # texture : 4 tuiles (face, dos, profil, profil miroir)
    def tile(img, mirror=False):
        arr = np.array(img).astype(float)
        solid = arr[..., 3] > 200
        solid = np.array(Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
        rgb = bleed(arr[..., :3], solid, iters=30)
        im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize((TILE, TILE), Image.LANCZOS)
        im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
        return im.transpose(Image.FLIP_LEFT_RIGHT) if mirror else im
    side_img = side  # museau a droite
    atlas = Image.new("RGB", (TILE * 4, TILE))
    atlas.paste(tile(front), (0, 0))
    atlas.paste(tile(back), (TILE, 0))
    atlas.paste(tile(side_img), (TILE * 2, 0))
    atlas.paste(tile(side_img, mirror=True), (TILE * 3, 0))
    return pos2, nrm, uv2, tris2, atlas


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or NAMES
    built = []
    for name in names:
        grid = BASE_GRID
        pos, nrm, uv, tris, atlas = build(name, grid)
        while len(tris) > MAX_TRIS and grid > 30:
            grid -= 4
            pos, nrm, uv, tris, atlas = build(name, grid)
        write_glb(os.path.join(OUT, name + ".glb"), pos, nrm, uv, tris, atlas)
        views = [render(pos, nrm, uv, tris, atlas, yaw) for yaw in (180, 145, 90, 35, 0)]
        sheet = Image.new("RGB", (300 * len(views), 300))
        for k, im in enumerate(views):
            sheet.paste(im, (300 * k, 0))
        sheet.save(os.path.join(OUT, name + "_apercu.png"))
        built.append((name, pos, nrm, uv, tris, atlas))
        print(f"{name}: {len(pos)} sommets, {len(tris)} triangles")
    if not sys.argv[1:]:
        write_combined_glb(os.path.join(OUT, "TousLesPets.glb"), built)
        print("-> TousLesPets.glb")


if __name__ == "__main__":
    main()
