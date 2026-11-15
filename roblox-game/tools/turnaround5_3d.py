#!/usr/bin/env python3
"""Reconstruit chaque pet en 3D a partir de 5 vues (assets/turnaround5/) : face, 3/4, profil, dos, 3/4 dos.

1. Volume : sections ovales a partir des silhouettes de face et de profil, puis sculpte par les
   silhouettes de 3/4 et 3/4 dos (et leurs symetriques).
2. Surface : surface nets + lissage, faces orientees vers l'exterieur.
3. Peinture : 8 directions tous les 45 degres (les 5 vues + 3 miroirs) ; chaque triangle prend
   la vue la plus en face de lui.
Sortie : assets/pets_glb/<Nom>.glb, TousLesPets.glb, <Nom>_apercu.png
Usage : python3 tools/turnaround5_3d.py [Nom ...]
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inflate_pets import write_glb, write_combined_glb, render, bleed  # noqa: E402
from turnaround_3d import runs, surface_nets  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "turnaround5")
OUT = os.path.join(ROOT, "assets", "pets_glb")
NAMES = ["Chaton", "Chiot", "Lapin", "Renard", "Hibou", "Licorne", "Cerf", "Loup", "Ours", "Panda",
         "Phenix", "Dragon", "Scorpion", "Chameau", "Cobra", "Lezard", "Sphinx", "Genie", "Pharaon"]
BASE_GRID = 56
USE_QUARTER_VIEWS = False  # les vues 3/4 generees par IA ne sont pas exactement a 45 degres : desactivees
MAX_TRIS = 19000
HEIGHT = 4.2
TILE = 256
VIEW_H = 200


def load(name, view):
    img = Image.open(os.path.join(SRC, f"{name}_{view}.png")).convert("RGBA")
    a = np.array(img)
    m = a[..., 3] > 128
    ys, xs = np.where(m)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    img = Image.fromarray(a)
    return img.resize((max(1, round(img.width * VIEW_H / img.height)), VIEW_H), Image.LANCZOS)


def face_right(img):
    """Le museau est-il a droite de l'image ? (yeux tres sombres dans la moitie haute)"""
    a = np.array(img).astype(int)
    m = a[..., 3] > 128
    lum = a[..., :3].mean(axis=2)
    h = m.shape[0]
    dark = m & (lum < 50)
    dark[int(h * 0.6):] = False
    if dark.sum() < 4:
        return None
    return np.where(dark)[1].mean() >= np.where(m)[1].mean()


def mask_of(img, w, h):
    return np.array(img.split()[3].resize((w, h), Image.BILINEAR)) > 110


def dirs(theta):
    t = math.radians(theta)
    D = np.array([math.sin(t), 0.0, -math.cos(t)])   # direction de la camera (depuis le pet)
    right = np.array([D[2], 0.0, -D[0]])             # droite de l'image
    return D, right


def build(name, grid):
    front, q, side, back, qb = (load(name, v) for v in ("front", "q", "side", "back", "qb"))
    # oriente les vues de cote pour que le museau soit a droite (angles positifs)
    fr = face_right(side)
    if fr is False:
        side = side.transpose(Image.FLIP_LEFT_RIGHT)
    fq = face_right(q)
    if fq is False:
        q = q.transpose(Image.FLIP_LEFT_RIGHT)
    fqb = face_right(qb)
    if fqb is False or (fqb is None and fq is False):
        qb = qb.transpose(Image.FLIP_LEFT_RIGHT)

    s = grid / VIEW_H
    nx, nz, ny = max(4, round(front.width * s)), max(4, round(side.width * s)), grid
    Mf = mask_of(front, nx, ny)
    Ms = mask_of(side, nz, ny)[:, ::-1]  # colonne 0 = museau (-Z)
    xc = np.zeros((ny, nx)); hx = np.ones((ny, nx)); zc = np.zeros((ny, nz)); hz = np.ones((ny, nz))
    for y in range(ny):
        xc[y], hx[y] = runs(Mf[y])
        zc[y], hz[y] = runs(Ms[y])
    X = np.arange(nx)[None, :, None]; Z = np.arange(nz)[None, None, :]
    ell = ((X - xc[:, :, None]) / (hx[:, :, None] + 0.35)) ** 2 + ((Z - zc[:, None, :]) / (hz[:, None, :] + 0.35)) ** 2
    occ = Mf[:, :, None] & Ms[:, None, :] & (ell <= 1.0)

    # coordonnees monde de chaque voxel
    unit = HEIGHT / grid
    gy, gx, gz = np.meshgrid(np.arange(ny), np.arange(nx), np.arange(nz), indexing="ij")
    W = np.stack([-(gx - (nx - 1) / 2) * unit, (ny - 1 - gy) * unit, (gz - (nz - 1) / 2) * unit], -1)

    # sculpte avec les vues de 3/4 (et leurs miroirs)
    views = {45: q, 135: qb, -45: q.transpose(Image.FLIP_LEFT_RIGHT), -135: qb.transpose(Image.FLIP_LEFT_RIGHT)}
    for theta, img in (views.items() if USE_QUARTER_VIEWS else []):
        _, right = dirs(theta)
        hcoord = W @ right
        hv = hcoord[occ]
        if len(hv) == 0:
            continue
        h0, h1 = hv.min(), hv.max()
        vw = max(4, round(img.width * s))
        M = mask_of(img, vw, ny)
        M = np.array(Image.fromarray((M * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
        col = np.clip(((hcoord - h0) / max(h1 - h0, 1e-6) * (vw - 1)).round().astype(int), 0, vw - 1)
        keep = M[gy, col]
        occ &= keep

    f = np.pad(occ.astype(float), 2)
    for _ in range(3):
        g = f.copy()
        for ax in range(3):
            g = (np.roll(g, 1, ax) + g * 2 + np.roll(g, -1, ax)) / 4
        f = g
    verts, quads, outs = surface_nets(f)
    nb = [[] for _ in range(len(verts))]
    for qd in quads:
        for k in range(4):
            nb[qd[k]].append(qd[(k + 1) % 4]); nb[qd[k]].append(qd[(k + 3) % 4])
    for _ in range(6):
        new = verts.copy()
        for i, n in enumerate(nb):
            if n:
                new[i] = 0.5 * verts[i] + 0.5 * verts[n].mean(0)
        verts = new
    vy, vx, vz = verts[:, 0] - 2, verts[:, 1] - 2, verts[:, 2] - 2
    pos = np.stack([-(vx - (nx - 1) / 2) * unit, (ny - 1 - vy) * unit, (vz - (nz - 1) / 2) * unit], 1).astype(np.float32)
    pos[:, 1] -= pos[:, 1].min()
    tris = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]])
    out_dir = np.concatenate([outs, outs])
    out_world = np.stack([-out_dir[:, 1], -out_dir[:, 0], out_dir[:, 2]], 1)
    p0, p1, p2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    wrong = np.einsum("ij,ij->i", fn, out_world) < 0
    tris[wrong] = tris[wrong][:, ::-1]
    fn[wrong] = -fn[wrong]
    # normales lissees pour choisir la vue (evite les changements brusques)
    vn = np.zeros_like(pos)
    for k in range(3):
        np.add.at(vn, tris[:, k], fn)
    tn = vn[tris].sum(1)
    tn /= np.maximum(np.linalg.norm(tn, axis=1, keepdims=True), 1e-9)

    # 8 directions : angle, image
    if USE_QUARTER_VIEWS:
        tiles = [(0, front), (45, q), (90, side), (135, qb), (180, back),
                 (-135, qb.transpose(Image.FLIP_LEFT_RIGHT)), (-90, side.transpose(Image.FLIP_LEFT_RIGHT)), (-45, q.transpose(Image.FLIP_LEFT_RIGHT))]
    else:
        tiles = [(0, front), (90, side), (180, back), (-90, side.transpose(Image.FLIP_LEFT_RIGHT))]
    Ds = np.array([dirs(t)[0] for t, _ in tiles])
    choice = np.argmax(tn @ Ds.T, axis=1)
    ymin, ymax = pos[:, 1].min(), pos[:, 1].max()
    proj = []
    for t, _ in tiles:
        _, right = dirs(t)
        h = pos @ right
        proj.append((h - h.min()) / max(h.max() - h.min(), 1e-6))
    out_pos, out_uv, out_tris, remap = [], [], [], {}
    for tri, k in zip(tris, choice):
        nt = []
        for vi in tri:
            key = (int(vi), int(k))
            if key not in remap:
                u = np.clip(proj[k][vi], 0.003, 0.997)
                v = np.clip((ymax - pos[vi, 1]) / (ymax - ymin), 0.003, 0.997)
                remap[key] = len(out_pos)
                out_pos.append(pos[vi])
                out_uv.append(((k % 4 + u) / 4, (k // 4 + v) / 2))
            nt.append(remap[key])
        out_tris.append(nt)
    pos2 = np.array(out_pos, np.float32); uv2 = np.array(out_uv, np.float32); tris2 = np.array(out_tris, np.uint32)
    nrm = np.zeros_like(pos2)
    a, b, c = pos2[tris2[:, 0]], pos2[tris2[:, 1]], pos2[tris2[:, 2]]
    n = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(nrm, tris2[:, k], n)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)

    atlas = Image.new("RGB", (TILE * 4, TILE * 2))
    for k, (_, img) in enumerate(tiles):
        arr = np.array(img).astype(float)
        solid = np.array(Image.fromarray(((arr[..., 3] > 200) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) > 0
        rgb = bleed(arr[..., :3], solid, iters=30)
        im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize((TILE, TILE), Image.LANCZOS)
        im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=70, threshold=2))
        atlas.paste(im, ((k % 4) * TILE, (k // 4) * TILE))
    return pos2, nrm, uv2, tris2, atlas


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or NAMES
    built = []
    for name in names:
        grid = BASE_GRID
        res = build(name, grid)
        while len(res[3]) > MAX_TRIS and grid > 32:
            grid -= 4
            res = build(name, grid)
        pos, nrm, uv, tris, atlas = res
        write_glb(os.path.join(OUT, name + ".glb"), pos, nrm, uv, tris, atlas)
        views = [render(pos, nrm, uv, tris, atlas, yaw) for yaw in (180, 145, 90, 35, 0)]
        sheet = Image.new("RGB", (300 * len(views), 300))
        for k, im in enumerate(views):
            sheet.paste(im, (300 * k, 0))
        sheet.save(os.path.join(OUT, name + "_apercu.png"))
        built.append((name, pos, nrm, uv, tris, atlas))
        print(f"{name}: {len(pos)} sommets, {len(tris)} triangles (grille {grid})")
    if not sys.argv[1:]:
        write_combined_glb(os.path.join(OUT, "TousLesPets.glb"), built)
        print("-> TousLesPets.glb")


if __name__ == "__main__":
    main()
