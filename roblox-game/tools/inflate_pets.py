#!/usr/bin/env python3
"""Transforme chaque image de pet (assets/pets/*.png) en vrai modele 3D "peluche" (.glb).

Principe : la silhouette de l'image est gonflee (epaisseur = racine de la distance au bord),
la face avant porte le dessin, la face arriere une version floutee sans les yeux, et les deux
faces sont soudees sur le contour. Sortie : assets/pets_glb/<Nom>.glb (texture integree),
a importer dans Roblox Studio (Fichier > Importer 3D). Le pet regarde vers -Z, sol a Y = 0.
Usage : python3 tools/inflate_pets.py [Nom ...]
"""
import io
import json
import math
import os
import struct
import sys
from collections import deque
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "pets")
OUT = os.path.join(ROOT, "assets", "pets_glb")

GRID = 78          # resolution du maillage (cellules sur le cote)
HEIGHT = 4.2       # hauteur du pet en studs
DEPTH = 0.62       # epaisseur maximale relative a la largeur
TEX = 512


def distance_inside(mask):
    """Distance (en cellules) de chaque cellule au bord de la silhouette."""
    h, w = mask.shape
    d = np.full((h, w), np.inf)
    q = deque()
    for y in range(h):
        for x in range(w):
            if not mask[y, x]:
                d[y, x] = 0
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx, c in ((1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and d[ny, nx] > d[y, x] + c:
                d[ny, nx] = d[y, x] + c
                q.append((ny, nx))
    return d


def bleed(rgb, known, alpha_limit=None, iters=60):
    """Prolonge les couleurs connues vers les pixels inconnus (evite les bords noirs)."""
    filled = rgb.copy()
    known = known.copy()
    for _ in range(iters):
        todo = ~known if alpha_limit is None else (alpha_limit & ~known)
        if not todo.any():
            break
        img_k = Image.fromarray(np.where(known[..., None], filled, 0).astype(np.uint8))
        cnt = Image.fromarray((known * 255).astype(np.uint8))
        s = np.array(img_k.filter(ImageFilter.BoxBlur(2))).astype(float)
        c = np.array(cnt.filter(ImageFilter.BoxBlur(2))).astype(float) / 255
        new = (c > 0.02) & todo
        filled[new] = s[new] / np.maximum(c[new, None], 1e-3)
        known |= new
    return filled


def back_texture(img):
    """Dos du pet : couleurs du corps sans les yeux ni les traits du visage."""
    rgba = np.array(img).astype(float)
    rgb = rgba[..., :3]
    alpha = rgba[..., 3] > 128
    grey = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    # yeux, contours, reflets : pixels tres sombres ou blancs purs -> a remplacer
    bad = alpha & ((grey < 115) | ((grey > 240) & (sat < 16)))
    bad = np.array(Image.fromarray((bad * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(13))) > 0
    good = alpha & ~bad
    filled = bleed(rgb, good, alpha_limit=alpha, iters=80)
    filled = bleed(filled, alpha, iters=40)
    out = Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(7))
    out = Image.fromarray(np.clip(np.array(out).astype(float) * 0.92, 0, 255).astype(np.uint8))
    return out


def build(name):
    img = Image.open(os.path.join(SRC, name + ".png")).convert("RGBA").resize((TEX, TEX), Image.LANCZOS)
    a = np.array(img)[..., 3]
    ys, xs = np.where(a > 100)
    # cadre serre autour du pet
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    bx0, by0 = cx - side / 2, cy - side / 2
    cell = side / GRID
    gx = bx0 + (np.arange(GRID + 1)) * cell  # coordonnees pixel des sommets
    gy = by0 + (np.arange(GRID + 1)) * cell
    # masque aux sommets (echantillonnage alpha)
    def sample_alpha(px, py):
        xi = np.clip(np.round(px).astype(int), 0, TEX - 1)
        yi = np.clip(np.round(py).astype(int), 0, TEX - 1)
        return a[yi, xi]
    PX, PY = np.meshgrid(gx, gy)
    inside = sample_alpha(PX, PY) > 110
    d = distance_inside(np.pad(inside, 1))[1:-1, 1:-1]
    dmax = d.max()
    width_units = HEIGHT * side / (y1 - y0)  # unites par cote de cadre
    scale = width_units / GRID
    zmax = DEPTH * width_units * 0.5
    # profil arrondi : epais au centre, fin sur les bords (oreilles, pattes)
    z = zmax * np.sqrt(np.clip(d / dmax, 0, 1)) ** 1.0
    for _ in range(2):  # lissage
        zp = np.pad(z, 1, mode="edge")
        z = (zp[:-2, 1:-1] + zp[2:, 1:-1] + zp[1:-1, :-2] + zp[1:-1, 2:] + 2 * zp[1:-1, 1:-1]) / 6
    z = np.where(inside, np.maximum(z, 0.03), 0)

    # direction vers l'interieur (gradient de la distance au bord), pour les UV du contour
    gdy, gdx = np.gradient(d)
    gn = np.maximum(np.hypot(gdx, gdy), 1e-6)
    inward_x, inward_y = gdx / gn, gdy / gn

    # sommets
    vid_f = -np.ones((GRID + 1, GRID + 1), int)
    vid_b = -np.ones((GRID + 1, GRID + 1), int)
    pos, uv = [], []
    ground = None
    for j in range(GRID + 1):
        for i in range(GRID + 1):
            if inside[j, i]:
                x = (i - GRID / 2) * scale
                y = (GRID - j) * scale
                # pres du bord, la couleur est prise un peu a l'interieur (evite le contour sombre)
                pull = max(0.0, 3.2 - d[j, i]) * cell * 1.6
                u = (gx[i] + inward_x[j, i] * pull) / TEX
                v = (gy[j] + inward_y[j, i] * pull) / TEX
                edge = d[j, i] <= 1.01
                vid_f[j, i] = len(pos)
                pos.append((x, y, -z[j, i]))
                uv.append((u * 0.5, v))
                # le dos a ses propres sommets (meme position sur le contour, UV du dos)
                vid_b[j, i] = len(pos)
                pos.append((x, y, 0.0 if edge else z[j, i] * 0.85))
                if edge:
                    pos[-2] = (x, y, 0.0)
                uv.append((0.5 + u * 0.5, v))
    pos = np.array(pos, np.float32)
    # adoucit l'escalier du contour : moyenne avec les voisins du bord
    edge_ids = {}
    for j in range(GRID + 1):
        for i in range(GRID + 1):
            if inside[j, i] and d[j, i] <= 1.01:
                edge_ids[(j, i)] = vid_f[j, i]
    ring2 = {}
    for j in range(GRID + 1):
        for i in range(GRID + 1):
            if inside[j, i] and 1.01 < d[j, i] <= 2.5:
                ring2[(j, i)] = (vid_f[j, i], vid_b[j, i])
    for _ in range(3):
        new = {}
        for (j, i), vid in edge_ids.items():
            acc = [pos[vid, :2]]
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    nb = edge_ids.get((j + dj, i + di))
                    if nb is not None and nb != vid:
                        acc.append(pos[nb, :2])
            new[vid] = np.mean(acc, axis=0)
        for vid, xy in new.items():
            pos[vid, :2] = xy
    for (j, i), vid in edge_ids.items():
        pos[vid_b[j, i], :2] = pos[vid, :2]
    for (j, i), (vf, vb) in ring2.items():
        acc = []
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                nb = edge_ids.get((j + dj, i + di))
                if nb is not None:
                    acc.append(pos[nb, :2])
        if acc:
            xy = 0.5 * pos[vf, :2] + 0.5 * np.mean(acc, axis=0)
            pos[vf, :2] = xy
            pos[vb, :2] = xy
    pos[:, 1] -= pos[:, 1].min()
    tris = []
    for j in range(GRID):
        for i in range(GRID):
            q = [(j, i), (j, i + 1), (j + 1, i + 1), (j + 1, i)]
            ins = [inside[p] for p in q]
            if sum(ins) < 3:
                continue
            f = [vid_f[p] for p in q]
            b = [vid_b[p] for p in q]
            if all(ins):
                # face avant (normale vers -Z) puis face arriere
                tris += [(f[0], f[1], f[2]), (f[0], f[2], f[3])]
                tris += [(b[0], b[2], b[1]), (b[0], b[3], b[2])]
            else:
                k = ins.index(False)
                r = [q[(k + 1) % 4], q[(k + 2) % 4], q[(k + 3) % 4]]
                fi = [vid_f[p] for p in r]
                bi = [vid_b[p] for p in r]
                tris.append((fi[0], fi[1], fi[2]))
                tris.append((bi[0], bi[2], bi[1]))
    tris = np.array(tris, np.uint32)
    # supprime les triangles degeneres (contour soude)
    ok = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 0] != tris[:, 2])
    tris = tris[ok]
    # normales lissees
    nrm = np.zeros_like(pos)
    p0, p1, p2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    for k in range(3):
        np.add.at(nrm, tris[:, k], fn)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    # contour : normale horizontale vers l'exterieur (les faces avant/arriere s'annuleraient)
    for j in range(GRID + 1):
        for i in range(GRID + 1):
            if inside[j, i] and d[j, i] <= 1.01:
                nx, ny = -inward_x[j, i], inward_y[j, i]  # image : y vers le bas
                l = math.hypot(nx, ny) or 1
                nrm[vid_f[j, i]] = (nx / l, ny / l, 0.0)
                nrm[vid_b[j, i]] = (nx / l, ny / l, 0.0)

    # texture : dessin a gauche, dos a droite
    atlas = Image.new("RGB", (TEX * 2, TEX))
    arr = np.array(img).astype(float)
    solid = arr[..., 3] > 200
    # contour : on prolonge les couleurs franches de l'interieur vers l'exterieur
    front = bleed(arr[..., :3], solid, iters=40)
    atlas.paste(Image.fromarray(np.clip(front, 0, 255).astype(np.uint8)), (0, 0))
    atlas.paste(back_texture(img), (TEX, 0))
    return pos, nrm, np.array(uv, np.float32), tris, atlas


def write_glb(path, pos, nrm, uv, tris, atlas):
    png = io.BytesIO()
    atlas.save(png, "PNG", optimize=True)
    png = png.getvalue()
    parts = [pos.tobytes(), nrm.astype(np.float32).tobytes(), uv.tobytes(), tris.astype(np.uint32).tobytes(), png]
    views, offset, blob = [], 0, b""
    for i, p in enumerate(parts):
        pad = (-len(blob)) % 4
        blob += b"\0" * pad
        offset = len(blob)
        blob += p
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(p)}
        if i < 3:
            view["target"] = 34962
        elif i == 3:
            view["target"] = 34963
        views.append(view)
    blob += b"\0" * ((-len(blob)) % 4)
    gltf = {
        "asset": {"version": "2.0", "generator": "PetRush inflate_pets.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": os.path.splitext(os.path.basename(path))[0]}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.8}, "doubleSided": False}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987}],
        "images": [{"bufferView": 4, "mimeType": "image/png"}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": int(tris.size), "type": "SCALAR"},
        ],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


def write_combined_glb(path, pets):
    """Un seul fichier avec tous les pets (un noeud nomme par pet), cote a cote."""
    blob = b""
    views, accessors, meshes, nodes, materials, textures, images = [], [], [], [], [], [], []

    def add_view(data, target=None):
        nonlocal blob
        blob += b"\0" * ((-len(blob)) % 4)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        blob += data
        views.append(view)
        return len(views) - 1

    for k, (name, pos, nrm, uv, tris, atlas) in enumerate(pets):
        png = io.BytesIO()
        atlas.save(png, "PNG", optimize=True)
        vp = add_view(pos.tobytes(), 34962)
        vn = add_view(nrm.astype(np.float32).tobytes(), 34962)
        vt = add_view(uv.tobytes(), 34962)
        vi = add_view(tris.astype(np.uint32).tobytes(), 34963)
        vimg = add_view(png.getvalue())
        a0 = len(accessors)
        accessors += [
            {"bufferView": vp, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": vn, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": vt, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": vi, "componentType": 5125, "count": int(tris.size), "type": "SCALAR"},
        ]
        images.append({"bufferView": vimg, "mimeType": "image/png", "name": name})
        textures.append({"source": len(images) - 1, "sampler": 0})
        materials.append({"name": name, "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures) - 1}, "metallicFactor": 0.0, "roughnessFactor": 0.8}})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a0, "NORMAL": a0 + 1, "TEXCOORD_0": a0 + 2}, "indices": a0 + 3, "material": len(materials) - 1}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1, "translation": [(k % 5) * 7.0, 0.0, (k // 5) * 7.0]})
    blob += b"\0" * ((-len(blob)) % 4)
    gltf = {
        "asset": {"version": "2.0", "generator": "PetRush inflate_pets.py"},
        "scene": 0,
        "scenes": [{"name": "TousLesPets", "nodes": list(range(len(nodes)))}],
        "nodes": nodes, "meshes": meshes, "materials": materials, "textures": textures,
        "samplers": [{"magFilter": 9729, "minFilter": 9987}], "images": images,
        "accessors": accessors, "buffers": [{"byteLength": len(blob)}], "bufferViews": views,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


# ------------------------------------------------------------- apercu (rasteriseur)
def render(pos, nrm, uv, tris, atlas, yaw_deg, size=300, pitch_deg=12):
    tex = np.array(atlas).astype(float) / 255
    th, tw, _ = tex.shape
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    R = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
    P = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
    c = pos - np.array([0, pos[:, 1].max() / 2, 0])
    v = c @ R.T @ P.T
    n = nrm @ R.T @ P.T
    s = size / (np.abs(v[:, :2]).max() * 2.3)
    sx = size / 2 + v[:, 0] * s
    sy = size / 2 - v[:, 1] * s
    depth = v[:, 2]  # camera regarde vers +Z (voit la face -Z)
    zbuf = np.full((size, size), np.inf)
    img = np.zeros((size, size, 3)) + np.array([0.42, 0.62, 0.95])
    L = np.array([-0.4, 0.7, -0.6]); L /= np.linalg.norm(L)
    for t in tris:
        a, b, cc = t
        xs = np.array([sx[a], sx[b], sx[cc]]); ys = np.array([sy[a], sy[b], sy[cc]])
        area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
        if area >= 0:  # face arriere vue de dos
            continue
        x0, x1 = int(max(0, xs.min())), int(min(size - 1, xs.max() + 1))
        y0, y1 = int(max(0, ys.min())), int(min(size - 1, ys.max() + 1))
        if x1 < x0 or y1 < y0:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((xs[1] - X) * (ys[2] - Y) - (xs[2] - X) * (ys[1] - Y)) / area
        w1 = ((xs[2] - X) * (ys[0] - Y) - (xs[0] - X) * (ys[2] - Y)) / area
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any():
            continue
        zz = w0 * depth[a] + w1 * depth[b] + w2 * depth[cc]
        Yi, Xi = Y.astype(int), X.astype(int)
        cur = zbuf[Yi, Xi]
        m &= zz < cur
        if not m.any():
            continue
        uu = w0 * uv[a, 0] + w1 * uv[b, 0] + w2 * uv[cc, 0]
        vv = w0 * uv[a, 1] + w1 * uv[b, 1] + w2 * uv[cc, 1]
        nn = w0[..., None] * n[a] + w1[..., None] * n[b] + w2[..., None] * n[cc]
        nn /= np.maximum(np.linalg.norm(nn, axis=2, keepdims=True), 1e-9)
        col = tex[np.clip((vv * th).astype(int), 0, th - 1), np.clip((uu * tw).astype(int), 0, tw - 1)]
        lam = np.clip((nn * L).sum(2), 0, 1)
        shade = col * (0.62 + 0.45 * lam[..., None])
        zbuf[Yi[m], Xi[m]] = zz[m]
        img[Yi[m], Xi[m]] = np.clip(shade[m], 0, 1)
    return Image.fromarray((img * 255).astype(np.uint8))


def main():
    os.makedirs(OUT, exist_ok=True)
    args = sys.argv[1:]
    combined_only = args == ["--combined"]
    names = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".png")) if (not args or combined_only) else args
    built = []
    for name in names:
        pos, nrm, uv, tris, atlas = build(name)
        built.append((name, pos, nrm, uv, tris, atlas))
        if combined_only:
            print(f"{name}: pret")
            continue
        write_glb(os.path.join(OUT, name + ".glb"), pos, nrm, uv, tris, atlas)
        views = [render(pos, nrm, uv, tris, atlas, yaw) for yaw in (180, 145, 90, 35, 0)]
        sheet = Image.new("RGB", (300 * len(views), 300))
        for k, im in enumerate(views):
            sheet.paste(im, (300 * k, 0))
        sheet.save(os.path.join(OUT, name + "_apercu.png"))
        print(f"{name}: {len(pos)} sommets, {len(tris)} triangles")
    if not args or combined_only:
        write_combined_glb(os.path.join(OUT, "TousLesPets.glb"), built)
        print("-> TousLesPets.glb (les 19 pets dans un seul fichier)")


if __name__ == "__main__":
    main()
