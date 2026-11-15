#!/usr/bin/env python3
"""Rendu logiciel (rasterisation z-buffer, couleurs par sommet interpolees) pour verifier les pets sculptes."""
import math
import numpy as np
from PIL import Image

def look(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    return Rx @ Ry

def render(meshes, size=512, yaw=-30, pitch=-12, bg=(236, 242, 250), ssaa=2, center=None, extent=None):
    """meshes: liste de (V, N, C, T). Camera orthographique regardant le pet de face (-Z) tourne de yaw."""
    S = size * ssaa
    R = look(yaw, pitch)
    allV = np.concatenate([m[0] for m in meshes])
    if center is None:
        lo, hi = allV.min(0), allV.max(0); center = (lo + hi) / 2
    if extent is None:
        extent = np.linalg.norm(allV.max(0) - allV.min(0)) * 0.56
    scale = S / (2 * extent)
    zbuf = np.full(S * S, np.inf)
    nbuf = np.zeros((S * S, 3)); cbuf = np.zeros((S * S, 3))
    for V, N, C, T in meshes:
        # vue de face : le pet regarde -Z, la camera est en -Z et regarde vers +Z
        Q = (V - center) @ R.T
        sx = S / 2 - Q[:, 0] * scale      # x monde vers la gauche de l'ecran (on regarde le pet de face)
        sy = S / 2 - Q[:, 1] * scale
        sz = Q[:, 2]                      # plus petit = plus proche (camera cote -Z)
        Nr = N @ R.T
        a, b, c = T[:, 0], T[:, 1], T[:, 2]
        x0, x1, x2 = sx[a], sx[b], sx[c]; y0, y1, y2 = sy[a], sy[b], sy[c]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        keep = np.abs(area) > 1e-9
        T = T[keep]; a, b, c = T[:, 0], T[:, 1], T[:, 2]
        x0, x1, x2 = sx[a], sx[b], sx[c]; y0, y1, y2 = sy[a], sy[b], sy[c]; area = area[keep]
        minx = np.floor(np.minimum(np.minimum(x0, x1), x2)).astype(int)
        maxx = np.ceil(np.maximum(np.maximum(x0, x1), x2)).astype(int)
        miny = np.floor(np.minimum(np.minimum(y0, y1), y2)).astype(int)
        maxy = np.ceil(np.maximum(np.maximum(y0, y1), y2)).astype(int)
        w = maxx - minx + 1; h = maxy - miny + 1
        ok = (w < 600) & (h < 600) & (maxx >= 0) & (minx < S) & (maxy >= 0) & (miny < S)
        idx = np.nonzero(ok)[0]
        cnt = (w * h)[idx]
        tri = np.repeat(idx, cnt)
        off = np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt)
        px = minx[tri] + off % w[tri] ; py = miny[tri] + off // w[tri]
        cx = px + 0.5; cy = py + 0.5
        l1 = ((x2[tri] - cx) * (y0[tri] - cy) - (x0[tri] - cx) * (y2[tri] - cy)) / area[tri]
        l2 = ((x0[tri] - cx) * (y1[tri] - cy) - (x1[tri] - cx) * (y0[tri] - cy)) / area[tri]
        l0 = 1 - l1 - l2
        inside = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6) & (px >= 0) & (px < S) & (py >= 0) & (py < S)
        tri, px, py, l0, l1, l2 = tri[inside], px[inside], py[inside], l0[inside], l1[inside], l2[inside]
        A, B, Cc = T[tri, 0], T[tri, 1], T[tri, 2]
        z = l0 * sz[A] + l1 * sz[B] + l2 * sz[Cc]
        pix = py * S + px
        order = np.lexsort((z, pix))
        pix, z = pix[order], z[order]
        first = np.ones(len(pix), bool); first[1:] = pix[1:] != pix[:-1]
        sel = order[first]; pix = pix[first]; z = z[first]
        better = z < zbuf[pix]
        sel, pix, z = sel[better], pix[better], z[better]
        zbuf[pix] = z
        L0, L1, L2 = l0[sel][:, None], l1[sel][:, None], l2[sel][:, None]
        A, B, Cc = A[sel], B[sel], Cc[sel]
        nbuf[pix] = L0 * Nr[A] + L1 * Nr[B] + L2 * Nr[Cc]
        cbuf[pix] = L0 * C[A] + L1 * C[B] + L2 * C[Cc]
    hit = np.isfinite(zbuf)
    n = nbuf[hit]; n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    col = cbuf[hit]
    # eclairage type Roblox cartoon : cle + remplissage + rim + speculaire doux
    key = np.array([-0.45, 0.75, -0.5]); key /= np.linalg.norm(key)
    fill = np.array([0.6, 0.2, -0.4]); fill /= np.linalg.norm(fill)
    view = np.array([0, 0, -1.0])
    dk = np.clip(n @ key, 0, 1); df = np.clip(n @ fill, 0, 1)
    rim = np.clip(1 - np.abs(n @ view), 0, 1) ** 3
    hv = key + view; hv /= np.linalg.norm(hv)
    spec = np.clip(n @ hv, 0, 1) ** 40
    sky = 0.5 + 0.5 * n[:, 1]
    lit = col * (0.42 + 0.18 * sky[:, None] + 0.55 * dk[:, None] + 0.15 * df[:, None]) + 0.25 * rim[:, None] + 0.22 * spec[:, None]
    img = np.empty((S * S, 3)); img[:] = np.array(bg) / 255
    img[hit] = np.clip(lit, 0, 1)
    # contour (silhouette + discontinuites de profondeur)
    zb = zbuf.reshape(S, S); hm = hit.reshape(S, S)
    zz = np.where(hm, zb, 1e9)
    edge = np.zeros((S, S), bool)
    thr = extent * 0.06
    for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        sh = np.roll(np.roll(zz, dy, 0), dx, 1)
        edge |= (np.abs(sh - zz) > thr) & (zz < sh)
    edge |= hm & ~(np.roll(hm, 1, 0) & np.roll(hm, -1, 0) & np.roll(hm, 1, 1) & np.roll(hm, -1, 1))
    img = img.reshape(S, S, 3)
    img[edge] = img[edge] * 0.35 + np.array([40, 28, 40]) / 255 * 0.65
    im = Image.fromarray((img * 255).astype(np.uint8))
    return im.resize((size, size), Image.LANCZOS)
